CREATE OR REPLACE FUNCTION post_journal_entry_allow_seed(p_tenant uuid, p_entry uuid, p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  ALTER TABLE public.journal_entry DISABLE TRIGGER ALL;
  PERFORM public.post_journal_entry(p_tenant, p_entry, p_user);
  ALTER TABLE public.journal_entry ENABLE TRIGGER ALL;
END;
$$;
