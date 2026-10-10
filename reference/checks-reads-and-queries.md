# Checks: reads and query shape

Each check names the columns it reads, the rule, and the public source of the rule. Apply a check only when its columns are in the results you ran, and report it only when the numbers show it. The URLs have been checked; cite them as they are.

## How much did each query read for what it returned?

- **Columns**: `avg_read_rows`, `avg_result_rows`, `avg_selected_parts`, `avg_selected_marks`, `marks_read_ratio` (`queries/loadtest/30_window_query_breakdown.sql`); `avg_read_rows`, `avg_result_rows`, `avg_selected_parts`, `avg_selected_marks`, `marks_read_ratio` (`queries/advisor/11_query_efficiency.sql`).
- **Rule**: the primary index selects whole granules of `index_granularity` rows (8192 by default) in each part. A low `marks_read_ratio` does not by itself mean a query reads little. If marks are about equal to parts and read rows are far above result rows, each part contributes about one granule and the rows read follow the number of parts. When marks are close to the table's total marks instead, the sorting key does not match the filters: the ordering key should start with the columns the queries filter on most, especially those that exclude many rows. Candidates are fewer parts or a smaller `index_granularity`. In the ClickHouse source, open-source MergeTree rejects changing `index_granularity` on an existing table (`READONLY_SETTING`), while SharedMergeTree in ClickHouse Cloud accepts `ALTER TABLE ... MODIFY SETTING index_granularity = ...` because each part keeps the granularity it was written with. The new value applies to parts written after the change, so existing data keeps the old granularity until it is rewritten; test the change on a copy and compare `marks` and `read_rows` before advising it.
- **Source**: https://clickhouse.com/docs/concepts/best-practices/choosing-a-primary-key , https://clickhouse.com/docs/guides/clickhouse/data-modelling/sparse-primary-indexes , https://clickhouse.com/docs/reference/settings/merge-tree-settings/index-granularity , ClickHouse source: https://github.com/ClickHouse/ClickHouse/blob/master/src/Storages/MergeTree/MergeTreeSettings.cpp (`isReadonlySetting`, `isSMTReadonlySetting`)

## Was the cache cold?

- **Columns**: `fs_cache_hit_rate`, `avg_s3_read_ms` (`30`); `fs_cache_hit_rate`, `s3_read_wait_seconds` per replica (`31`); `uptime_seconds` (`queries/01_service.sql`).
- **Rule**: the hit rate is cache bytes ÷ (cache bytes + source bytes), as in the Cloud console's advanced dashboard. A low hit rate with high S3 read time at the start of a test, or on a replica with a short uptime, points to a cold cache; measure cold and warm runs separately.
- **Source**: https://clickhouse.com/docs/products/cloud/features/monitoring/cloud-console#advanced-dashboard

## Did a GROUP BY spill to disk?

- **Columns**: `spilled_group_by_executions`, `max_memory_bytes` (`11`).
- **Rule**: once temporary data is flushed to disk, the run takes several times longer (approximately three times). Compare `max_memory_bytes` with the memory limit.
- **Source**: https://clickhouse.com/docs/reference/statements/select/group-by#group-by-in-external-memory

## Is an exact distinct count needed?

- **Columns**: `uses_uniq_exact` (`11`).
- **Rule**: `COUNT(DISTINCT)` uses the function set by `count_distinct_implementation`, `uniqExact` by default. `uniqExact` state grows without bound with the number of distinct values; use it only when the exact result is needed, otherwise `uniq`. Ask whether the result must be exact.
- **Source**: https://clickhouse.com/docs/reference/functions/aggregate-functions/count , https://clickhouse.com/docs/reference/functions/aggregate-functions/uniqExact , https://clickhouse.com/docs/reference/functions/aggregate-functions/uniq

## Does FINAL pay for unmerged parts?

- **Columns**: `final_executions` (`11`), `max_parts_in_partition` of the same table (`queries/advisor/10_table_layout.sql`).
- **Rule**: `FINAL` merges data at query time, so its cost depends on the parts that are not yet merged. `final_executions` matches `FROM` or `JOIN` followed by a table and `FINAL` in the query text, so a column or alias named `final` can also match; confirm with `sample_query`.
- **Source**: https://clickhouse.com/docs/reference/statements/select/from#final-modifier

## Does the query read columns it does not need?

- **Columns**: `avg_columns_read`, `avg_read_bytes` (`11`), the table's column count (`queries/03_columns.sql`).
- **Rule**: when the columns read are close to all of the table's columns, list only the required columns and compare `read_bytes` before and after.
- **Source**: https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/optimization-approaches#read-only-the-required-columns

## Choosing the kind of change

- **Rule**: from the official guide: wide or unneeded columns → reduce the data read; a selective filter that still reads many parts or granules → align the data layout with the query; repeated transformations or aggregations → precompute. Look at a representative run of the pattern, not only the slowest one.
- **Source**: https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/optimization-approaches#choose-an-approach , https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/diagnose-slow-queries#choose-a-representative-query-run

## How to verify a change

- **Rule**: compare under the same cache conditions, change one thing at a time, and use the median of repeated runs after warm-up. For an uncached comparison set `enable_filesystem_cache = 0`, `use_query_cache = 0`, `use_query_condition_cache = 0` and `optimize_use_implicit_projections = 0`; on 25.9 and later also set `use_skip_indexes_on_data_read = 0` before `EXPLAIN indexes = 1`.
- **Source**: https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/isolate-query-bottlenecks

## Were results served from a cache?

- **Columns**: `query_cache_read_share`, `condition_cache_hit_share` (`queries/loadtest/30_window_query_breakdown.sql`), `query_cache_read_share` (`11`).
- **Rule**: a run whose result came from the query cache did not execute the query, and the query condition cache (on by default) lets repeated runs skip granules; do not compare cached runs with uncached ones. In a load test that replays the same queries, report the share next to the latency and treat cached runs as not measuring execution.
- **Source**: https://clickhouse.com/docs/concepts/features/performance/caches/query-cache#configuration-settings-and-usage , https://clickhouse.com/docs/concepts/features/performance/caches/query-condition-cache , https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/isolate-query-bottlenecks

## Are projections used?

- **Columns**: `projections` per table (`queries/advisor/10_table_layout.sql`), `projections_used` per pattern (`11`).
- **Rule**: projections add storage and work on every insert and merge, so use them sparingly. A projection that no pattern in the period used costs without helping; one that is used shows its value.
- **Source**: https://clickhouse.com/docs/concepts/features/projections/projections#when-to-use-projections

## Did a JOIN spill?

- **Columns**: `spilled_join_executions`, `max_memory_bytes` (`11`).
- **Rule**: a hash join builds the right-hand side in memory; when it does not fit, a spilling algorithm is used and the join slows down. Since 24.12 the planner puts the smaller table of a two-table join on the right by itself (since 25.9 also for three or more tables), so first check the join order in `EXPLAIN`; otherwise choose the join algorithm for the sizes involved.
- **Source**: https://clickhouse.com/docs/concepts/features/operations/select/joining-tables#choosing-a-join-algorithm

## Do skipping indexes pay for themselves?

- **Columns**: `avg_skip_index_ms` against `p50_ms` and `marks_read_ratio` (`11`).
- **Rule**: an index pays off only if the granules it skips save more than evaluating it costs. High index time with little pruning (`marks_read_ratio` close to 1) is a net loss; confirm with `EXPLAIN indexes = 1`. `avg_skip_index_ms` is summed over the query's threads, so compare it between patterns or runs, not directly with the wall-clock `p50_ms`.
- **Source**: https://clickhouse.com/docs/concepts/features/performance/skip-indexes/skipping-indexes#skip-best-practices

## Do queries rely on the old analyzer?

- **Columns**: `old_analyzer_executions` (`11`).
- **Rule**: ClickHouse Cloud is moving every service to the new analyzer, and since 26.9 it is mandatory (setting `enable_analyzer = 0` is rejected); patterns that turn it off need to be fixed before the service moves to 26.9.
- **Source**: https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/analyzer#cloud-migration

## Does ORDER BY ... LIMIT read the whole table?

- **Columns**: `avg_read_rows`, `avg_result_rows`, `sample_query` (`queries/advisor/11_query_efficiency.sql`); `sorting_key` (`queries/advisor/10_table_layout.sql`).
- **Rule**: with `ORDER BY ... LIMIT`, the server avoids reading all data only when the `ORDER BY` expression has a prefix that matches the table's sorting key (`optimize_read_in_order`). A pattern whose `sample_query` sorts by other columns and reads far more rows than it returns reads everything before the limit applies. A sorting key on an expression does not match the bare column: a key on `toUnixTimestamp(ts)` is not used by `ORDER BY ts`. To confirm, `EXPLAIN PIPELINE` shows `algorithm: InOrder` when the optimization is used and `algorithm: Thread` for a normal read.
- **Source**: https://clickhouse.com/docs/reference/statements/select/order-by , https://clickhouse.com/docs/resources/support-center/knowledge-base/performance-optimization/why-is-my-primary-key-not-used

## Is a CTE computed more than once?

- **Columns**: `avg_read_rows`, `sample_query` (`11`), `total_rows` of the tables it reads (`10`).
- **Rule**: by default a CTE is inlined at each reference and re-executed every time. A pattern that references the same CTE several times and reads a multiple of its tables' rows pays for each reference.
- **Source**: https://clickhouse.com/docs/reference/statements/select/with

## Are JOIN inputs filtered before the join?

- **Columns**: `avg_read_rows`, `spilled_join_executions`, `max_memory_bytes`, `sample_query` (`11`).
- **Rule**: filters are not always pushed down to both sides of a JOIN; if they are not, rewrite one side as a subquery that filters first, and check the plan with `EXPLAIN`. Ported outer JOINs return the column type's default value for unmatched rows unless `join_use_nulls = 1`, so a query ported from another database can return different results; compare results as well as speed.
- **Source**: https://clickhouse.com/docs/concepts/best-practices/minimize-optimize-joins , https://clickhouse.com/docs/reference/statements/explain

## Are column types left as inferred?

- **Columns**: rows with `check` = `mostly nullable table` (`queries/advisor/13_service_objects.sql`); `type`, compressed and uncompressed bytes per column (`queries/03_columns.sql`).
- **Rule**: use `Nullable` only when empty and NULL must be told apart, and prefer `DateTime` over `DateTime64` unless sub-second precision is needed; `Nullable` adds storage and almost always costs performance. Tables whose columns are mostly `Nullable` usually kept the types of a migration or of schema inference.
- **Source**: https://clickhouse.com/docs/concepts/best-practices/select-data-type , https://clickhouse.com/docs/concepts/best-practices/avoidnullablecolumns

## Does a rollup table actually roll up?

- **Columns**: rows with `check` = `rollup table` (`queries/advisor/13_service_objects.sql`) with `value` (rows) and `sorting_key`; `total_rows` of the source table (`10`).
- **Rule**: `SummingMergeTree` replaces all rows with the same sorting key with one row when merging, and the summed columns must not be in the sorting key. If the sorting key holds a high-cardinality column, rows rarely share a key and the rollup stays almost as large as its source; compare its rows with the source table's.
- **Source**: https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/summingmergetree

## Would parallel replicas help one large query?

- **Columns**: patterns with high `p50_ms` and `avg_read_rows` that run rarely (`11`); `replica` count (`queries/01_service.sql`).
- **Rule**: one query runs on one replica unless parallel replicas are enabled (`enable_parallel_replicas`, off by default). For queries that read a lot of rows it can spread the work; for queries that read few rows the coordination between replicas can make them slower. Suggest it as a candidate to measure, not as a fix.
- **Source**: https://clickhouse.com/docs/products/cloud/features/infrastructure/parallel-replicas
