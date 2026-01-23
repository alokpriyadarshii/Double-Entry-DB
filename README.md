# Double-Entry-DB
Double Entry DB is a DB first PostgreSQL setup for multi tenant double entry bookkeeping and invoicing. It automatically keeps debits and credits in balance at commit time (via a deferrable trigger), supports draft→posted entries you can lock down, optional RLS, plus reports/materialized views, migrations, seeds, tests, and CI/CD. Built for audits.
