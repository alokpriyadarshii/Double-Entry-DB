CREATE OR REPLACE FUNCTION public.issue_invoice_allow_seed(p_tenant uuid, p_invoice uuid, p_user uuid, p_ar_account uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  ALTER TABLE public.journal_entry DISABLE TRIGGER ALL;
  PERFORM public.issue_invoice(p_tenant, p_invoice, p_user, p_ar_account);
  ALTER TABLE public.journal_entry ENABLE TRIGGER ALL;
END;
$$;
