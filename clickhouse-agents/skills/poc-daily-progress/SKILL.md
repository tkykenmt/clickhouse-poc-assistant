---
name: poc-daily-progress
description: Writes the daily PoC progress note for this ClickHouse service - what changed in the last 24 hours, where each success criterion stands, new table and query advice limited to what changed, and the next actions - using the PoC plan file attached to the agent. Use when the user asks for PoC progress, "進捗", "日次のまとめ" or "ネクストアクション".
always-apply: false
user-invocable: true
---

# PoC daily progress

You write a short daily note on a ClickHouse Cloud PoC. You read **system tables**. You query the user's own tables only with the user's approval, as the rules below describe. The connection is read-only: you cannot change data, tables or service settings. Query-level `SETTINGS` may or may not be accepted; each step says what to do when they are not.

## Input: the PoC plan file

The PoC plan is a file attached to this agent as file context, named like `poc-plan*.md`. Find it with the file search tool and read these sections:

- `## Target` (or `## 対象`): the service, the PoC period and the start date
- `## Success criteria` (or `## 成功基準`): one item per criterion - the metric, the pass threshold, how to measure it, and, in newer plans, who measures it and its scope
- `## Results` (or `## 結果`), if present: results recorded on earlier days and results the user measured
- `## Log` (or `## 経緯`), if present: earlier decisions and open next actions

If the file or either required section is missing, say which section is missing, list the required sections above, and stop. Nothing is written back to the file: compare with the previous day by querying system tables again, not by remembering.

## Rules

- Every number comes from a query result in this conversation. Show the SQL you wrote for a criterion.
- A `nan` or NULL in a 7-day column means there is no baseline (nothing ran in that window); say "no baseline" instead of comparing.
- The queries leave out this connection's own reads of system tables, but keep every other query of the same database user, so a workload that runs as the same user is still counted. Queries on user tables that carry `log_comment = 'poc-assistant'` are left out; any other query on user tables over this connection is counted. If SELECT or INSERT counts are unexpectedly zero, say so.
- Do not recommend a service size, a tier or a price. Do not output user names or e-mail addresses.
- Before the first query, ask whether a load test or another measured run is going on now. If it is, wait until it ends: these queries read up to 30 days of logs on every replica and would add load to the measurement.
- Reading system tables wakes an idled service and keeps it awake, and system tables keep about 30 days. Read `reference/checks-cloud-service.md` for these and for services in a warehouse.
- The reference files can name queries that this skill does not list. They are included; run one only when a finding needs its columns, and say that you did.
- To confirm a finding from these queries, you may write further read-only queries on system tables, for example one query_hash per minute, the parts of one table, or the minutes around an error. Filter on `event_date` and a time range, add `LIMIT`, and do not read message text such as `exception` or `query` beyond what the listed queries already return. In the output, show each query you wrote and mark it as yours, separately from the listed ones.
- Queries on the user's own tables are allowed only to confirm a finding, and only after the user approves them:
  1. Write every query you plan for this investigation first. For each, give the SQL, what it confirms, and the estimate from `EXPLAIN ESTIMATE <query>` (rows and marks it would read). Ask the user to approve the set, and run nothing on user tables until they do. A query outside the approved set needs approval again.
  2. Return aggregates (counts, sums, whether two results match), not rows. Do not output values of user columns such as IDs, names or free text; database, table and column names are fine.
  3. Add `LIMIT` and `SETTINGS log_comment = 'poc-assistant', max_execution_time = 60`. The listed queries leave out queries with this `log_comment`, so they are not counted as workload. If the connection cannot change settings, run only queries whose estimate is under 100 million rows, without the `SETTINGS` clause, and say that they had no time limit and are counted in the workload numbers (the row limit is this assistant's safety limit, not a ClickHouse rule). If `EXPLAIN ESTIMATE` cannot run, do not query user tables.
  4. Do not run them while a load test is running. They wake an idled service, like any query.

  If the user does not approve, or the connection cannot read the table, stay with system tables and say what could not be checked.
- When you state how ClickHouse behaves (not a number from a query), confirm it with the documentation search tool and attach the URL.
- Answer in the user's language (Japanese if the user writes in Japanese). Keep the note's prose under 40 lines; put the SQL you wrote in a section after the note, which does not count.

## Steps

1. Read and run these files. The paths are exact; do not guess other names.
   - `queries/progress/20_daily_digest.sql`
   - `queries/progress/21_parts_health.sql`
   - `queries/progress/22_new_query_patterns.sql`
   - `queries/progress/23_changed_query_patterns.sql`
   - `queries/progress/24_table_changes.sql`
   - `queries/progress/25_insert_shape_change.sql`
   - `queries/progress/26_errors_by_code.sql`, `queries/progress/27_background_health.sql` and `queries/progress/28_async_insert_failures.sql`, each with `30 /*days*/` replaced by `1`

   Judge read and cache changes with `reference/checks-reads-and-queries.md` (for example a p99 that fell because results came from the query cache).

   If a query fails because settings cannot be changed, remove the final `SETTINGS skip_unavailable_shards = 1` line and run it again.
2. For each success criterion, measure it for the last 24 hours and for the 7 days before, within its scope, and compare both with the pass threshold:
   - `Measured by: system tables` (or no such line; if the line is in another language, read its meaning and say how you read it): write one read-only query against system tables, run it, and show it.
   - `user tables, with approval`: follow the rule for queries on the user's own tables.
   - `user`: take the latest value from `## Results` and give its date; if there is none, say the user has not recorded one.
3. Find what is new or changed. Look only at these, so advice is not repeated on days when nothing changed:
   - new SELECT patterns from `22` that are among the heaviest (by `total_cpu_seconds`) or read most of their tables (`marks_read_ratio`)
   - patterns from `23` whose `p99_ratio` or `read_rows_ratio` is 2 or more with at least 10 executions in the last 24 hours (this is a reporting threshold for change, not a ClickHouse recommendation)
   - tables from `24` that were created or altered
   - tables from `25` whose `p50_rows_per_insert_24h` fell to half or less of the 7-day value, and tables from `21` whose `max_parts_in_partition` stands out
   - tables from `25` with `async_inserts_without_wait_24h` above 0: with `wait_for_async_insert = 0` the client is not told when a flush fails (https://clickhouse.com/docs/concepts/features/operations/insert/asyncinserts#choosing-a-return-mode)
   - error codes from `26`, and stuck or failing background work from `27`, judged with `reference/checks-errors-and-background.md`
   - failed async insert flushes from `28`, judged with "Did async insert flushes fail?" in `reference/checks-inserts-and-parts.md`
   For each of these, check the matching rule in the `clickhouse-best-practices` skill (and `clickhouse-architecture-advisor` for pattern choices) and the documentation search tool. Keep at most three findings that a rule or a documentation page supports; drop the rest. `sample_query` has literal values replaced by `?`; quote column names, JSON keys and functions from it.
4. Write the note:
   - **Last 24 hours**: ingest and query volume against the previous 7-day average, p99 latency, errors, the table with the most parts in one partition. Mention only what changed notably.
   - **Success criteria**: one line each - value in the last 24 hours, value over the 7 days before, pass threshold, met / not met / not measurable.
   - **New advice**: at most three findings from step 3. For each: target (table or query_hash), what changed with the numbers, candidate, rule name or documentation URL, and how to verify. If there is nothing, write a single line saying there is no new finding.
   - **Next actions**: at most three, each tied to a criterion, an observation or a finding above.
   - **Lines for the plan**: one line per criterion in the `## Results` format (`- <date> <criterion number>: <value> (daily note, <query or source>)`), in a code block the user can paste into the plan file. Nothing is written back automatically.
