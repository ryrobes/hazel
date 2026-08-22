#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log_file=$(mktemp /tmp/hazel-clickhouse-qml.XXXXXX.log)
test_dir=$(mktemp -d /tmp/hazel-clickhouse-qml.XXXXXX)
cleanup() {
  rm -f -- "$log_file"
  rm -f -- "$test_dir/shell.qml" "$test_dir/Hazel" "$test_dir/Commons" "$test_dir/Ui"
  rmdir -- "$test_dir"
}
trap cleanup EXIT

docker compose -f "$repo_dir/compose.yaml" up -d --wait clickhouse >/dev/null
ln -s "$repo_dir/tests/ClickHouseControllerHarness.qml" "$test_dir/shell.qml"
ln -s "$repo_dir" "$test_dir/Hazel"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
timeout 15 quickshell -p "$test_dir/shell.qml" 2>&1 | tee "$log_file"

if ! rg -q 'HAZEL_CLICKHOUSE_QML_OK .* PART SURFACE ' "$log_file"; then
  echo "ClickHouse did not complete a real HazelController QML snapshot" >&2
  exit 1
fi

if rg -q 'HAZEL_CLICKHOUSE_QML_(ERROR|TIMEOUT)' "$log_file"; then
  echo "ClickHouse HazelController emitted an error or timed out" >&2
  exit 1
fi
