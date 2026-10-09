# Checks: inserts and parts

Each check names the columns it reads, the rule, and the public source of the rule. Apply a check only when its columns are in the results you ran, and report it only when the numbers show it. The URLs have been checked; cite them as they are.

## Were inserts slowed or rejected on purpose?

- **Columns**: `avg_delayed_insert_ms`, `rejected_inserts` (`queries/loadtest/30_window_query_breakdown.sql`), `avg_delayed_insert_ms` (`queries/advisor/12_insert_shape.sql`), `TOO_MANY_PARTS` in `queries/progress/26_errors_by_code.sql` (a rejected insert fails with this code), `max_parts_in_partition` (`queries/loadtest/31_window_cpu_10s.sql`, `queries/advisor/10_table_layout.sql`).
- **Rule**: a delay or rejection above 0 means the server slowed or refused inserts because a partition had too many active parts. Compare the part counts with the service's own `parts_to_delay_insert` and `parts_to_throw_insert`, read with `SELECT name, value FROM system.merge_tree_settings WHERE name IN ('parts_to_delay_insert', 'parts_to_throw_insert')`; do not quote a default value.
- **Source**: https://clickhouse.com/docs/reference/system-tables/events , https://clickhouse.com/docs/reference/settings/merge-tree-settings/parts-to

## Are async inserts sent without waiting?

- **Columns**: `async_inserts`, `async_inserts_without_wait` (`12`), `async_inserts_without_wait_24h` (`queries/progress/25_insert_shape_change.sql`).
- **Rule**: with `wait_for_async_insert = 0` the client is not told when a flush fails. The `Settings` map in `query_log` holds only changed settings, so a missing key means the default.
- **Source**: https://clickhouse.com/docs/concepts/features/operations/insert/asyncinserts#choosing-a-return-mode

## Do attached materialized views add to insert time?

- **Columns**: `max_attached_views` (`12`).
- **Rule**: every insert also runs the attached materialized views. `system.query_views_log` shows the time per view when `log_query_views` is enabled; an empty log means it is probably not enabled, so do not infer anything else from it.
- **Source**: https://clickhouse.com/docs/reference/system-tables/query_views_log

## Why are there too many parts?

- **Columns**: `p50_rows_per_insert`, `avg_parts_per_insert`, `max_parts_per_insert`, `inserts_per_second`, `async_inserts` (`12`); `max_parts_in_partition`, `partitions` (`10`); `TOO_MANY_PARTS` in `queries/progress/26_errors_by_code.sql`.
- **Rule**: the knowledge-base causes are small synchronous inserts, a partition key with many values, inserts that touch many partitions (more than one part per insert), and merges that cannot keep up. The fixes are larger batches or async inserts with waiting, and a low-cardinality partition key; raising the part thresholds is not the fix. Rows per insert here come from the parts each insert wrote, not from `written_rows`, which also counts rows written by attached materialized views.
- **Source**: https://clickhouse.com/docs/resources/support-center/knowledge-base/troubleshooting/exception-too-many-parts#diagnose-the-cause , https://clickhouse.com/docs/reference/system-tables/query_log

## Were inserts silently deduplicated?

- **Columns**: `duplicated_blocks` (`12`, `30`).
- **Rule**: a duplicate block is dropped while the client still gets success. A load tool that replays the same batch will see fewer rows than it sent; use `insert_deduplication_token` or vary the data.
- **Source**: https://clickhouse.com/docs/concepts/features/operations/insert/deduplicating-inserts-on-retries#how-insert-deduplication-works

## Did async insert flushes fail?

- **Columns**: `failed_inserts` per table and `status` (`queries/progress/28_async_insert_failures.sql`).
- **Rule**: async inserts are parsed at flush time, and a parsing error rejects the whole payload of that insert. With `wait_for_async_insert = 0` the client never learns of it. If `system.asynchronous_insert_log` does not exist on the service, say so instead of reporting zero.
- **Source**: https://clickhouse.com/docs/concepts/features/operations/insert/asyncinserts#error-handling , https://clickhouse.com/docs/reference/system-tables/asynchronous_insert_log

## Do patch parts slow reads?

- **Columns**: `patch_parts` (`10`).
- **Rule**: patch parts from lightweight updates are applied on every read until they are merged, and while they exist some read optimizations are not used. Batch small frequent updates; for large updates use `ALTER UPDATE`.
- **Source**: https://clickhouse.com/docs/reference/statements/update#performance-considerations
