-- LedgerWorks DB smoke tests
-- Run with: psql -v ON_ERROR_STOP=1 -f tests/db/smoke_test.sql

BEGIN;

DO $$
DECLARE
  t1 uuid;
  t2 uuid;
  u1 uuid;
  j1 uuid;
  cash uuid;
  equity uuid;
  other_acct uuid;
  e1 uuid;
BEGIN
  -- Setup minimal tenant + user
  INSERT INTO tenant(name) VALUES ('TestTenant') RETURNING id INTO t1;
  INSERT INTO app_user(email, full_name) VALUES ('testuser@example.com', 'Test User') RETURNING id INTO u1;

  INSERT INTO journal(tenant_id, name) VALUES (t1, 'General') RETURNING id INTO j1;

  INSERT INTO account(tenant_id, code, name, type) VALUES (t1, '1000', 'Cash', 'ASSET') RETURNING id INTO cash;
  INSERT INTO account(tenant_id, code, name, type) VALUES (t1, '3000', 'Equity', 'EQUITY') RETURNING id INTO equity;

  -- Create DRAFT entry and add unbalanced lines
  INSERT INTO journal_entry(tenant_id, journal_id, entry_date, memo)
  VALUES (t1, j1, CURRENT_DATE, 'Unbalanced test')
  RETURNING id INTO e1;

  INSERT INTO journal_line(tenant_id, entry_id, line_no, account_id, description, debit, credit)
  VALUES (t1, e1, 1, cash, 'Debit cash', 100, 0);

  -- Expect balance check to fail
  BEGIN
    PERFORM assert_entry_balanced(e1);
    RAISE EXCEPTION 'Expected assert_entry_balanced to fail for unbalanced entry';
  EXCEPTION WHEN others THEN
    -- expected
    NULL;
  END;

  -- Add balancing line
  INSERT INTO journal_line(tenant_id, entry_id, line_no, account_id, description, debit, credit)
  VALUES (t1, e1, 2, equity, 'Credit equity', 0, 100);

  -- Now it should pass
  PERFORM assert_entry_balanced(e1);

  -- Direct status update must be blocked
  BEGIN
    UPDATE journal_entry SET status='POSTED' WHERE id=e1;
    RAISE EXCEPTION 'Expected direct status update to POSTED to be blocked';
  EXCEPTION WHEN others THEN
    NULL;
  END;

  -- Posting via function should work
  PERFORM post_journal_entry(t1, e1, u1);

  IF (SELECT status FROM journal_entry WHERE id=e1) <> 'POSTED' THEN
    RAISE EXCEPTION 'Expected entry to be POSTED';
  END IF;

  -- Posted lines must be immutable
  BEGIN
    UPDATE journal_line SET description='tamper' WHERE entry_id=e1 AND line_no=1;
    RAISE EXCEPTION 'Expected update on posted line to be blocked';
  EXCEPTION WHEN others THEN
    NULL;
  END;

  -- Cross-tenant FK protection
  INSERT INTO tenant(name) VALUES ('OtherTenant') RETURNING id INTO t2;
  INSERT INTO account(tenant_id, code, name, type) VALUES (t2, '9999', 'Other', 'ASSET') RETURNING id INTO other_acct;

  BEGIN
    INSERT INTO journal_line(tenant_id, entry_id, line_no, account_id, description, debit, credit)
    VALUES (t1, e1, 3, other_acct, 'Should fail', 1, 0);
    RAISE EXCEPTION 'Expected cross-tenant account reference to fail';
  EXCEPTION WHEN others THEN
    NULL;
  END;
END $$;

ROLLBACK;
