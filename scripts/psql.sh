#!/usr/bin/env bash
set -euo pipefail

# Opens an interactive psql session inside the running db container.
exec docker compose exec db psql -U ledger -d ledgerworks
