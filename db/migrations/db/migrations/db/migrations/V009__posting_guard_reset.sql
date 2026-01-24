-- LedgerWorks V009: reset post_journal_entry bypass flag after posting

CREATE OR REPLACE FUNCTION post_journal_entry(p_tenant uuid, p_entry uuid, p_user uuid)
RETURNS void AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM journal_entry WHERE id=p_entry AND tenant_id=p_tenant) THEN
    RAISE EXCEPTION 'Entry not found for tenant';
  END IF;

  -- Force balance validation now (also validated at commit via constraint trigger)
  PERFORM assert_entry_balanced(p_entry);

  PERFORM set_config('app.allow_posting', 'on', true);

  BEGIN
    UPDATE journal_entry
    SET status='POSTED', posted_at=now(), posted_by=p_user, updated_at=now()
    WHERE id=p_entry AND tenant_id=p_tenant AND status='DRAFT';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Entry not in DRAFT or not found';
    END IF;
  EXCEPTION WHEN others THEN
    PERFORM set_config('app.allow_posting', 'off', true);
    RAISE;
  END;

  PERFORM set_config('app.allow_posting', 'off', true);
END;
$$ LANGUAGE plpgsql;
