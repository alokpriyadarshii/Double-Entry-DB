-- LedgerWorks V002: Row Level Security (optional hardening)
-- Note: RLS is ENABLED but not FORCED to keep migrations/seeding easy.
-- In production, consider FORCE ROW LEVEL SECURITY and dedicated roles.


ALTER TABLE account ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_line ENABLE ROW LEVEL SECURITY;

-- Tenant context set by the app per request:
--   SET app.tenant_id = '<tenant-uuid>';

CREATE POLICY tenant_isolation_account ON account
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_journal ON journal
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_entry ON journal_entry
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_line ON journal_line
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid);

