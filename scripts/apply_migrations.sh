#!/usr/bin/env bash
set -euo pipefail

# Apply all migrations in order using psql (no Flyway required).
# Connection is controlled by standard libpq env vars: PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD.

MIG_DIR="${1:-db/migrations}"

for f in $(ls -1 "$MIG_DIR"/V*.sql | sort); do
  echo "==> Applying $f"
  psql -v ON_ERROR_STOP=1 -f "$f"
done
