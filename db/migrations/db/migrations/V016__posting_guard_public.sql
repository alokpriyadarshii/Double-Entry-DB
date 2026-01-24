-- LedgerWorks V016: ensure posting guard uses public schema and latest logic

DROP TRIGGER IF EXISTS t_entry_block_direct_post ON public.journal_entry;
DROP FUNCTION IF EXISTS public.trg_block_direct_post();

CREATE FUNCTION public.trg_block_direct_post()
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

CREATE TRIGGER t_entry_block_direct_post
BEFORE UPDATE OF status ON public.journal_entry
FOR EACH ROW EXECUTE FUNCTION public.trg_block_direct_post();

CREATE OR REPLACE FUNCTION public.post_journal_entry(p_tenant uuid, p_entry uuid, p_user uuid)
RETURNS void AS $$
DECLARE
  prev_allow text;
  prev_entry text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.journal_entry WHERE id=p_entry AND tenant_id=p_tenant) THEN
    RAISE EXCEPTION 'Entry not found for tenant';
  END IF;

  -- Force balance validation now (also validated at commit via constraint trigger)
  PERFORM public.assert_entry_balanced(p_entry);

  prev_allow := current_setting('app.allow_posting', true);
  prev_entry := current_setting('app.posting_entry_id', true);

  PERFORM set_config('app.allow_posting', 'on', false);
  PERFORM set_config('app.posting_entry_id', p_entry::text, false);

  BEGIN
    UPDATE public.journal_entry
    SET status='POSTED', posted_at=now(), posted_by=p_user, updated_at=now()
    WHERE id=p_entry AND tenant_id=p_tenant AND status='DRAFT';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Entry not in DRAFT or not found';
    END IF;
  EXCEPTION WHEN others THEN
    PERFORM set_config('app.allow_posting', COALESCE(prev_allow, ''), false);
    PERFORM set_config('app.posting_entry_id', COALESCE(prev_entry, ''), false);
    RAISE;
  END;

  PERFORM set_config('app.allow_posting', COALESCE(prev_allow, ''), false);
  PERFORM set_config('app.posting_entry_id', COALESCE(prev_entry, ''), false);
END;
$$ LANGUAGE plpgsql;
