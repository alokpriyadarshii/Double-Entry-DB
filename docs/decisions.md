# Design Decisions

This project is intentionally **database-first**. The goal is to demonstrate production-grade relational patterns.

## 1) Tenant isolation via composite foreign keys
Every entity includes `tenant_id`. Cross-tenant relationships are prevented with **composite FKs** such as:
`journal_line(tenant_id, entry_id) -> journal_entry(tenant_id, id)`.

This makes accidental cross-tenant joins impossible at the schema layer.

## 2) Balanced journal entries at COMMIT
Balancing is enforced using a **DEFERRABLE constraint trigger** on `journal_line`.
- Inserts/updates can happen line-by-line
- The entry is validated only when the transaction commits

This mirrors real systems where the application builds a draft entry in multiple statements.

## 3) Posting workflow and immutability
Accounting data should be append-only.
- Entries start as `DRAFT`
- Posting is performed via `post_journal_entry(...)`
- Once `POSTED`, updates/deletes on header and lines are blocked

## 4) Row Level Security (optional)
RLS policies are included to demonstrate tenant-safe query enforcement.
In many production environments, RLS is combined with service-layer authorization.

## 5) Money and precision
Amounts are stored in `NUMERIC(20,6)` to support large values and fractional units.
For strict currency rounding, some systems store minor-units as integers; both approaches are valid.
