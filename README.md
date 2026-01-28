# Double Entry DB

---

set -euo pipefail

## 1) Go to project folder (adjust if you're already there)

---

cd "Double-Entry-DB"

## 2) Start Postgres in background

---

docker compose up -d db

## 3) Wait until Postgres is ready

---

until docker compose exec -T db pg_isready -U ledger -d ledgerworks >/dev/null 2>&1; do sleep 0.2; done

## 4) Run migrations

---

docker compose run --rm flyway

## 5) Load demo seed data

---

./scripts/seed.sh

## 6) Run DB smoke tests

---

./scripts/test.sh

## 7) All commands at once (one paste)

---

cd "Double-Entry-DB" 2>/dev/null || true && docker compose up -d db && until docker compose exec -T db pg_isready -U ledger -d ledgerworks >/dev/null 2>&1; do sleep 0.2; done && docker compose run --rm flyway && ./scripts/seed.sh && ./scripts/test.sh

