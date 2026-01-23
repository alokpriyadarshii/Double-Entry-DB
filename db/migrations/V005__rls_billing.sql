-- LedgerWorks V005: RLS policies for billing tables

ALTER TABLE customer ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_allocation ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_customer ON customer
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_invoice ON invoice
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_invoice_item ON invoice_item
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_payment ON payment
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_payment_allocation ON payment_allocation
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);
