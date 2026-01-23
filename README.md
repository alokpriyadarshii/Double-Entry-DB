# Double Entry DB

A **multi-tenant double-entry accounting ledger + invoicing** database built on **PostgreSQL** (Docker + Flyway).

---

```bash
set -euo pipefail
```

## 1) Go to project folder (adjust if you're already there)

---

```bash
cd "Double Entry DB"
```

## 2) Start Postgres in background

---

```bash
make up
```

## 3) Wait until Postgres is ready

---

```bash
until docker compose exec -T db pg_isready -U ledger -d ledgerworks >/dev/null 2>&1; do sleep 0.2; done
```

## 4) Run migrations

---

```bash
make migrate
```

## 5) Load demo seed data

---

```bash
make seed
```

## 6) Run database smoke tests

---

```bash
make test
```

## 7) Open a SQL shell (psql)

---

```bash
make psql
```

---

## Connection details

---

- Host: `localhost`
- Port: `5432`
- DB: `ledgerworks`
- User: `ledger`
- Pass: `ledger`

---

## Handy commands

---

```bash
make down    # stop containers
make reset   # wipe volumes + restart db (DANGER: deletes data)
```

---

## Notes

---

- Migrations are **Flyway-compatible** (versioned `V###__*.sql`).
- Balancing is enforced at **COMMIT** time using a **DEFERRABLE constraint trigger**.
- Posted journal entries are **immutable** (updates/deletes are blocked).
- Optional **Row Level Security (RLS)** policies are included for tenant isolation.