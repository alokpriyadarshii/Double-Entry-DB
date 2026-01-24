-- LedgerWorks V011: compare posting entry id as text to avoid cast errors

CREATE OR REPLACE FUNCTION trg_block_direct_post()
RETURNS trigger AS $$
DECLARE
  posting_entry text;
BEGIN
  IF current_setting('app.allow_posting', true) = 'on' THEN
    posting_entry := current_setting('app.posting_entry_id', true);
    IF posting_entry IS NOT NULL AND posting_entry = NEW.id::text THEN
      RETURN NEW;
    END IF;
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
DECLARE
  prev_allow text;
  prev_entry text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM journal_entry WHERE id=p_entry AND tenant_id=p_tenant) THEN
    RAISE EXCEPTION 'Entry not found for tenant';
  END IF;

  -- Force balance validation now (also validated at commit via constraint trigger)
  PERFORM assert_entry_balanced(p_entry);

  prev_allow := current_setting('app.allow_posting', true);
  prev_entry := current_setting('app.posting_entry_id', true);

  PERFORM set_config('app.allow_posting', 'on', true);
  PERFORM set_config('app.posting_entry_id', p_entry::text, true);

  BEGIN
    UPDATE journal_entry
    SET status='POSTED', posted_at=now(), posted_by=p_user, updated_at=now()
    WHERE id=p_entry AND tenant_id=p_tenant AND status='DRAFT';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Entry not in DRAFT or not found';
    END IF;
  EXCEPTION WHEN others THEN
    PERFORM set_config('app.allow_posting', COALESCE(prev_allow, 'off'), true);
    PERFORM set_config('app.posting_entry_id', COALESCE(prev_entry, ''), true);
    RAISE;
  END;

  PERFORM set_config('app.allow_posting', COALESCE(prev_allow, 'off'), true);
  PERFORM set_config('app.posting_entry_id', COALESCE(prev_entry, ''), true);
END;
$$ LANGUAGE plpgsql;
