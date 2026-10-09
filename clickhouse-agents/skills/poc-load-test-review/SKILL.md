---
name: poc-load-test-review
description: Reviews one load test on this ClickHouse service from system tables - where latency went (CPU, waiting for CPU, I/O), whether the replicas ran out of CPU, how much each query read for what it returned, and why autoscaling did or did not react - and proposes what to measure or change next. Use when the user asks about a load test, a benchmark run, latency that rose under load, "負荷試験", "ベンチマークの結果" or "レイテンシが上がった".
always-apply: false
user-invocable: true
---

# PoC load-test review

You explain what happened on a ClickHouse Cloud service during one load test. You read **system tables only**; never select rows from the user's own tables. You cannot change anything: the connection is read-only.

## Rules

- Every observation cites a number from a query result in this conversation, with the query file it came from.
- The URLs in this skill have been checked; cite them as they are without searching for them again. Use the documentation search tool only for facts about ClickHouse behaviour that this skill does not cover, and attach the URL you found.
- Present changes as candidates to verify, not as decisions. Do not promise a speed-up; say what to measure instead.
- Do not recommend a service size, a tier or a price.
- Reading system tables wakes an idled service and keeps it awake, and system tables keep about 30 days. Read `reference/checks-cloud-service.md` for these and for services in a warehouse.
- The reference files can name queries that this skill does not list. They are included; run one only when a finding needs its columns, and say that you did.
- To confirm a finding from these queries, you may write further read-only queries on system tables, for example one query_hash per minute, the parts of one table, or the minutes around an error. Filter on `event_date` and a time range, add `LIMIT`, and do not read message text such as `exception` or `query` beyond what the listed queries already return. In the output, show each query you wrote and mark it as yours, separately from the listed ones.
- Do not output user names or e-mail addresses. `query_tables` may name the user's databases and tables; quoting them is fine.
- The queries leave out this connection's own reads of system tables, but keep every other query of the same database user, so a workload that runs as the same user is still counted. Queries you run on user tables over this connection are counted too, so keep them few and say so if they could change the numbers.
- Answer in the user's language (Japanese if the user writes in Japanese).

## Steps

1. Ask for the test window: start and end, with the time zone. Also ask, if the user knows: the step boundaries (for example 10 → 25 → 50 → 100 requests per second), the target rate per step, and whether the load tool keeps a fixed number of users that each wait for the previous response (closed loop, for example Locust users) or sends at a fixed rate (open loop).
2. Convert the window to UTC. Read these files (the paths are exact; do not guess other names) and replace every `now() - INTERVAL 1 HOUR /*window_start*/` with `toDateTime('<start>', 'UTC')` and every `now() /*window_end*/` with `toDateTime('<end>', 'UTC')`:
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

## Report format

- **Summary**: two to four sentences: what limited the test, and the one or two next steps.
- **Latency**: per step, the busiest `query_hash` with `p50_ms`, `avg_cpu_ms`, `avg_cpu_wait_ms`, `avg_io_wait_ms` (from `30`), and the achieved rate against the target.
- **CPU**: per replica, the peak `cpu_wait_ratio`, `container_cpu_cores`, `container_system_cores`, `cpu_cores` and `cpu_limit_cores` (from `31` and `01`), with the 10-second interval.
- **Reads**: queries where `avg_read_rows` is far above `avg_result_rows`, with parts and marks.
- **Errors, inserts, cache and balance**: only what the results show: the most frequent error codes, delayed or rejected inserts, a cold cache, or uneven load across replicas. Leave out a line when nothing stands out.
- **Autoscaling**: what the documentation says and what that means for this test's step length.
- **Next steps**: candidates to verify, each with how to measure it, from `reference/checks-autoscaling-and-test-design.md` and the checks that found something.
