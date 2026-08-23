#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  lookup)
    sleep 1
    printf 'stale-keyring-password\n'
    ;;
  store)
    read -r _secret || true
    ;;
  clear)
    ;;
  *)
    exit 2
    ;;
esac
