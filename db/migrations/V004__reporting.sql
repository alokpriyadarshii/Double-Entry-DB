-- LedgerWorks V004: Reporting


-- Trial balance (posted entries only)
CREATE OR REPLACE VIEW v_trial_balance AS
SELECT
  je.tenant_id,
  jl.account_id,
  SUM(jl.debit)  AS total_debit,
  SUM(jl.credit) AS total_credit,
  SUM(jl.debit - jl.credit) AS net
FROM journal_entry je
JOIN journal_line jl ON jl.entry_id = je.id
WHERE je.status = 'POSTED'
GROUP BY je.tenant_id, jl.account_id;

-- Open Accounts Receivable (simple)
CREATE OR REPLACE VIEW v_open_invoices AS
SELECT
  i.tenant_id,
  i.id AS invoice_id,
  i.invoice_no,
  i.invoice_date,
  i.due_date,
  i.status,
  i.total_amount,
  COALESCE(SUM(pa.amount), 0) AS allocated_amount,
  (i.total_amount - COALESCE(SUM(pa.amount), 0)) AS balance_due
FROM invoice i
LEFT JOIN payment_allocation pa
  ON pa.invoice_id = i.id AND pa.tenant_id = i.tenant_id
WHERE i.status IN ('ISSUED','PAID')
GROUP BY i.tenant_id, i.id;

-- Daily net change per account (posted)
CREATE MATERIALIZED VIEW mv_daily_account_balance AS
SELECT
  je.tenant_id,
  jl.account_id,
  je.entry_date,
  SUM(jl.debit - jl.credit) AS net_change
FROM journal_entry je
JOIN journal_line jl ON jl.entry_id = je.id
WHERE je.status='POSTED'
GROUP BY je.tenant_id, jl.account_id, je.entry_date;

CREATE INDEX IF NOT EXISTS mv_daily_idx
  ON mv_daily_account_balance(tenant_id, account_id, entry_date);

