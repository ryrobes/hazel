#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
container=hazel-clickhouse
active_job=""
root_clickhouse=(docker exec "$container" clickhouse-client --database hazel)
monitor_clickhouse=(docker exec -i -e CLICKHOUSE_PASSWORD=hazel-dev-only "$container" clickhouse-client --user hazel --database hazel --multiquery --format JSONEachRow)

cleanup() {
  "${root_clickhouse[@]}" --query "SYSTEM START MERGES hazel.hazel_clickhouse_test" >/dev/null 2>&1 || true
  "${root_clickhouse[@]}" --query "KILL QUERY WHERE query_id = 'hazel-test-active' SYNC" >/dev/null 2>&1 || true
  if [[ -n "$active_job" ]]; then
    kill "$active_job" >/dev/null 2>&1 || true
    wait "$active_job" >/dev/null 2>&1 || true
  fi
  "${root_clickhouse[@]}" --query "DROP TABLE IF EXISTS hazel.hazel_clickhouse_test" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker compose -f "$repo_dir/compose.yaml" up -d --wait clickhouse >/dev/null

if rg -n -i '^\s*(insert|update|delete|create|alter|drop|truncate|grant|revoke|kill|optimize|system|set)\b' \
  "$repo_dir/clickhouse/summary.sql" "$repo_dir/clickhouse/details.sql"; then
  echo "ClickHouse collectors must remain SELECT-only" >&2
  exit 1
fi

grants=$("${root_clickhouse[@]}" --query "SHOW GRANTS FOR hazel")
if grep -Eq 'ALL|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE|OPTIMIZE' <<<"$grants"; then
  echo "ClickHouse fixture monitoring account has write privileges" >&2
  exit 1
fi

summary=$("${monitor_clickhouse[@]}" < "$repo_dir/clickhouse/summary.sql")
jq -e '
  .schema == 1 and
  .kind == "summary" and
  .engine == "clickhouse" and
  .identity.database == "hazel" and
  .identity.family == "clickhouse" and
  (.identity.version | type == "string") and
  .capabilities.processes == 1 and
  .capabilities.merges == 1 and
  .capabilities.mutations == 1 and
  (.connections.max > 0) and
  (.counters.workTotal >= 0) and
  .counters.statsReset == null and
  .counters.logStatsReset == null and
  (.capacity.memoryUsed > 0) and
  (.capacity.memoryMax > .capacity.memoryUsed) and
  .maintenance.kind == "merge" and
  .maintenance.backlogLabel == "MERGE DEBT" and
  .maintenance.surfaceLabel == "PART SURFACE" and
  (.maintenance.activeParts >= 1)
' <<<"$summary" >/dev/null

persistent_responses=$(
  {
    sed '$a\' "$repo_dir/clickhouse/summary.sql"
    sed '$a\' "$repo_dir/clickhouse/details.sql"
  } | "${monitor_clickhouse[@]}"
)
jq -s -e 'length == 2 and .[0].kind == "summary" and .[1].kind == "details"' <<<"$persistent_responses" >/dev/null

"${root_clickhouse[@]}" --multiquery --query "
  DROP TABLE IF EXISTS hazel.hazel_clickhouse_test;
  CREATE TABLE hazel.hazel_clickhouse_test
  (
    event_time DateTime,
    account_id UInt64,
    event_kind LowCardinality(String),
    payload String
  )
  ENGINE = MergeTree
  ORDER BY (event_time, account_id);
  INSERT INTO hazel.hazel_clickhouse_test
  SELECT now(), number % 10000, 'fixture', repeat('x', 64) FROM numbers(250000);
  SYSTEM STOP MERGES hazel.hazel_clickhouse_test;
  INSERT INTO hazel.hazel_clickhouse_test
  SELECT now(), number % 10000, 'fixture', repeat('y', 64) FROM numbers(100000);
  INSERT INTO hazel.hazel_clickhouse_test
  SELECT now(), number % 10000, 'fixture', repeat('z', 64) FROM numbers(100000);
  ALTER TABLE hazel.hazel_clickhouse_test
  UPDATE payload = 'hazel-secret-4242'
  WHERE account_id = 4242
  SETTINGS mutations_sync = 0;
" >/dev/null

for _ in {1..50}; do
  pending=$("${root_clickhouse[@]}" --query "SELECT count() FROM system.mutations WHERE database = 'hazel' AND table = 'hazel_clickhouse_test' AND is_done = 0")
  [[ "$pending" -ge 1 ]] && break
  sleep 0.1
done

docker exec "$container" clickhouse-client --query_id hazel-test-active \
  --query "SELECT count() FROM numbers_mt(100000000000) WHERE cityHash64(number) % 97 = 0" >/dev/null 2>&1 &
active_job=$!
for _ in {1..50}; do
  active=$("${root_clickhouse[@]}" --query "SELECT count() FROM system.processes WHERE query_id = 'hazel-test-active'")
  [[ "$active" -eq 1 ]] && break
  sleep 0.1
done

debt_summary=$("${monitor_clickhouse[@]}" < "$repo_dir/clickhouse/summary.sql")
details=$("${monitor_clickhouse[@]}" < "$repo_dir/clickhouse/details.sql")

jq -e '
  .connections.active >= 1 and
  .maintenance.pendingMutations >= 1 and
  .maintenance.mutationParts >= 1 and
  .maintenance.backlog >= 1 and
  .maintenance.activeParts >= 3
' <<<"$debt_summary" >/dev/null

jq -e '
  .schema == 1 and
  .kind == "details" and
  (.activity | length >= 1) and
  (any(.activity[]; .queryId == "hazel-test-active")) and
  (any(.activity[]; .queryText | contains("cityHash64"))) and
  (all(.activity[]; (.queryText | contains("100000000000") or contains("97")) | not)) and
  (.relations | any(.relation == "hazel_clickhouse_test" and .parts >= 3 and .rows >= 450000)) and
  (.background | any(.kind == "mutation" and .table == "hazel_clickhouse_test" and .partsToDo >= 1 and .progress == null)) and
  (has("maintenance") | not) and
  (all(.background[]; ((.label + " " + .error) | contains("hazel-secret-4242") or contains("4242")) | not)) and
  .blocking == []
' <<<"$details" >/dev/null

cleanup
active_job=""
trap - EXIT

printf 'Hazel ClickHouse snapshots passed on %s; active query and queued mutation captured with literals masked\n' \
  "$(docker exec "$container" clickhouse-client --query 'SELECT version()')"
