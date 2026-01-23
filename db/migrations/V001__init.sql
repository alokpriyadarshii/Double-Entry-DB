-- LedgerWorks V001: core multi-tenant double-entry ledger


-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- Helper: updated_at trigger
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Tenancy & access
CREATE TABLE tenant (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app_user (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email      citext NOT NULL UNIQUE,
  full_name  text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tenant_membership (
  tenant_id  uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role       text NOT NULL CHECK (role IN ('ADMIN','ACCOUNTANT','VIEWER')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, user_id)
);

-- Accounting
CREATE TYPE account_type AS ENUM ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE');

CREATE TABLE account (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
  code       text NOT NULL,
  name       text NOT NULL,
  type       account_type NOT NULL,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_account_tenant_code UNIQUE (tenant_id, code),
  CONSTRAINT uq_account_tenant_id UNIQUE (tenant_id, id)
);

CREATE TABLE journal (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
  name       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_journal_tenant_name UNIQUE (tenant_id, name),
  CONSTRAINT uq_journal_tenant_id UNIQUE (tenant_id, id)
);

CREATE TYPE entry_status AS ENUM ('DRAFT','POSTED','VOID');

CREATE TABLE journal_entry (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
  journal_id uuid NOT NULL,
  entry_date date NOT NULL,
  memo       text,
  status     entry_status NOT NULL DEFAULT 'DRAFT',
  posted_at  timestamptz,
  posted_by  uuid REFERENCES app_user(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_entry_tenant_id UNIQUE (tenant_id, id),
  CONSTRAINT fk_entry_journal FOREIGN KEY (tenant_id, journal_id)
    REFERENCES journal(tenant_id, id)
    ON DELETE RESTRICT,
  CONSTRAINT chk_posted_fields CHECK (
    (status = 'POSTED' AND posted_at IS NOT NULL AND posted_by IS NOT NULL) OR
    (status <> 'POSTED' AND posted_at IS NULL)
  )
);

CREATE TRIGGER t_journal_entry_updated_at
BEFORE UPDATE ON journal_entry
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE journal_line (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL,
  entry_id    uuid NOT NULL,
  line_no     int  NOT NULL,
  account_id  uuid NOT NULL,
  description text,
  debit       numeric(20,6) NOT NULL DEFAULT 0,
  credit      numeric(20,6) NOT NULL DEFAULT 0,
  currency    text NOT NULL DEFAULT 'INR',
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_line_entry_lineno UNIQUE (entry_id, line_no),
  CONSTRAINT fk_line_entry FOREIGN KEY (tenant_id, entry_id)
    REFERENCES journal_entry(tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_line_account FOREIGN KEY (tenant_id, account_id)
    REFERENCES account(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT chk_line_amounts_nonneg CHECK (debit >= 0 AND credit >= 0),
  CONSTRAINT chk_line_not_both CHECK (NOT (debit > 0 AND credit > 0)),
  CONSTRAINT chk_line_one_side CHECK (debit > 0 OR credit > 0)
);

-- Performance indexes
CREATE INDEX idx_entry_tenant_date ON journal_entry(tenant_id, entry_date DESC);
CREATE INDEX idx_line_entry ON journal_line(entry_id);
CREATE INDEX idx_line_tenant_account ON journal_line(tenant_id, account_id);

-- Balance enforcement (deferrable constraint trigger)
CREATE OR REPLACE FUNCTION assert_entry_balanced(p_entry uuid)
RETURNS void AS $$
DECLARE
  diff numeric(20,6);
BEGIN
  SELECT COALESCE(SUM(debit - credit), 0)
    INTO diff
  FROM journal_line
  WHERE entry_id = p_entry;

  IF diff <> 0 THEN
    RAISE EXCEPTION 'Journal entry % is not balanced. Diff=%', p_entry, diff;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_check_balance()
RETURNS trigger AS $$
BEGIN
  PERFORM assert_entry_balanced(COALESCE(NEW.entry_id, OLD.entry_id));
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER journal_entry_balance_check
AFTER INSERT OR UPDATE OR DELETE ON journal_line
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_check_balance();

-- Immutability & safe posting
CREATE OR REPLACE FUNCTION trg_block_updates_on_posted()
RETURNS trigger AS $$
DECLARE
  st entry_status;
BEGIN
  SELECT status INTO st FROM journal_entry WHERE id = COALESCE(NEW.entry_id, OLD.entry_id);
  IF st = 'POSTED' THEN
    RAISE EXCEPTION 'Posted entries are immutable. Create a reversal/adjustment entry instead.';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER t_line_no_update_on_posted
BEFORE UPDATE OR DELETE ON journal_line
FOR EACH ROW EXECUTE FUNCTION trg_block_updates_on_posted();

CREATE OR REPLACE FUNCTION trg_block_direct_post()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'POSTED' AND OLD.status <> 'POSTED' THEN
    RAISE EXCEPTION 'Use post_journal_entry(...) to post. Direct status changes are not allowed.';
  END IF;
  IF OLD.status = 'POSTED' AND NEW.status <> 'POSTED' THEN
    RAISE EXCEPTION 'Posted entries cannot be un-posted. Create a reversal entry.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER t_entry_block_direct_post
BEFORE UPDATE OF status ON journal_entry
FOR EACH ROW EXECUTE FUNCTION trg_block_direct_post();

-- Post function (atomic)
CREATE OR REPLACE FUNCTION post_journal_entry(p_tenant uuid, p_entry uuid, p_user uuid)
RETURNS void AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM journal_entry WHERE id=p_entry AND tenant_id=p_tenant) THEN
    RAISE EXCEPTION 'Entry not found for tenant';
  END IF;

  -- Force balance validation now (also validated at commit via constraint trigger)
  PERFORM assert_entry_balanced(p_entry);

  UPDATE journal_entry
  SET status='POSTED', posted_at=now(), posted_by=p_user, updated_at=now()
  WHERE id=p_entry AND tenant_id=p_tenant AND status='DRAFT';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entry not in DRAFT or not found';
  END IF;
END;
$$ LANGUAGE plpgsql;

