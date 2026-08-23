#!/usr/bin/env bash
set -euo pipefail

export SQLCMDPASSWORD="${SQLCMDPASSWORD:-Hazel-dev-only!42}"
arguments=()
while (($# > 0)); do
  if [[ "$1" == "-S" && $# -ge 2 ]]; then
    arguments+=("-S" "localhost,1433")
    shift 2
  else
    arguments+=("$1")
    shift
  fi
done

exec docker exec -i -e SQLCMDPASSWORD hazel-sqlserver \
  /opt/mssql-tools18/bin/sqlcmd "${arguments[@]}"
