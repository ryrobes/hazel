#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log_file=$(mktemp /tmp/hazel-bounded-reader.XXXXXX.log)
test_dir=$(mktemp -d /tmp/hazel-bounded-reader.XXXXXX)
cleanup() {
  rm -f -- "$log_file"
  rm -f -- "$test_dir/shell.qml" "$test_dir/Hazel" "$test_dir/Commons" "$test_dir/Ui"
  rmdir -- "$test_dir"
}
trap cleanup EXIT

ln -s "$repo_dir/tests/BoundedLineReaderHarness.qml" "$test_dir/shell.qml"
ln -s "$repo_dir" "$test_dir/Hazel"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
timeout 5 quickshell -p "$test_dir/shell.qml" 2>&1 | tee "$log_file"

rg -q 'HAZEL_BOUNDED_READER_OK' "$log_file"
if rg -q 'HAZEL_BOUNDED_READER_(FAIL|TIMEOUT)' "$log_file"; then
  exit 1
fi
