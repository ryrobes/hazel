#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d /tmp/hazel-postgres-test.XXXXXX)
data_dir="$test_dir/data"
socket_dir="$test_dir/socket"
log_file="$test_dir/postgres.log"
port=55439
blocker_job=""
waiter_job=""
literal_job=""

mkdir -p "$socket_dir"

cleanup() {
  if [[ -n "$blocker_job" ]]; then
    kill "$blocker_job" >/dev/null 2>&1 || true
  fi
  if [[ -n "$waiter_job" ]]; then
    kill "$waiter_job" >/dev/null 2>&1 || true
  fi
  if [[ -n "$literal_job" ]]; then
    kill "$literal_job" >/dev/null 2>&1 || true
  fi
  if [[ -d "$data_dir" ]]; then
    pg_ctl -D "$data_dir" -m immediate stop >/dev/null 2>&1 || true
  fi
  rm -rf -- "$test_dir"
}
trap cleanup EXIT

initdb -D "$data_dir" -A trust --no-locale --encoding=UTF8 -U hazel_test >/dev/null
pg_ctl -D "$data_dir" -l "$log_file" \
  -o "-k $socket_dir -p $port -F -c listen_addresses=''" start >/dev/null

psql_base=(psql -X -w -qAt -h "$socket_dir" -p "$port" -U hazel_test)
createdb -h "$socket_dir" -p "$port" -U hazel_test hazel_test

"${psql_base[@]}" -d hazel_test <<'SQL'
CREATE TABLE events (id integer PRIMARY KEY, payload text);
INSERT INTO events SELECT value, repeat('x', 40) FROM generate_series(1, 1000) AS value;
DELETE FROM events WHERE id <= 120;
ANALYZE events;
CREATE TABLE lock_probe (id integer PRIMARY KEY, payload text);
INSERT INTO lock_probe VALUES (1, 'ready');
SQL

summary=$("${psql_base[@]}" -d hazel_test -f "$repo_dir/postgres/summary.sql")

PGAPPNAME=hazel-test-blocker "${psql_base[@]}" -d hazel_test >/dev/null 2>&1 <<'SQL' &
BEGIN;
UPDATE lock_probe SET payload = 'held-secret' WHERE id = 1;
SELECT pg_sleep(30);
ROLLBACK;
SQL
blocker_job=$!

for _ in {1..40}; do
  if [[ $("${psql_base[@]}" -d hazel_test -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'hazel-test-blocker' AND state = 'active'") == "1" ]]; then
    break
  fi
  sleep 0.1
done

PGAPPNAME=hazel-test-waiter "${psql_base[@]}" -d hazel_test >/dev/null 2>&1 <<'SQL' &
BEGIN;
UPDATE lock_probe SET payload = 'waiting-secret' WHERE id = 1;
ROLLBACK;
SQL
waiter_job=$!

for _ in {1..40}; do
  if [[ $("${psql_base[@]}" -d hazel_test -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'hazel-test-waiter' AND cardinality(pg_blocking_pids(pid)) > 0") == "1" ]]; then
    break
  fi
  sleep 0.1
done

PGAPPNAME=hazel-test-literal "${psql_base[@]}" -d hazel_test >/dev/null 2>&1 <<'SQL' &
SELECT pg_sleep(30), $$dollar-secret$$, $hazel$tagged-secret$hazel$;
SQL
literal_job=$!

for _ in {1..40}; do
  if [[ $("${psql_base[@]}" -d hazel_test -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'hazel-test-literal' AND state = 'active'") == "1" ]]; then
    break
  fi
  sleep 0.1
done

details=$("${psql_base[@]}" -d hazel_test -f "$repo_dir/postgres/details.sql")

jq -e '
  .schema == 1 and
  .kind == "summary" and
  .engine == "postgresql" and
  .identity.database == "hazel_test" and
  (.capabilities.pgRvbbit | type == "boolean") and
  .capabilities.pgRvbbit == false and
  (.connections.max > 0) and
  (.connections.lockWaiting >= 0) and
  (.connections.oldestLockWaitSeconds >= 0) and
  (.counters.xactCommit >= 0) and
  (.mvcc.deadTuples >= 0) and
  (.mvcc.autovacuumCount >= 0) and
  (.mvcc.vacuumCount >= 0) and
  (.mvcc.autovacuumWorkers >= 0) and
  (.mvcc.vacuumWorkers >= 0)
' <<<"$summary" >/dev/null

jq -e '
  .schema == 1 and
  .kind == "details" and
  (.activity | type == "array") and
  (.activity | length >= 2) and
  (all(.activity[]; .state == "active")) and
  (any(.activity[]; .queryText | contains("lock_probe"))) and
  (all(.activity[]; (.queryText | contains("held-secret") or contains("waiting-secret") or contains("dollar-secret") or contains("tagged-secret")) | not)) and
  (.relations | type == "array") and
  (.blocking | type == "array") and
  (.blocking | length >= 1) and
  (.blocking[0].lockMode | type == "string") and
  (.blocking[0].lockTarget | type == "string") and
  (.vacuum | type == "array")
' <<<"$details" >/dev/null

"${psql_base[@]}" -d hazel_test -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name IN ('hazel-test-blocker', 'hazel-test-waiter', 'hazel-test-literal')" >/dev/null
wait "$blocker_job" >/dev/null 2>&1 || true
blocker_job=""
wait "$waiter_job" >/dev/null 2>&1 || true
waiter_job=""
wait "$literal_job" >/dev/null 2>&1 || true
literal_job=""

printf 'Hazel PostgreSQL SQL snapshots passed on PostgreSQL %s\n' \
  "$("${psql_base[@]}" -d hazel_test -c 'show server_version')"
