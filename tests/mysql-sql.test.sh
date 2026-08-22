#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
blocker_job=""
waiter_job=""
reader_job=""

root_mysql=(docker exec -e MYSQL_PWD=hazel-root-dev-only hazel-mysql mysql -uroot -Dhazel --batch --raw --skip-column-names --silent)
monitor_mysql=(docker exec -e MYSQL_PWD=hazel-dev-only hazel-mysql mysql -uhazel -Dhazel --batch --raw --skip-column-names --silent)

cleanup() {
  "${root_mysql[@]}" -e "SELECT CONCAT('KILL ', ID, ';') FROM performance_schema.processlist WHERE USER = 'root' AND ID <> CONNECTION_ID() AND COMMAND <> 'Sleep'" 2>/dev/null \
    | "${root_mysql[@]}" 2>/dev/null || true
  for job in "$blocker_job" "$waiter_job" "$reader_job"; do
    if [[ -n "$job" ]]; then
      kill "$job" >/dev/null 2>&1 || true
      wait "$job" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

docker compose -f "$repo_dir/compose.yaml" up -d --wait mysql >/dev/null

if rg -n -i '^\s*(insert|update|delete|replace|create|alter|drop|truncate|grant|revoke|call|do|set)\b' "$repo_dir/mysql/summary.sql" "$repo_dir/mysql/details.sql"; then
  echo "MySQL collectors must remain SELECT-only" >&2
  exit 1
fi

grants=$("${monitor_mysql[@]}" -e "SHOW GRANTS FOR CURRENT_USER()")
if grep -Eq 'ALL PRIVILEGES|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER' <<<"$grants"; then
  echo "MySQL fixture monitoring account has write privileges" >&2
  exit 1
fi

summary=$(docker exec -i -e MYSQL_PWD=hazel-dev-only hazel-mysql mysql -uhazel -Dhazel --batch --raw --skip-column-names --silent < "$repo_dir/mysql/summary.sql")

jq -e '
  .schema == 1 and
  .kind == "summary" and
  .engine == "mysql" and
  .identity.database == "hazel" and
  (.identity.version | startswith("8.4.")) and
  .capabilities.performanceSchema == 1 and
  (.connections.max > 0) and
  (.counters.workTotal >= 0) and
  (.counters.logBytes >= 0) and
  .maintenance.kind == "purge" and
  .maintenance.backlogLabel == "PURGE DEBT" and
  (.maintenance.backlog >= 0) and
  (.maintenance.workerCount >= 1)
' <<<"$summary" >/dev/null

"${root_mysql[@]}" -e "SELECT * FROM accounts; UPDATE accounts SET balance = balance WHERE id = 4" >/dev/null

"${root_mysql[@]}" -e "START TRANSACTION; UPDATE accounts SET balance=1111.11 WHERE id=1; SELECT SLEEP(30); ROLLBACK" >/dev/null 2>&1 &
blocker_job=$!
for _ in {1..50}; do
  [[ $("${root_mysql[@]}" -e "SELECT COUNT(*) FROM information_schema.innodb_trx") -ge 1 ]] && break
  sleep 0.1
done

"${root_mysql[@]}" -e "START TRANSACTION; UPDATE accounts SET balance=2222.22 WHERE id=1; ROLLBACK" >/dev/null 2>&1 &
waiter_job=$!
for _ in {1..50}; do
  [[ $("${root_mysql[@]}" -e "SELECT COUNT(*) FROM performance_schema.data_lock_waits") -ge 1 ]] && break
  sleep 0.1
done

locked_summary=$(docker exec -i -e MYSQL_PWD=hazel-dev-only hazel-mysql mysql -uhazel -Dhazel --batch --raw --skip-column-names --silent < "$repo_dir/mysql/summary.sql")
details=$(docker exec -i -e MYSQL_PWD=hazel-dev-only hazel-mysql mysql -uhazel -Dhazel --batch --raw --skip-column-names --silent < "$repo_dir/mysql/details.sql")

jq -e '.connections.blocked >= 1 and .connections.lockWaiting >= 1 and .connections.oldestLockWaitSeconds >= 0' <<<"$locked_summary" >/dev/null
jq -e '
  .schema == 1 and
  .kind == "details" and
  (.activity | length >= 2) and
  (all(.activity[]; .state != "sleep")) and
  (any(.activity[]; .queryText | contains("accounts"))) and
  (all(.activity[]; (.queryText | contains("1111.11") or contains("2222.22")) | not)) and
  (.relations | length >= 1) and
  (.relations[0].rowsChanged >= 0) and
  (.blocking | length >= 1) and
  .blocking[0].waitType == "DATA" and
  (.blocking[0].lockMode | type == "string") and
  .blocking[0].lockTarget == "hazel.accounts" and
  (.maintenance | length >= 1)
' <<<"$details" >/dev/null

cleanup
blocker_job=""
waiter_job=""

baseline=$("${monitor_mysql[@]}" -e "SELECT COUNT FROM information_schema.innodb_metrics WHERE NAME='trx_rseg_history_len'")
"${root_mysql[@]}" -e "START TRANSACTION WITH CONSISTENT SNAPSHOT; SELECT COUNT(*) FROM accounts; SELECT SLEEP(5); COMMIT" >/dev/null 2>&1 &
reader_job=$!
for _ in {1..50}; do
  [[ $("${root_mysql[@]}" -e "SELECT COUNT(*) FROM information_schema.innodb_trx") -ge 1 ]] && break
  sleep 0.1
done
updates=""
for value in $(seq 1 100); do
  updates+="UPDATE accounts SET balance = 1000 + $value WHERE id = 1;"
done
"${root_mysql[@]}" -e "$updates" >/dev/null
during=$("${monitor_mysql[@]}" -e "SELECT COUNT FROM information_schema.innodb_metrics WHERE NAME='trx_rseg_history_len'")
if (( during <= baseline )); then
  echo "Expected purge debt to grow while a consistent snapshot was held ($baseline -> $during)" >&2
  exit 1
fi

wait "$reader_job"
reader_job=""
after=$("${monitor_mysql[@]}" -e "SELECT COUNT FROM information_schema.innodb_metrics WHERE NAME='trx_rseg_history_len'")

printf 'Hazel MySQL snapshots passed on MySQL %s; lock edge captured; held-snapshot purge debt grew %s -> %s (post-release sample %s)\n' \
  "$("${monitor_mysql[@]}" -e 'SELECT VERSION()')" "$baseline" "$during" "$after"
