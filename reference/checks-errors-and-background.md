# Checks: errors and background work

Each check names the columns it reads, the rule, and the public source of the rule. Apply a check only when its columns are in the results you ran, and report it only when the numbers show it. The URLs have been checked; cite them as they are.

## Which errors, and what next?

- **Columns**: `error`, `query_kind`, `query_hash`, `failures` (`queries/progress/26_errors_by_code.sql`).
- **Rule**: route each frequent code to its source: `TOO_MANY_PARTS` → "Why are there too many parts?" in `reference/checks-inserts-and-parts.md`; `MEMORY_LIMIT_EXCEEDED` → "Was memory under pressure?" in `reference/checks-cpu-and-concurrency.md`; `TOO_MANY_SIMULTANEOUS_QUERIES` → "Why did queries fail?" in `reference/checks-cpu-and-concurrency.md` (the per-replica limit or a lower `max_concurrent_*` setting); `TIMEOUT_EXCEEDED` → "Why did a query time out?" below. For any other code, look it up with the documentation search tool before explaining it. The query does not return message text; do not ask for it. A failure that happened before a query started keeps no tables, so a failed query of this connection itself (for example one rejected as read-only) can appear here; if its time matches a query you ran, say so instead of reporting it as the user's error.
- **Source**: https://clickhouse.com/docs/resources/support-center/knowledge-base/troubleshooting/exception-too-many-parts , https://clickhouse.com/docs/resources/support-center/knowledge-base/performance-optimization/memory-limit-exceeded-for-query , https://clickhouse.com/docs/products/cloud/reference/architecture#concurrency-limits , https://clickhouse.com/docs/reference/settings/session-settings/max-concurrent

## Why did a query time out?

- **Columns**: `TIMEOUT_EXCEEDED` (code 159) in `queries/progress/26_errors_by_code.sql` or in `top_errors` (`queries/loadtest/30_window_query_breakdown.sql`).
- **Rule**: `max_execution_time` is checked against a projected time: after `timeout_before_checking_execution_speed` (10 seconds by default) the server estimates the total execution time and stops the query if the estimate exceeds the limit, so a query can fail well before it reaches the limit. It can also run past the limit, because it cannot be stopped while merging aggregation states or during most of query analysis. Before suggesting a higher limit, ask which limit the client or the user's profile sets, and look at the pattern's read volume with "How much did each query read for what it returned?" in `reference/checks-reads-and-queries.md`.
- **Source**: https://clickhouse.com/docs/reference/settings/session-settings/max-execution

## Are mutations stuck or failing?

- **Columns**: rows with `check` = `unfinished mutation` (`queries/progress/27_background_health.sql`).
- **Rule**: mutations rewrite whole parts, run in order and cannot be rolled back. An unfinished mutation with a `failing=` code is retrying; it holds back later mutations. If the code shows the mutation itself cannot be applied to the data (for example a function in it throws), it is stuck and can be killed (`KILL MUTATION`; changes already made stay); a transient code such as `MEMORY_LIMIT_EXCEEDED` may clear on retry, so check whether `parts_to_do` still falls before suggesting a kill. A mutation that is killed but not done can stay listed for a while in Cloud. Prefer designs that avoid mutations.
- **Source**: https://clickhouse.com/docs/reference/system-tables/mutations#monitoring-mutations , https://clickhouse.com/docs/reference/statements/kill#kill-mutation , https://clickhouse.com/docs/concepts/best-practices/avoid-mutations

## Is background work failing?

- **Columns**: rows with `check` = `failed MergeParts`, `failed MutatePart`, `failed NewPart`, `failed DownloadPart` (`27`).
- **Rule**: a non-zero error on a merge or a mutation of a part means background work is failing; read the code (for example `MEMORY_LIMIT_EXCEEDED`) with the matching check. Rows with `check` = `deduplicated insert` are not failures: a duplicate block was dropped on purpose; judge them with "Were inserts silently deduplicated?" in `reference/checks-inserts-and-parts.md`.
- **Source**: https://clickhouse.com/docs/reference/system-tables/part_log

## Are refreshable materialized views failing?

- **Columns**: rows with `check` = `refreshable view failing` (`27`).
- **Rule**: a view with an exception is not refreshing. `detail` holds the latest success (`last_success=none` when no replica has had one since it started), and `occurrences` is the number of replicas that report the failure, not the number of failed refreshes. Keep an eye on `system.view_refreshes`.
- **Source**: https://clickhouse.com/docs/reference/statements/system#managing-refreshable-materialized-views , https://clickhouse.com/docs/reference/system-tables/view_refreshes

## Is a dictionary empty or failing?

- **Columns**: rows with `check` = `dictionary empty or failed` (`queries/advisor/13_service_objects.sql`): the dictionary and replica, `element_count` as `value`, `status` in `detail`. Only failed dictionaries and loaded ones with no elements are listed, leaving out direct and cache layouts, which hold no elements by design; `NOT_LOADED` is normal, because by default a dictionary stays in that status until its first use. The user needs the `SHOW DICTIONARIES` grant to see them (`export/setup_user.sql` has it).
- **Rule**: in ClickHouse Cloud a dictionary can be created or reloaded on a replica before the data it reads has reached that replica, so replicas can disagree and a dictionary can stay empty. With `LIFETIME(MIN 0 MAX 0)` it is never refreshed automatically and stays empty until `SYSTEM RELOAD DICTIONARIES`. The documented fix is a `SELECT` query as the source with `select_sequential_consistency = 1`.
- **Source**: https://clickhouse.com/docs/resources/support-center/knowledge-base/data-management/dictionaries-consistent-state , https://clickhouse.com/docs/reference/system-tables/dictionaries#columns , https://clickhouse.com/docs/reference/settings/server-settings/settings/dictionaries#dictionaries_lazy_load

## Are there detached parts?

- **Columns**: rows with `check` = `detached part` (`27`): the table, the `reason` in `detail`, and the count per replica.
- **Rule**: the server forgets detached data until it is attached again, so queries do not read it. The knowledge base lists detached parts among the things that might need investigation; report the table and the reason. An empty reason means a user detached the part; `invalid part name` means the server could not parse the part's name. Do not suggest attaching or dropping them; that is the user's decision, and a support case is the place to ask when the reason is not one the user expected.
- **Source**: https://clickhouse.com/docs/resources/support-center/knowledge-base/queries-sql/useful-queries-for-troubleshooting#detached-parts , https://clickhouse.com/docs/reference/system-tables/detached_parts , https://clickhouse.com/docs/reference/statements/alter/partition#detach-partitionpart

## Long-running merges

- **Columns**: rows with `check` = `running merge` or `running mutation of a part` (`27`).
- **Rule**: report the longest ones next to the parts checks. The documentation gives no threshold; do not call a merge too slow from its duration alone.
- **Source**: https://clickhouse.com/docs/reference/system-tables/merges
