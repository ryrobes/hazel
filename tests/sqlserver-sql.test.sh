#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
container=hazel-sqlserver
blocker_job=""
waiter_job=""
root_password='Hazel-root-dev-only!42'
monitor_password='Hazel-dev-only!42'
sqlcmd_path=/opt/mssql-tools18/bin/sqlcmd
root_sqlcmd=(docker exec -e "SQLCMDPASSWORD=$root_password" "$container" "$sqlcmd_path" -S localhost -U sa -d hazel -C -b -h -1 -W)

cleanup() {
  for job in "$waiter_job" "$blocker_job"; do
    if [[ -n "$job" ]]; then
      kill "$job" >/dev/null 2>&1 || true
      wait "$job" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

docker compose -f "$repo_dir/compose.yaml" up -d --wait sqlserver >/dev/null
docker compose -f "$repo_dir/compose.yaml" run --rm --no-deps sqlserver-init >/dev/null

if rg -n -i '^\s*(insert|update|delete|merge|create|alter|drop|truncate|grant|revoke|kill|execute|exec)\b' \
  "$repo_dir/sqlserver/summary.sql" "$repo_dir/sqlserver/details.sql"; then
  echo "SQL Server collectors must remain read-only" >&2
  exit 1
fi

permissions=$("${root_sqlcmd[@]}" -Q "SET NOCOUNT ON; EXECUTE AS LOGIN = 'hazel'; SELECT (SELECT COUNT(*) FROM sys.fn_my_permissions(NULL, 'SERVER') WHERE permission_name = 'VIEW SERVER PERFORMANCE STATE'), HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'VIEW DATABASE PERFORMANCE STATE'); REVERT;")
if [[ $(tr -s ' ' <<<"$permissions" | xargs) != "1 1" ]]; then
  echo "SQL Server fixture monitoring account is missing DMV permissions" >&2
  exit 1
fi

if docker exec -e "SQLCMDPASSWORD=$monitor_password" "$container" "$sqlcmd_path" -S localhost -U hazel -d hazel -C -b -Q "UPDATE dbo.accounts SET balance = balance WHERE id = 1" >/dev/null 2>&1; then
  echo "SQL Server fixture monitoring account can write" >&2
  exit 1
fi

collector() {
  docker exec -i -e "SQLCMDPASSWORD=$monitor_password" "$container" "$sqlcmd_path" \
    -S localhost,1433 -U hazel -d hazel -l 3 -t 5 -w 65535 -y 0 -r1 -b -x -No -C
}

summary=$(collector < "$repo_dir/sqlserver/summary.sql")
jq -e '
  .schema == 1 and
  .kind == "summary" and
  .engine == "sqlserver" and
  .identity.database == "hazel" and
  .identity.family == "sqlserver" and
  (.identity.version | type == "string") and
  (.connections.max > 0) and
  (.connections.waiting >= 0) and
  (.counters.workTotal > 0) and
  (.counters.logBytes >= 0) and
  .maintenance.kind == "log" and
  .maintenance.backlogLabel == "LOG USED" and
  .maintenance.surfaceLabel == "TABLE PRESSURE" and
  (.maintenance.logUsedPercent >= 0) and
  (.capacity.workersUsed > 0) and
  (.capacity.workersMax > .capacity.workersUsed) and
  (.capacity.logTotal > .capacity.logUsed)
' <<<"$summary" >/dev/null

persistent_responses=$(
  {
    sed '$a\' "$repo_dir/sqlserver/summary.sql"
    sed '$a\' "$repo_dir/sqlserver/details.sql"
  } | collector
)
jq -s -e 'length == 2 and .[0].kind == "summary" and .[1].kind == "details"' <<<"$persistent_responses" >/dev/null

"${root_sqlcmd[@]}" -Q "BEGIN TRANSACTION; UPDATE dbo.accounts SET balance=1111.11 WHERE id=1; WAITFOR DELAY '00:00:30'; ROLLBACK;" >/dev/null 2>&1 &
blocker_job=$!
for _ in {1..50}; do
  open_transactions=$("${root_sqlcmd[@]}" -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_tran_session_transactions AS transactions JOIN sys.dm_exec_sessions AS sessions ON sessions.session_id = transactions.session_id WHERE sessions.login_name = 'sa' AND transactions.is_user_transaction = 1;")
  [[ "${open_transactions//[[:space:]]/}" -ge 1 ]] && break
  sleep 0.1
done

"${root_sqlcmd[@]}" -Q "BEGIN TRANSACTION; UPDATE dbo.accounts SET balance=2222.22 WHERE id=1; ROLLBACK;" >/dev/null 2>&1 &
waiter_job=$!
blocked=0
for _ in {1..50}; do
  blocked=$("${root_sqlcmd[@]}" -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id > 0;")
  blocked=${blocked//[[:space:]]/}
  [[ "$blocked" -ge 1 ]] && break
  sleep 0.1
done
if [[ "$blocked" -lt 1 ]]; then
  echo "Timed out waiting for SQL Server blocking fixture" >&2
  exit 1
fi

locked_summary=$(collector < "$repo_dir/sqlserver/summary.sql")
details=$(collector < "$repo_dir/sqlserver/details.sql")

jq -e '
  .connections.blocked >= 1 and
  .connections.lockWaiting >= 1 and
  .connections.waiting >= .connections.blocked and
  .connections.oldestLockWaitSeconds >= 0
' <<<"$locked_summary" >/dev/null

jq -e '
  .schema == 1 and
  .kind == "details" and
  (.activity | length >= 2) and
  (any(.activity[]; .queryVerb == "UPDATE" and .waitType == "Lock")) and
  (all(.activity[]; (.queryText | contains("1111.11") or contains("2222.22")) | not)) and
  (.relations | any(.schema == "dbo" and .relation == "accounts" and .rowCount == 4)) and
  (.blocking | length >= 1) and
  .blocking[0].waitType == "LOCK" and
  (.blocking[0].waitEvent | startswith("LCK_")) and
  (.blocking[0].blockedSeconds | type == "number") and
  (.maintenance | length == 1)
' <<<"$details" >/dev/null

cleanup
blocker_job=""
waiter_job=""
trap - EXIT

printf 'Hazel SQL Server snapshots passed on %s; live worker, log, active-query, and holder/waiter telemetry verified\n' \
  "$(jq -r '.identity.version' <<<"$summary")"
