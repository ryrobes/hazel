#!/usr/bin/env bash
set -euo pipefail

variant=${1:?usage: mysql-family-sql.test.sh mysql|mariadb|percona}
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
blocker_job=""
waiter_job=""
reader_job=""

case "$variant" in
  mysql)
    service=mysql
    container=hazel-mysql
    client=mysql
    sql_dir=mysql
    lock_wait_count="SELECT COUNT(*) FROM performance_schema.data_lock_waits"
    ;;
  mariadb)
    service=mariadb
    container=hazel-mariadb
    client=mariadb
    sql_dir=mariadb
    lock_wait_count="SELECT COUNT(*) FROM information_schema.INNODB_LOCK_WAITS"
    ;;
  percona)
    service=percona
    container=hazel-percona
    client=mysql
    sql_dir=mysql
    lock_wait_count="SELECT COUNT(*) FROM performance_schema.data_lock_waits"
    ;;
  *)
    echo "Unknown MySQL-family variant: $variant" >&2
    exit 2
    ;;
esac

root_mysql=(docker exec -i -e MYSQL_PWD=hazel-root-dev-only "$container" "$client" -uroot -Dhazel --batch --raw --skip-column-names --silent)
monitor_mysql=(docker exec -e MYSQL_PWD=hazel-dev-only "$container" "$client" -uhazel -Dhazel --batch --raw --skip-column-names --silent)

cleanup() {
  "${root_mysql[@]}" -e "SELECT CONCAT('KILL ', ID, ';') FROM information_schema.PROCESSLIST WHERE USER = 'root' AND ID <> CONNECTION_ID() AND COMMAND <> 'Sleep'" 2>/dev/null \
    | "${root_mysql[@]}" 2>/dev/null || true
  for job in "$blocker_job" "$waiter_job" "$reader_job"; do
    if [[ -n "$job" ]]; then
      kill "$job" >/dev/null 2>&1 || true
      wait "$job" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

docker compose -f "$repo_dir/compose.yaml" up -d --wait "$service" >/dev/null

if rg -n -i '^\s*(insert|update|delete|replace|create|alter|drop|truncate|grant|revoke|call|do|set)\b' "$repo_dir/$sql_dir/summary.sql" "$repo_dir/$sql_dir/details.sql"; then
  echo "$variant collectors must remain SELECT-only" >&2
  exit 1
fi

grants=$("${monitor_mysql[@]}" -e "SHOW GRANTS FOR CURRENT_USER()")
if grep -Eq 'ALL PRIVILEGES|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER' <<<"$grants"; then
  echo "$variant fixture monitoring account has write privileges" >&2
  exit 1
fi

summary=$(docker exec -i -e MYSQL_PWD=hazel-dev-only "$container" "$client" -uhazel -Dhazel --batch --raw --skip-column-names --silent < "$repo_dir/$sql_dir/summary.sql")

jq -e --arg engine "$variant" '
  .schema == 1 and
  .kind == "summary" and
  .engine == $engine and
  .identity.database == "hazel" and
  .identity.family == "mysql" and
  (.identity.version | type == "string") and
  (.connections.max > 0) and
  (.counters.workTotal >= 0) and
  (.counters.logBytes >= 0) and
  .counters.statsReset == null and
  .counters.logStatsReset == null and
  .maintenance.kind == "purge" and
  .maintenance.backlogLabel == "PURGE DEBT" and
  (.maintenance.backlog >= 0) and
  (.maintenance.workerCount >= 1)
' <<<"$summary" >/dev/null

if [[ "$variant" == mariadb ]]; then
  jq -e '.capabilities.innodbLockWaits == true and .capabilities.dataLocks == false' <<<"$summary" >/dev/null
else
  jq -e '.capabilities.performanceSchema == 1 and .capabilities.dataLocks == true' <<<"$summary" >/dev/null
fi

"${root_mysql[@]}" -e "SELECT * FROM accounts; UPDATE accounts SET balance = balance WHERE id = 4" >/dev/null

"${root_mysql[@]}" -e "START TRANSACTION; UPDATE accounts SET balance=1111.11 WHERE id=1; SELECT SLEEP(30); ROLLBACK" >/dev/null 2>&1 &
blocker_job=$!
for _ in {1..50}; do
  [[ "$("${root_mysql[@]}" -e "SELECT COUNT(*) FROM information_schema.INNODB_TRX")" -ge 1 ]] && break
  sleep 0.1
done

"${root_mysql[@]}" -e "START TRANSACTION; UPDATE accounts SET balance=2222.22 WHERE id=1; ROLLBACK" >/dev/null 2>&1 &
waiter_job=$!
for _ in {1..50}; do
  [[ "$("${root_mysql[@]}" -e "$lock_wait_count")" -ge 1 ]] && break
  sleep 0.1
done

locked_summary=$(docker exec -i -e MYSQL_PWD=hazel-dev-only "$container" "$client" -uhazel -Dhazel --batch --raw --skip-column-names --silent < "$repo_dir/$sql_dir/summary.sql")
details=$(docker exec -i -e MYSQL_PWD=hazel-dev-only "$container" "$client" -uhazel -Dhazel --batch --raw --skip-column-names --silent < "$repo_dir/$sql_dir/details.sql")

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

if [[ "$variant" == mariadb ]] && [[ "$(jq -r '.capabilities.performanceSchema' <<<"$summary")" == "0" ]]; then
  jq -e 'all(.relations[]; (.limited == true or .limited == 1) and .rowsRead == 0 and (.estimatedRows >= 0))' <<<"$details" >/dev/null
fi

cleanup
blocker_job=""
waiter_job=""

remaining_transactions=1
for _ in {1..50}; do
  remaining_transactions=$("${root_mysql[@]}" -e "SELECT COUNT(*) FROM information_schema.INNODB_TRX")
  [[ "$remaining_transactions" -eq 0 ]] && break
  sleep 0.1
done
if [[ "$remaining_transactions" -ne 0 ]]; then
  echo "Timed out waiting for the $variant lock fixture to fully roll back" >&2
  exit 1
fi

baseline=$("${monitor_mysql[@]}" -e "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME='trx_rseg_history_len'")
"${root_mysql[@]}" -e "START TRANSACTION WITH CONSISTENT SNAPSHOT; SELECT COUNT(*) FROM accounts; SELECT SLEEP(5) AS hazel_purge_reader; COMMIT" >/dev/null 2>&1 &
reader_job=$!
reader_ready=0
for _ in {1..50}; do
  reader_ready=$("${root_mysql[@]}" -e "
    SELECT COUNT(*)
    FROM information_schema.INNODB_TRX AS transactions
    JOIN information_schema.PROCESSLIST AS processes
      ON processes.ID = transactions.trx_mysql_thread_id
    WHERE COALESCE(processes.INFO, '') LIKE '%hazel_purge_reader%'
  ")
  [[ "$reader_ready" -ge 1 ]] && break
  sleep 0.1
done
if [[ "$reader_ready" -lt 1 ]]; then
  echo "Timed out waiting for the $variant held-snapshot fixture" >&2
  exit 1
fi
updates=""
for value in $(seq 1 100); do
  updates+="UPDATE accounts SET balance = 1000 + $value WHERE id = 1;"
done
"${root_mysql[@]}" -e "$updates" >/dev/null
during=$("${monitor_mysql[@]}" -e "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME='trx_rseg_history_len'")
if (( during <= baseline )); then
  echo "Expected $variant purge debt to grow while a consistent snapshot was held ($baseline -> $during)" >&2
  exit 1
fi

wait "$reader_job"
reader_job=""
after=$("${monitor_mysql[@]}" -e "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME='trx_rseg_history_len'")

printf 'Hazel %s snapshots passed on %s; lock edge captured; held-snapshot purge debt grew %s -> %s (post-release sample %s)\n' \
  "$variant" "$("${monitor_mysql[@]}" -e 'SELECT VERSION()')" "$baseline" "$during" "$after"
