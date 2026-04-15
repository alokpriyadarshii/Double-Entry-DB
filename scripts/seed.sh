#!/usr/bin/env bash
set -euo pipefail

# Loads demo data (tenant, users, chart of accounts, sample journal entry + invoice).

if command -v docker >/dev/null 2>&1; then
  docker compose exec -T db psql -U ledger -d ledgerworks -f db/seeds/seed_demo_tenant.sql
else
  : "${PGHOST:?PGHOST must be set when docker is unavailable}"
  : "${PGPORT:?PGPORT must be set when docker is unavailable}"
  : "${PGDATABASE:?PGDATABASE must be set when docker is unavailable}"
  : "${PGUSER:?PGUSER must be set when docker is unavailable}"
  psql -v ON_ERROR_STOP=1 -f db/seeds/seed_demo_tenant.sql
fi
