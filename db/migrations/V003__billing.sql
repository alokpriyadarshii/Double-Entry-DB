-- LedgerWorks V003: Billing (customers, invoices, payments)


CREATE TYPE invoice_status AS ENUM ('DRAFT','ISSUED','PAID','VOID');

CREATE TABLE customer (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
  name       text NOT NULL,
  email      citext,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_customer_tenant_id UNIQUE (tenant_id, id)
);

CREATE TABLE invoice (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
  customer_id     uuid NOT NULL,
  invoice_no      text NOT NULL,
  invoice_date    date NOT NULL,
  due_date        date,
  status          invoice_status NOT NULL DEFAULT 'DRAFT',
  currency        text NOT NULL DEFAULT 'INR',
  total_amount    numeric(20,6) NOT NULL DEFAULT 0,
  ledger_entry_id uuid,
  issued_at       timestamptz,
  issued_by       uuid REFERENCES app_user(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_invoice_tenant_no UNIQUE (tenant_id, invoice_no),
  CONSTRAINT uq_invoice_tenant_id UNIQUE (tenant_id, id),
  CONSTRAINT fk_invoice_customer FOREIGN KEY (tenant_id, customer_id)
    REFERENCES customer(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_ledger_entry FOREIGN KEY (tenant_id, ledger_entry_id)
    REFERENCES journal_entry(tenant_id, id) ON DELETE SET NULL
);

CREATE TRIGGER t_invoice_updated_at
BEFORE UPDATE ON invoice
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE invoice_item (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL,
  invoice_id  uuid NOT NULL,
  line_no     int  NOT NULL,
  description text NOT NULL,
  qty         numeric(20,6) NOT NULL DEFAULT 1,
  unit_price  numeric(20,6) NOT NULL,
  income_account_id uuid NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_invoice_item_lineno UNIQUE (invoice_id, line_no),
  CONSTRAINT fk_item_invoice FOREIGN KEY (tenant_id, invoice_id)
    REFERENCES invoice(tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_item_income_acct FOREIGN KEY (tenant_id, income_account_id)
    REFERENCES account(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT chk_item_qty CHECK (qty > 0),
  CONSTRAINT chk_item_price CHECK (unit_price >= 0)
);

-- Recalculate invoice totals (sum of items)
CREATE OR REPLACE FUNCTION recalc_invoice_total(p_invoice uuid)
RETURNS void AS $$
DECLARE
  t numeric(20,6);
BEGIN
  SELECT COALESCE(SUM(qty * unit_price), 0)
    INTO t
  FROM invoice_item
  WHERE invoice_id = p_invoice;

  UPDATE invoice SET total_amount = t, updated_at = now()
  WHERE id = p_invoice;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_recalc_invoice_total()
RETURNS trigger AS $$
BEGIN
  PERFORM recalc_invoice_total(COALESCE(NEW.invoice_id, OLD.invoice_id));
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER invoice_total_recalc
AFTER INSERT OR UPDATE OR DELETE ON invoice_item
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_recalc_invoice_total();

-- Block edits once invoice is ISSUED/PAID/VOID
CREATE OR REPLACE FUNCTION trg_block_changes_if_final()
RETURNS trigger AS $$
DECLARE
  st invoice_status;
BEGIN
  SELECT status INTO st FROM invoice WHERE id = COALESCE(NEW.invoice_id, OLD.invoice_id);
  IF st <> 'DRAFT' THEN
    RAISE EXCEPTION 'Invoice is %, cannot modify items. Create a new invoice or issue a credit note.', st;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER t_invoice_item_block_on_final
BEFORE UPDATE OR DELETE ON invoice_item
FOR EACH ROW EXECUTE FUNCTION trg_block_changes_if_final();

-- Ensure a journal exists (creates if missing) and returns its id
CREATE OR REPLACE FUNCTION ensure_journal(p_tenant uuid, p_name text)
RETURNS uuid AS $$
DECLARE
  j uuid;
BEGIN
  SELECT id INTO j FROM journal WHERE tenant_id = p_tenant AND name = p_name;
  IF j IS NULL THEN
    INSERT INTO journal(tenant_id, name) VALUES (p_tenant, p_name) RETURNING id INTO j;
  END IF;
  RETURN j;
END;
$$ LANGUAGE plpgsql;

-- Issue invoice: creates a balanced posted journal entry
-- Debit: Accounts Receivable (p_ar_account)
-- Credit: income accounts from invoice items (grouped)
CREATE OR REPLACE FUNCTION issue_invoice(
  p_tenant uuid,
  p_invoice uuid,
  p_user uuid,
  p_ar_account uuid
)
RETURNS void AS $$
DECLARE
  inv invoice%ROWTYPE;
  sales_journal uuid;
  entry_id uuid;
  ln int := 1;
  rec record;
BEGIN
  SELECT * INTO inv FROM invoice WHERE id = p_invoice AND tenant_id = p_tenant FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice not found for tenant';
  END IF;
  IF inv.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Invoice must be DRAFT to issue. Current status=%', inv.status;
  END IF;

  -- Ensure latest totals
  PERFORM recalc_invoice_total(inv.id);
  SELECT * INTO inv FROM invoice WHERE id = inv.id;
  IF inv.total_amount <= 0 THEN
    RAISE EXCEPTION 'Invoice total must be > 0 to issue';
  END IF;

  sales_journal := ensure_journal(p_tenant, 'Sales');

  INSERT INTO journal_entry(tenant_id, journal_id, entry_date, memo)
  VALUES (p_tenant, sales_journal, inv.invoice_date, 'Invoice ' || inv.invoice_no)
  RETURNING id INTO entry_id;

  -- Debit AR for total
  INSERT INTO journal_line(tenant_id, entry_id, line_no, account_id, description, debit, credit, currency)
  VALUES (p_tenant, entry_id, ln, p_ar_account, 'Accounts Receivable', inv.total_amount, 0, inv.currency);
  ln := ln + 1;

  -- Credit income accounts grouped by account
  FOR rec IN
    SELECT income_account_id AS account_id, SUM(qty * unit_price) AS amt
    FROM invoice_item
    WHERE invoice_id = inv.id
    GROUP BY income_account_id
    ORDER BY income_account_id
  LOOP
    INSERT INTO journal_line(tenant_id, entry_id, line_no, account_id, description, debit, credit, currency)
    VALUES (p_tenant, entry_id, ln, rec.account_id, 'Income', 0, rec.amt, inv.currency);
    ln := ln + 1;
  END LOOP;

  -- Post (also validates balance)
  PERFORM post_journal_entry(p_tenant, entry_id, p_user);

  UPDATE invoice
  SET status='ISSUED', issued_at=now(), issued_by=p_user, ledger_entry_id=entry_id
  WHERE id = inv.id;
END;
$$ LANGUAGE plpgsql;

-- Payments (minimal): a payment record and optional allocation table
CREATE TABLE payment (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL,
  payment_date date NOT NULL,
  amount     numeric(20,6) NOT NULL,
  currency   text NOT NULL DEFAULT 'INR',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_payment_tenant_id UNIQUE (tenant_id, id),
  CONSTRAINT fk_payment_customer FOREIGN KEY (tenant_id, customer_id)
    REFERENCES customer(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT chk_payment_amount CHECK (amount > 0)
);

CREATE TABLE payment_allocation (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL,
  payment_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  amount     numeric(20,6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fk_alloc_payment FOREIGN KEY (tenant_id, payment_id)
    REFERENCES payment(tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_alloc_invoice FOREIGN KEY (tenant_id, invoice_id)
    REFERENCES invoice(tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT chk_alloc_amount CHECK (amount > 0)
);

