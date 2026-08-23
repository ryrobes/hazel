#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
container="hazel-postgres11-compat-$$"

cleanup() {
  docker stop "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --rm --name "$container" \
  -e POSTGRES_DB=postgres \
  -e POSTGRES_USER=hazel \
  -e POSTGRES_PASSWORD=hazel-dev-only \
  postgres:11 >/dev/null

ready=0
for _ in {1..120}; do
  if [[ "$(docker logs "$container" 2>&1)" == *"PostgreSQL init process complete"* ]] &&
    docker exec "$container" pg_isready -U hazel -d postgres >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.5
done
if [[ "$ready" -ne 1 ]]; then
  echo "PostgreSQL 11 compatibility container did not become ready" >&2
  exit 1
fi

summary=$(docker exec -i "$container" psql -X -w -qAt -U hazel -d postgres < "$repo_dir/postgres/summary.sql")
details=$(docker exec -i "$container" psql -X -w -qAt -U hazel -d postgres < "$repo_dir/postgres/details.sql")

jq -e '
  .kind == "summary" and
  (.identity.version | startswith("11.")) and
  (.counters.walBytes | type == "number") and
  .counters.walRecords == null and
  .mvcc.vacuumWorkers == 0
' <<<"$summary" >/dev/null
jq -e '.kind == "details" and .vacuum == []' <<<"$details" >/dev/null

printf 'Hazel PostgreSQL compatibility snapshots passed on PostgreSQL 11\n'
