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
- **Source**: https://clickhouse.com/docs/resources/support-center/knowledge-base/troubleshooting/exception-too-many-parts#diagnose-the-cause , https://clickhouse.com/docs/reference/system-tables/query_log , https://clickhouse.com/docs/concepts/core-concepts/partitions

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

## Is the partition key too fine?

- **Columns**: `partitions`, `partition_key`, `max_parts_in_partition` (`queries/advisor/10_table_layout.sql`).
- **Rule**: a low-cardinality partitioning key, with fewer than about 100 to 1,000 distinct values, is usually optimal. Partitioning is a data management technique (for example dropping old data), not a query optimization tool; a key such as tenant × month multiplies partitions, and parts spread across many partitions are never merged together.
- **Source**: https://clickhouse.com/docs/concepts/best-practices/partitioning-keys , https://clickhouse.com/docs/concepts/core-concepts/partitions

## Does each insert touch many partitions?

- **Columns**: `avg_parts_per_insert`, `max_parts_per_insert` (`12`); `TOO_MANY_PARTITIONS` in `queries/progress/26_errors_by_code.sql`.
- **Rule**: an insert that touches many partitions writes more than one part (one of the knowledge-base causes of too many parts), and more partitions than `max_partitions_per_insert_block` in one block logs a warning or fails. A backfill from source files that are not ordered by the partition key makes every block touch many partitions; sort or split the load by partition first.
- **Source**: https://clickhouse.com/docs/resources/support-center/knowledge-base/troubleshooting/exception-too-many-parts#diagnose-the-cause , https://clickhouse.com/docs/reference/settings/session-settings/max-partitions

## Are backfills one large INSERT ... SELECT?

- **Columns**: rows with `check` = `insert select` (`queries/advisor/13_service_objects.sql`): count, `max_duration_s`, `failed`, `memory_limit`.
- **Rule**: one large `INSERT ... SELECT` cannot be resumed when it fails, for example on a network interruption; split it into batches by range or by file. It runs on one replica unless `parallel_distributed_insert_select = 2` and `enable_parallel_replicas = 1` (since 25.4 for `SharedMergeTree` sources). With `async_insert = 1`, an `INSERT ... SELECT` takes the asynchronous route only when its whole result is one block within `async_insert_max_data_size`; otherwise it runs synchronously.
- **Source**: https://clickhouse.com/docs/guides/clickhouse/data-modelling/backfilling , https://clickhouse.com/docs/reference/settings/session-settings/parallel , https://clickhouse.com/docs/concepts/features/operations/insert/async-insert-select

## Are deletes or updates the main write path?

- **Columns**: rows with `check` = `deletes and updates` (`queries/advisor/13_service_objects.sql`); `unfinished mutation` rows (`queries/progress/27_background_health.sql`).
- **Rule**: deleting large volumes with lightweight `DELETE` can slow `SELECT` queries, and mutations rewrite parts. If deletes or updates run as often as inserts (for example a delete-then-insert model), consider engines and patterns that avoid mutations.
- **Source**: https://clickhouse.com/docs/concepts/features/operations/delete/lightweight-delete , https://clickhouse.com/docs/concepts/best-practices/avoid-mutations
