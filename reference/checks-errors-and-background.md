# Checks: errors and background work

Each check names the columns it reads, the rule, and the public source of the rule. Apply a check only when its columns are in the results you ran, and report it only when the numbers show it. The URLs have been checked; cite them as they are.

## Which errors, and what next?

- **Columns**: `error`, `query_kind`, `query_hash`, `failures` (`queries/progress/26_errors_by_code.sql`).
- **Rule**: route each frequent code to its source: `TOO_MANY_PARTS` → "Why are there too many parts?" in `reference/checks-inserts-and-parts.md`; `MEMORY_LIMIT_EXCEEDED` → "Was memory under pressure?" in `reference/checks-cpu-and-concurrency.md`; `TOO_MANY_SIMULTANEOUS_QUERIES` → the limit of 1000 concurrent queries per replica. For any other code, look it up with the documentation search tool before explaining it. The query does not return message text; do not ask for it.
- **Source**: https://clickhouse.com/docs/resources/support-center/knowledge-base/troubleshooting/exception-too-many-parts , https://clickhouse.com/docs/resources/support-center/knowledge-base/performance-optimization/memory-limit-exceeded-for-query , https://clickhouse.com/docs/products/cloud/reference/architecture#concurrency-limits

## Are mutations stuck or failing?

- **Columns**: rows with `check` = `unfinished mutation` (`queries/progress/27_background_health.sql`).
- **Rule**: mutations rewrite whole parts, run in order and cannot be rolled back. An unfinished mutation with a `failing=` code cannot finish; it holds back later mutations until it is killed (`KILL MUTATION`; changes already made stay). A mutation that is killed but not done can stay listed for a while in Cloud. Prefer designs that avoid mutations.
- **Source**: https://clickhouse.com/docs/reference/system-tables/mutations#monitoring-mutations , https://clickhouse.com/docs/reference/statements/kill#kill-mutation , https://clickhouse.com/docs/concepts/best-practices/avoid-mutations

## Is background work failing?

- **Columns**: rows with `check` = `failed MergeParts`, `failed MutatePart`, `failed NewPart`, `failed DownloadPart` (`27`).
- **Rule**: a non-zero error on a merge or a mutation of a part means background work is failing; read the code (for example `MEMORY_LIMIT_EXCEEDED`) with the matching check. Rows with `check` = `deduplicated insert` are not failures: a duplicate block was dropped on purpose; judge them with "Were inserts silently deduplicated?" in `reference/checks-inserts-and-parts.md`.
- **Source**: https://clickhouse.com/docs/reference/system-tables/part_log

## Are refreshable materialized views failing?

- **Columns**: rows with `check` = `refreshable view failing` (`27`).
- **Rule**: a view with an exception is not refreshing; `first_time` is its last success. Keep an eye on `system.view_refreshes`.
- **Source**: https://clickhouse.com/docs/reference/statements/system#managing-refreshable-materialized-views , https://clickhouse.com/docs/reference/system-tables/view_refreshes

## Long-running merges

- **Columns**: rows with `check` = `running merge` or `running mutation of a part` (`27`).
- **Rule**: report the longest ones next to the parts checks. The documentation gives no threshold; do not call a merge too slow from its duration alone.
- **Source**: https://clickhouse.com/docs/reference/system-tables/merges
