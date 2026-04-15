#!/usr/bin/env bash
set -euo pipefail

# Apply migrations in Flyway-like order using psql (no Flyway required).
# Connection is controlled by standard libpq env vars: PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD.

MIG_DIR="${1:-db/migrations}"

if [[ ! -d "$MIG_DIR" ]]; then
  echo "Migration directory not found: $MIG_DIR" >&2
  exit 1
fi

tmp_versions="$(mktemp)"
trap 'rm -f "$tmp_versions"' EXIT

while IFS= read -r f; do
  file="${f##*/}"

  # Match Flyway-style versioned migrations, e.g. V1__x.sql, V1_2__x.sql, V001__x.sql.
  if [[ "$file" =~ ^V([0-9][0-9_\.]*)__.+\.sql$ ]]; then
    version="${BASH_REMATCH[1]}"
    normalized_version="${version//_/.}"
    printf '%s\t%s\n' "$normalized_version" "$f" >>"$tmp_versions"
  fi
done < <(find "$MIG_DIR" -type f -name 'V*.sql' -print)

if [[ ! -s "$tmp_versions" ]]; then
  echo "No versioned migration files found under: $MIG_DIR" >&2
  exit 1
fi

sort -t $'\t' -k1,1V -k2,2 "$tmp_versions" | cut -f2- | while IFS= read -r migration; do
  echo "==> Applying $migration"
  psql -v ON_ERROR_STOP=1 -f "$migration"
done
