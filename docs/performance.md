# Performance Notes

## Indexing strategy
Common access patterns are tenant-scoped:
- Fetch entries by `tenant_id` and date range
- Fetch lines by `entry_id`
- Aggregate by `tenant_id, account_id`

Key indexes included:
- `journal_entry(tenant_id, entry_date DESC)`
- `journal_line(entry_id)`
- `journal_line(tenant_id, account_id)`

## Materialized views
The materialized view `mv_daily_account_balance` supports fast dashboards by pre-aggregating net changes per day.

## Partitioning (optional extension)
If data grows large:
- Partition `journal_line` by month on `created_at` or by `entry_date` via the parent `journal_entry`
- Keep tenant_id as a leading key in indexes to preserve locality

## Query planning
When optimizing, use:
```sql
EXPLAIN (ANALYZE, BUFFERS) <query>;
```
Track regressions in CI by asserting maximum query time for representative workloads.
