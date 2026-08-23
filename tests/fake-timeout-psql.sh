#!/usr/bin/env bash
set -euo pipefail

IFS= read -r _line || exit 0
exec sleep 30
