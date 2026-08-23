#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log_file=$(mktemp /tmp/hazel-credential-race.XXXXXX.log)
test_dir=$(mktemp -d /tmp/hazel-credential-race.XXXXXX)
cleanup() {
  rm -f -- "$log_file"
  rm -f -- "$test_dir/shell.qml" "$test_dir/Hazel" "$test_dir/Commons" "$test_dir/Ui" "$test_dir/bin/secret-tool"
  rmdir -- "$test_dir/bin" "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/bin"
ln -s "$repo_dir/tests/CredentialRaceHarness.qml" "$test_dir/shell.qml"
ln -s "$repo_dir" "$test_dir/Hazel"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$test_dir/Ui"
ln -s "$repo_dir/tests/fake-secret-tool.sh" "$test_dir/bin/secret-tool"

PATH="$test_dir/bin:$PATH" timeout 6 quickshell -p "$test_dir/shell.qml" 2>&1 | tee "$log_file"

rg -q 'HAZEL_CREDENTIAL_RACE_OK' "$log_file"
if rg -q 'HAZEL_CREDENTIAL_RACE_(FAIL|TIMEOUT)' "$log_file"; then
  exit 1
fi
