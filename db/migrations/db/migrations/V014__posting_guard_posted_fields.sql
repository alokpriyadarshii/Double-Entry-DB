-- LedgerWorks V014: allow posting when posted_at/by are set

CREATE OR REPLACE FUNCTION trg_block_direct_post()
RETURNS trigger AS $$
DECLARE
  posting_entry text;
BEGIN
  IF current_setting('app.allow_posting', true) = 'on' THEN
    posting_entry := NULLIF(current_setting('app.posting_entry_id', true), '');
    IF posting_entry IS NULL OR posting_entry = NEW.id::text THEN
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.status = 'POSTED' AND OLD.status <> 'POSTED' THEN
    IF NEW.posted_at IS NULL OR NEW.posted_by IS NULL THEN
      RAISE EXCEPTION 'Use post_journal_entry(...) to post. Direct status changes are not allowed.';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'POSTED' AND NEW.status <> 'POSTED' THEN
    RAISE EXCEPTION 'Posted entries cannot be un-posted. Create a reversal entry.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
