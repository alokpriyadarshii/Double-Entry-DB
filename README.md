# Double-Entry-DB

A PostgreSQL first, multi tenant double entry accounting schema with Docker based local setup, SQL migrations, demo seed data, reporting views, and smoke tests.

Inside the SQL migrations and test files, the project is referred to as **LedgerWorks**. The repository name is **Double-Entry-DB**, but both refer to the same database project.

## What this project includes

- Multi-tenant ledger schema with strict tenant-scoped foreign keys
- Core accounting entities: tenants, users, memberships, accounts, journals, journal entries, and journal lines
- Balanced journal enforcement with a **deferrable constraint trigger**
- Safe posting workflow through `post_journal_entry(...)`
- Immutability rules for posted entries
- Billing layer with customers, invoices, invoice items, payments, and payment allocations
- Invoice issuing workflow through `issue_invoice(...)`
- Optional Row Level Security policies for tenant isolation
- Reporting objects for trial balance, open invoices, and daily balances
- Demo seed data for a sample tenant and sample transactions
- SQL smoke tests and GitHub Actions CI

## Tech stack

- PostgreSQL 16
- Flyway 10
- Docker Compose
- Bash helper scripts
- Plain SQL / PL/pgSQL

## Project structure

```text
.
├── db/
│   ├── migrations/          # main schema and feature migrations
│   └── seeds/               # demo seed data
├── docs/
│   ├── decisions.md         # design choices
│   ├── erd.md               # Mermaid ERD
│   └── performance.md       # indexing and reporting notes
├── scripts/
│   ├── apply_migrations.sh  # psql-based migration runner
│   ├── psql.sh              # opens psql inside the db container
│   ├── seed.sh              # loads demo data
│   └── test.sh              # runs smoke tests
├── tests/
│   └── db/smoke_test.sql    # database behavior checks
├── docker-compose.yml
└── Makefile
```

## Main schema areas

### Core ledger

The base schema creates:

- `tenant`
- `app_user`
- `tenant_membership`
- `account`
- `journal`
- `journal_entry`
- `journal_line`

Important rules built into the database:

- Account and journal relationships are tenant-scoped
- Journal lines must have exactly one side populated: debit or credit
- Debits and credits must be non-negative
- Journal entries are validated for balance at commit time
- Posted entries cannot be edited or un-posted directly

### Billing

The billing migrations add:

- `customer`
- `invoice`
- `invoice_item`
- `payment`
- `payment_allocation`

`issue_invoice(...)` creates and posts the corresponding accounting entry automatically by:

- debiting Accounts Receivable
- crediting one or more income accounts from invoice items

### Reporting

The reporting migrations create:

- `v_trial_balance`
- `v_open_invoices`
- `mv_daily_account_balance`

These are intended for ledger summaries, AR tracking, and dashboard-style reporting.

## Quick start

### Option 1: Docker Compose workflow

Requirements:

- Docker
- Docker Compose

Start the database:

```bash
make up
```

Apply migrations through Flyway:

```bash
make migrate
```

Load demo seed data:

```bash
make seed
```

Run smoke tests:

```bash
make test
```

Open a psql shell:

```bash
make psql
```

Stop containers:

```bash
make down
```

Reset local data volume and restart Postgres:

```bash
make reset
```

### Option 2: One-liner setup

```bash
cd Double-Entry-DB 2>/dev/null || true && docker compose up -d db && until docker compose exec -T db pg_isready -U ledger -d ledgerworks >/dev/null 2>&1; do sleep 0.2; done && docker compose run --rm flyway && ./scripts/seed.sh && ./scripts/test.sh
```

## Local database configuration

The Docker setup uses:

- database: `ledgerworks`
- user: `ledger`
- password: `ledger`
- port: `5432`

## Running with local PostgreSQL instead of Docker

The repository also includes `scripts/apply_migrations.sh`, which applies migrations with `psql` using standard libpq environment variables:

- `PGHOST`
- `PGPORT`
- `PGDATABASE`
- `PGUSER`
- `PGPASSWORD`

Example:

```bash
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=ledgerworks
export PGUSER=ledger
export PGPASSWORD=ledger
./scripts/apply_migrations.sh
```

## Demo data

The seed script loads a small working example into the database:

- a demo tenant
- two users
- a basic chart of accounts
- a general journal
- a posted owner-investment entry
- one customer
- one invoice with invoice items
- automatic invoice issuance into the ledger

Run it with:

```bash
./scripts/seed.sh
```

## Testing

Smoke tests are located in `tests/db/smoke_test.sql`.

They verify behavior such as:

- unbalanced entries are rejected
- balanced entries can be posted through the posting function
- direct status changes to `POSTED` are blocked
- posted lines are immutable
- cross-tenant account references are rejected

Run tests with:

```bash
./scripts/test.sh
```

Or through Make:

```bash
make test
```

## Useful queries

Once seeded, these are useful places to start exploring:

```sql
SELECT * FROM v_trial_balance;
SELECT * FROM v_open_invoices;
SELECT * FROM mv_daily_account_balance;
```

To inspect base data:

```sql
SELECT * FROM tenant;
SELECT * FROM account ORDER BY code;
SELECT * FROM journal_entry ORDER BY created_at DESC;
SELECT * FROM journal_line ORDER BY entry_id, line_no;
```

## Row Level Security

RLS is enabled on ledger and billing tables to demonstrate tenant-scoped access.

The intended application pattern is to set a tenant context before queries:

```sql
SET app.tenant_id = '<tenant-uuid>';
```

The migrations enable RLS but do **not** force it, which keeps local setup, seeding, and migrations simpler.

## Documentation

Additional design notes are available in:

- `docs/decisions.md`
- `docs/erd.md`
- `docs/performance.md`

## CI

GitHub Actions runs a database CI workflow that:

- starts PostgreSQL
- applies migrations with `psql`
- runs the smoke test script

Workflow file:

- `.github/workflows/ci.yml`

## Notes and current limitations

- This repository is database-first; it does not include an application API or UI
- Billing support is focused on invoice issuance and simple payment allocation structures
- Payment records exist, but there is no built-in `record_payment(...)` posting workflow yet
- Currency is stored as text on rows; there is no FX conversion logic
- The materialized view is created, but automated refresh scheduling is not included
- The main local workflow uses the top-level migrations in `db/migrations`
- The repository also contains nested follow-up migration files under `db/migrations/db/migrations`, which appear to be later posting-guard iterations and are not used by the helper script `scripts/apply_migrations.sh`

