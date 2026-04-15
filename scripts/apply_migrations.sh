#!/usr/bin/env bash
set -euo pipefail

# Apply migrations in version order using psql (no Flyway required).
# Connection is controlled by standard libpq env vars: PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD.

MIG_DIR="${1:-db/migrations}"

if [[ ! -d "$MIG_DIR" ]]; then
  echo "Migration directory not found: $MIG_DIR" >&2
  exit 1
fi

mapfile -t migration_files < <(find "$MIG_DIR" -type f -name 'V*.sql' -print | sort -t'/' -k1,1)

if [[ ${#migration_files[@]} -eq 0 ]]; then
  echo "No migration files found under: $MIG_DIR" >&2
  exit 1
fi

mapfile -t sorted_migrations < <(
  printf '%s\n' "${migration_files[@]}" \
    | awk -F/ '
      {
        file = $NF
        if (match(file, /^V([0-9]+)__/ , m)) {
          printf("%010d\t%s\n", m[1], $0)
        }
      }
    ' \
    | sort -k1,1n -k2,2 \
    | cut -f2-
)

for f in "${sorted_migrations[@]}"; do
find "$MIG_DIR" -maxdepth 1 -type f -name 'V*.sql' | sort | while read -r f; do
  echo "==> Applying $f"
  psql -v ON_ERROR_STOP=1 -f "$f"
done
