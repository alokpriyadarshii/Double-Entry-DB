#!/usr/bin/env bash
set -euo pipefail

# Opens an interactive psql session inside the running db container.

if command -v docker >/dev/null 2>&1; then
  exec docker compose exec db psql -U ledger -d ledgerworks
else
  : "${PGHOST:?PGHOST must be set when docker is unavailable}"
  : "${PGPORT:?PGPORT must be set when docker is unavailable}"
  : "${PGDATABASE:?PGDATABASE must be set when docker is unavailable}"
  : "${PGUSER:?PGUSER must be set when docker is unavailable}"
  exec psql
fi
