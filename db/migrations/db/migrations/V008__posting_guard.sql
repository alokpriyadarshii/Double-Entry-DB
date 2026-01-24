-- LedgerWorks V008: allow post_journal_entry to bypass direct post guard

CREATE OR REPLACE FUNCTION trg_block_direct_post()
RETURNS trigger AS $$
BEGIN
  IF current_setting('app.allow_posting', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'POSTED' AND OLD.status <> 'POSTED' THEN
    RAISE EXCEPTION 'Use post_journal_entry(...) to post. Direct status changes are not allowed.';
  END IF;
  IF OLD.status = 'POSTED' AND NEW.status <> 'POSTED' THEN
    RAISE EXCEPTION 'Posted entries cannot be un-posted. Create a reversal entry.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION post_journal_entry(p_tenant uuid, p_entry uuid, p_user uuid)
RETURNS void AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM journal_entry WHERE id=p_entry AND tenant_id=p_tenant) THEN
    RAISE EXCEPTION 'Entry not found for tenant';
  END IF;

  -- Force balance validation now (also validated at commit via constraint trigger)
  PERFORM assert_entry_balanced(p_entry);

  PERFORM set_config('app.allow_posting', 'on', true);

  UPDATE journal_entry
  SET status='POSTED', posted_at=now(), posted_by=p_user, updated_at=now()
  WHERE id=p_entry AND tenant_id=p_tenant AND status='DRAFT';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entry not in DRAFT or not found';
  END IF;
END;
$$ LANGUAGE plpgsql;
