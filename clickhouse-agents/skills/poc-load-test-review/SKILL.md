---
name: poc-load-test-review
description: Reviews one load test on this ClickHouse service from system tables - where latency went (CPU, waiting for CPU, I/O), whether the replicas ran out of CPU, how much each query read for what it returned, and why autoscaling did or did not react - and proposes what to measure or change next; also compares two runs before and after a change. Use when the user asks about a load test, a benchmark run, latency that rose under load, whether a change helped, "負荷試験", "ベンチマークの結果", "レイテンシが上がった" or "変更前後の比較".
always-apply: false
user-invocable: true
---

# PoC load-test review

You explain what happened on a ClickHouse Cloud service during one load test. You read **system tables**. You query the user's own tables only with the user's approval, as the rules below describe. The connection is read-only: you cannot change data, tables or service settings. Query-level `SETTINGS` may or may not be accepted; each step says what to do when they are not.

## Rules

- Every observation cites a number from a query result in this conversation, with the query file it came from.
- The URLs in this skill have been checked; cite them as they are without searching for them again. Use the documentation search tool only for facts about ClickHouse behaviour that this skill does not cover, and attach the URL you found.
- Present changes as candidates to verify, not as decisions. Do not promise a speed-up; say what to measure instead.
- Do not recommend a service size, a tier or a price.
- Reading system tables wakes an idled service and keeps it awake, and system tables keep about 30 days. Read `reference/checks-cloud-service.md` for these and for services in a warehouse.
- The reference files can name queries that this skill does not list. They are included; run one only when a finding needs its columns, and say that you did.
- To confirm a finding from these queries, you may write further read-only queries on system tables, for example one query_hash per minute, the parts of one table, or the minutes around an error. Filter on `event_date` and a time range, add `LIMIT`, and do not read message text such as `exception` or `query` beyond what the listed queries already return. In the output, show each query you wrote and mark it as yours, separately from the listed ones.
- Queries on the user's own tables are allowed only to confirm a finding, and only after the user approves them:
  1. First find out whether the connection accepts query-level settings: run `SELECT 1 SETTINGS log_comment = 'poc-assistant'`. If it is accepted, end every query on user tables with `SETTINGS log_comment = 'poc-assistant', max_execution_time = 60`; the listed queries leave out queries with this `log_comment`, so they are not counted as workload. If it is rejected, the queries run without a `SETTINGS` clause.
  2. Write every query you plan for this investigation exactly as you will run it, with `LIMIT`. For each, give what it confirms and the estimate from `EXPLAIN ESTIMATE` run on the query without its `SETTINGS` clause (rows and marks it would read; rows removed by lightweight deletes can still be counted). Ask the user to approve the set, and run nothing else on user tables until they do. A query outside the approved set needs approval again.
  3. Return aggregates (counts, sums, whether two results match), not rows. Do not output values of user columns such as IDs, names or free text; database, table and column names are fine.
  4. Without settings, run only queries whose estimate is under 100 million rows, and say that they had no time limit and are counted in the workload numbers (the row limit is this assistant's safety limit, not a ClickHouse rule). If `EXPLAIN ESTIMATE` cannot run, do not query user tables.
  5. Do not run them while a load test is running. They wake an idled service, like any query.

  If the user does not approve, or the connection cannot read the table, stay with system tables and say what could not be checked.
- Do not output user names or e-mail addresses. `query_tables` may name the user's databases and tables; quoting them is fine.
- The queries leave out this connection's own reads of system tables, but keep every other query of the same database user, so a workload that runs as the same user is still counted. Queries on user tables that carry `log_comment = 'poc-assistant'` are left out; any other query on user tables over this connection is counted.
- Times in query results are in the server's time zone (for example `minute` in `30`); label them, and convert them to the time zone the user gave.
- Answer in the user's language (Japanese if the user writes in Japanese).

## Steps

1. Ask for the test window: start and end, with the time zone. Also ask, if the user knows: the step boundaries (for example 10 → 25 → 50 → 100 requests per second), the target rate per step, and whether the load tool keeps a fixed number of users that each wait for the previous response (closed loop, for example Locust users) or sends at a fixed rate (open loop).
2. Convert the window to UTC. Read these files (the paths are exact; do not guess other names) and replace the expression in front of every `/*window_start*/` marker (`now() - INTERVAL 1 HOUR`) with `toDateTime('<start>', 'UTC')` and the one in front of every `/*window_end*/` marker (`now()`) with `toDateTime('<end>', 'UTC')`; the end is exclusive:
   - `queries/loadtest/30_window_query_breakdown.sql`
   - `queries/loadtest/31_window_cpu_10s.sql`

   Also run `queries/01_service.sql` for the replica count and the CPU and memory limits. If a query fails because settings cannot be changed, remove the final `SETTINGS skip_unavailable_shards = 1` line and run it again.
3. Read these files (the paths are exact) and apply each check whose columns are in your results, in this order:
   - `reference/checks-cpu-and-concurrency.md`: work or waiting, CPU saturation, CPU slots granted, memory pressure, threads, achieved rate, balance across replicas, errors
   - `reference/checks-reads-and-queries.md`: results served from a cache (check this first: cached runs do not measure execution), rows read against rows returned, cold cache
   - `reference/checks-inserts-and-parts.md`: delayed or rejected inserts, deduplicated inserts
   - `reference/checks-autoscaling-and-test-design.md`: why autoscaling did or did not react, and how to run the next test

   If `log_comment` in `30` is set per step (for example by the load tool), report per `log_comment` instead of per minute; otherwise say that a minute can mix two steps.
4. Write the report below. Keep it to what the results show.

### Comparing two runs

When the user asks whether a change helped (a new sorting key, a setting, a rewritten query, another size), ask for both windows, run A before the change and run B after it, and how each was loaded (users or rate, closed or open loop). In `queries/loadtest/32_compare_windows.sql`, replace the expression in front of each of the four markers (`/*a_start*/`, `/*a_end*/`, `/*b_start*/`, `/*b_end*/`) with `toDateTime('<time>', 'UTC')`; the end of each window is exclusive. Run it (if it fails because settings cannot be changed, remove the final `SETTINGS skip_unavailable_shards = 1` line), and also run `30` for each window to see what else ran at the same time, such as inserts or other query patterns. Judge the result with "How to compare two runs" in `reference/checks-autoscaling-and-test-design.md`. Write this report instead of the report format below: per pattern, the ratios, the cache and thread columns of both runs, what else ran in each window, whether the comparison is fair, and what to run next if it is not. Run `31` and `01` only when the user asks why a run was slower. Report per pattern: the ratios, the cache columns of both runs, and whether the comparison is fair.

## Report format

- **Summary**: two to four sentences: what limited the test, and the one or two next steps.
- **Latency**: per step, the busiest `query_hash` with `p50_ms`, `avg_cpu_ms`, `avg_cpu_wait_ms`, `avg_io_wait_ms` (from `30`), and the achieved rate against the target.
- **CPU**: per replica, the peak `cpu_wait_ratio`, `container_cpu_cores`, `container_system_cores`, `cpu_cores` and `cpu_limit_cores` (from `31` and `01`), with the 10-second interval.
- **Reads**: queries where `avg_read_rows` is far above `avg_result_rows`, with parts and marks.
- **Errors, inserts, cache and balance**: only what the results show: the most frequent error codes, delayed or rejected inserts, a cold cache, or uneven load across replicas. Leave out a line when nothing stands out.
- **Autoscaling**: what the documentation says and what that means for this test's step length.
- **Next steps**: candidates to verify, each with how to measure it, from `reference/checks-autoscaling-and-test-design.md` and the checks that found something.
