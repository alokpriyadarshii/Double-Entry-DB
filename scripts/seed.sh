#!/usr/bin/env bash
set -euo pipefail

# Loads demo data (tenant, users, chart of accounts, sample journal entry + invoice).

docker compose exec -T db psql -U ledger -d ledgerworks -f db/seeds/seed_demo_tenant.sql
