-- Demo seed data for LedgerWorks

BEGIN;

-- Create a demo tenant and users
DO $$
DECLARE
  t uuid;
  admin_id uuid;
  acct_id uuid;
  cash uuid;
  ar uuid;
  sales uuid;
  expense uuid;
  equity uuid;
  j_general uuid;
  c uuid;
  inv uuid;
BEGIN
  INSERT INTO tenant(name) VALUES ('DemoCo Pvt Ltd') RETURNING id INTO t;

  INSERT INTO app_user(email, full_name) VALUES ('admin@demo.co', 'Demo Admin') RETURNING id INTO admin_id;
  INSERT INTO app_user(email, full_name) VALUES ('accountant@demo.co', 'Demo Accountant') RETURNING id INTO acct_id;

  INSERT INTO tenant_membership(tenant_id, user_id, role) VALUES (t, admin_id, 'ADMIN');
  INSERT INTO tenant_membership(tenant_id, user_id, role) VALUES (t, acct_id, 'ACCOUNTANT');

  -- Chart of accounts
  INSERT INTO account(tenant_id, code, name, type) VALUES (t, '1000', 'Cash', 'ASSET') RETURNING id INTO cash;
  INSERT INTO account(tenant_id, code, name, type) VALUES (t, '1100', 'Accounts Receivable', 'ASSET') RETURNING id INTO ar;
  INSERT INTO account(tenant_id, code, name, type) VALUES (t, '4000', 'Sales Revenue', 'REVENUE') RETURNING id INTO sales;
  INSERT INTO account(tenant_id, code, name, type) VALUES (t, '5000', 'Office Expense', 'EXPENSE') RETURNING id INTO expense;
  INSERT INTO account(tenant_id, code, name, type) VALUES (t, '3000', 'Owner Equity', 'EQUITY') RETURNING id INTO equity;

  -- Journals
  INSERT INTO journal(tenant_id, name) VALUES (t, 'General') RETURNING id INTO j_general;
  PERFORM ensure_journal(t, 'Sales');

  -- Sample posted journal entry: Owner invests cash
  INSERT INTO journal_entry(tenant_id, journal_id, entry_date, memo)
    VALUES (t, j_general, CURRENT_DATE, 'Owner investment')
    RETURNING id INTO inv;

  INSERT INTO journal_line(tenant_id, entry_id, line_no, account_id, description, debit, credit)
    VALUES (t, inv, 1, cash, 'Cash in', 100000, 0);

  INSERT INTO journal_line(tenant_id, entry_id, line_no, account_id, description, debit, credit)
    VALUES (t, inv, 2, equity, 'Equity', 0, 100000);

  PERFORM post_journal_entry(t, inv, admin_id);

  -- Customer + Invoice
  INSERT INTO customer(tenant_id, name, email) VALUES (t, 'Acme Client', 'billing@acme.com') RETURNING id INTO c;

  INSERT INTO invoice(tenant_id, customer_id, invoice_no, invoice_date, due_date)
    VALUES (t, c, 'INV-0001', CURRENT_DATE, CURRENT_DATE + 14)
    RETURNING id INTO inv;

  INSERT INTO invoice_item(tenant_id, invoice_id, line_no, description, qty, unit_price, income_account_id)
    VALUES (t, inv, 1, 'API Development', 10, 2500, sales);

  INSERT INTO invoice_item(tenant_id, invoice_id, line_no, description, qty, unit_price, income_account_id)
    VALUES (t, inv, 2, 'Support Retainer', 1, 15000, sales);

  -- Issue invoice (creates and posts a journal entry)
  PERFORM issue_invoice(t, inv, acct_id, ar);
END $$;

COMMIT;
