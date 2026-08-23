#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
container="hazel-postgres16-compat-$$"

cleanup() {
  docker stop "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --rm --name "$container" \
  -e POSTGRES_DB=postgres \
  -e POSTGRES_USER=hazel \
  -e POSTGRES_PASSWORD=hazel-dev-only \
  postgres:16 >/dev/null

ready=0
for _ in {1..60}; do
  if docker exec "$container" pg_isready -U hazel -d postgres >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done
if [[ "$ready" -ne 1 ]]; then
  echo "PostgreSQL 16 compatibility container did not become ready" >&2
  exit 1
fi

summary=$(docker exec -i "$container" psql -X -w -qAt -U hazel -d postgres < "$repo_dir/postgres/summary.sql")
details=$(docker exec -i "$container" psql -X -w -qAt -U hazel -d postgres < "$repo_dir/postgres/details.sql")

jq -e '.kind == "summary" and (.identity.version | startswith("16."))' <<<"$summary" >/dev/null
jq -e '.kind == "details" and .vacuum == []' <<<"$details" >/dev/null

printf 'Hazel PostgreSQL compatibility snapshots passed on PostgreSQL 16\n'
