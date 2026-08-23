#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log_file=$(mktemp /tmp/hazel-timeout-state.XXXXXX.log)
test_dir=$(mktemp -d /tmp/hazel-timeout-state.XXXXXX)
cleanup() {
  rm -f -- "$log_file"
  rm -f -- "$test_dir/shell.qml" "$test_dir/Hazel" "$test_dir/Commons" "$test_dir/Ui" "$test_dir/bin/psql"
  rmdir -- "$test_dir/bin" "$test_dir"
}
trap cleanup EXIT

mkdir "$test_dir/bin"
ln -s "$repo_dir/tests/TimeoutStateHarness.qml" "$test_dir/shell.qml"
ln -s "$repo_dir" "$test_dir/Hazel"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
ln -s "$repo_dir/tests/fake-timeout-psql.sh" "$test_dir/bin/psql"

PATH="$test_dir/bin:$PATH" timeout 14 quickshell -p "$test_dir/shell.qml" 2>&1 | tee "$log_file"
rg -q 'HAZEL_TIMEOUT_STATE_OK Snapshot delayed' "$log_file"
if rg -q 'HAZEL_TIMEOUT_STATE_FAIL' "$log_file"; then
  exit 1
fi
