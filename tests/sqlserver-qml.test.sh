#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log_file=$(mktemp /tmp/hazel-sqlserver-qml.XXXXXX.log)
test_dir=$(mktemp -d /tmp/hazel-sqlserver-qml.XXXXXX)
cleanup() {
  rm -f -- "$log_file"
  rm -f -- "$test_dir/shell.qml" "$test_dir/Hazel" "$test_dir/Commons" "$test_dir/Ui" "$test_dir/bin/sqlcmd"
  rmdir -- "$test_dir/bin" "$test_dir"
}
trap cleanup EXIT

docker compose -f "$repo_dir/compose.yaml" up -d --wait sqlserver >/dev/null
docker compose -f "$repo_dir/compose.yaml" run --rm --no-deps sqlserver-init >/dev/null
mkdir -p "$test_dir/bin"
ln -s "$repo_dir/tests/SqlServerControllerHarness.qml" "$test_dir/shell.qml"
ln -s "$repo_dir" "$test_dir/Hazel"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
ln -s "$repo_dir/tests/fake-sqlcmd.sh" "$test_dir/bin/sqlcmd"
PATH="$test_dir/bin:$PATH" timeout 15 quickshell -p "$test_dir/shell.qml" 2>&1 | tee "$log_file"

if ! rg -q 'HAZEL_SQLSERVER_QML_OK .* TABLE PRESSURE ' "$log_file"; then
  echo "SQL Server did not complete a real HazelController QML snapshot" >&2
  exit 1
fi

if rg -q 'HAZEL_SQLSERVER_QML_(ERROR|TIMEOUT)' "$log_file"; then
  echo "SQL Server HazelController emitted an error or timed out" >&2
  exit 1
fi
