#!/usr/bin/env bash
set -euo pipefail

# Runs SQL smoke tests.

docker compose exec -T db psql -U ledger -d ledgerworks -v ON_ERROR_STOP=1 -f tests/db/smoke_test.sql
