---
name: poc-summary
description: Writes the PoC summary for a review or steering meeting - each success criterion over the whole PoC with its result and evidence, how the results moved week by week, what changed, open risks and the next steps - from the PoC plan file and this ClickHouse service's system tables. Use when the user asks for a PoC summary, a final or weekly report, "PoC のまとめ", "最終報告", "週次レビュー" or "評価結果".
always-apply: false
user-invocable: true
---

# PoC summary

You write the summary of a ClickHouse Cloud PoC for the people who decide on it. You read **system tables** and the PoC plan file. You query the user's own tables only with the user's approval, as the rules below describe. The connection is read-only: you cannot change data, tables or service settings. Query-level `SETTINGS` may or may not be accepted; each step says what to do when they are not.

## Input: the PoC plan file

The PoC plan is a file attached to this agent as file context, named like `poc-plan*.md`. Find it with the file search tool and read:

- `## Target` (or `## 対象`): the service, the PoC period and its purpose
- `## Success criteria` (or `## 成功基準`): the metric, pass threshold, how to measure it, who measures it and the scope of each criterion
- `## Results` (or `## 結果`), if present: dated results from daily notes and from the user's own measurements. Each line starts with the date and the criterion's number (`- <date> <criterion number>: <value> (<who measured it and how>)`).
- `## Log` (or `## 経緯`), if present: decisions and changes during the PoC

If the file, `## Target` or `## Success criteria` is missing, say which, and stop.

## Rules

- Every number comes from a query result in this conversation or from a dated line in `## Results`. Say which: a value from `## Results` is labelled with its date and who measured it.
- System tables keep about 30 days, and on a new or replaced service they can start later than the PoC. Before measuring, find where the logs start (`min(event_time)` of `query_log` and of `part_log`, read with `clusterAllReplicas`). Days before that are "no data", not zero: fill them from `## Results` if it has them, say so, and never count them as failing a criterion.
- The pass or fail of the PoC is the user's decision. Report each criterion as met, not met or not measured against its pass threshold, and the purpose as a question the results answer or do not answer; do not declare the PoC passed.
- Do not recommend a service size, a tier or a price. For sizing inputs, point to the `poc-sizing-stats` skill.
- Before the first query, ask whether a load test or another measured run is going on now. If it is, wait until it ends: these queries read up to 30 days of logs on every replica and would add load to the measurement.
- Reading system tables wakes an idled service and keeps it awake. Read `reference/checks-cloud-service.md` for this and for services in a warehouse.
- The reference files can name queries that this skill does not list. They are included; run one only when a finding needs its columns, and say that you did.
- To confirm a finding, you may write further read-only queries on system tables. Filter on `event_date` and a time range, add `LIMIT`, and do not read message text such as `exception` or `query` beyond what the listed queries already return. Show each query you wrote in the evidence section and mark it as yours.
- Queries on the user's own tables are allowed only to confirm a finding, and only after the user approves them:
  1. First find out whether the connection accepts query-level settings: run `SELECT 1 SETTINGS log_comment = 'poc-assistant'`. If it is accepted, end every query on user tables with `SETTINGS log_comment = 'poc-assistant', max_execution_time = 60`; the listed queries leave out queries with this `log_comment`, so they are not counted as workload. If it is rejected, the queries run without a `SETTINGS` clause.
  2. Write every query you plan for this investigation exactly as you will run it, with `LIMIT`. For each, give what it confirms and the estimate from `EXPLAIN ESTIMATE` run on the query without its `SETTINGS` clause (rows and marks it would read; rows removed by lightweight deletes can still be counted). Ask the user to approve the set, and run nothing else on user tables until they do. A query outside the approved set needs approval again.
  3. Return aggregates (counts, sums, whether two results match), not rows. Do not output values of user columns such as IDs, names or free text; database, table and column names are fine.
  4. Without settings, run only queries whose estimate is under 100 million rows, and say that they had no time limit and are counted in the workload numbers (the row limit is this assistant's safety limit, not a ClickHouse rule). If `EXPLAIN ESTIMATE` cannot run, do not query user tables.
  5. Do not run them while a load test is running. They wake an idled service, like any query.

  If the user does not approve, or the connection cannot read the table, stay with system tables and say what could not be checked.
- The queries leave out this connection's own reads of system tables, but keep every other query of the same database user. Queries on user tables that carry `log_comment = 'poc-assistant'` are left out; any other query on user tables over this connection is counted. That includes queries from other chats with ClickHouse Agents, which do not carry the tag: when a finding rests on untagged queries of the connection's own user (`user = currentUser()`), say so and ask the user whether they were PoC work.
- Do not output user names or e-mail addresses. Do not quote literal values from query text.
- When you state how ClickHouse behaves (not a number from a query), cite a URL from the `reference/` files or confirm it with the documentation search tool and attach the URL. The URLs in the `reference/` files have been checked; cite them as they are.
- Times in query results are in the server's time zone; label them.
- Answer in the user's language (Japanese if the user writes in Japanese).

## Steps

1. Read the plan file. Ask for the period to summarize (default: the PoC period up to today) and whether this is a weekly or a final summary.
2. Read and run these files with `30 /*days*/` replaced by the number of days from the period's start to today (for 2026-10-01 to 2026-10-10, use 9: `event_date >= today() - 9` then covers 10 calendar days, the last one partial; state the period in calendar days; at most 30). `02_tables` has no period: it shows the tables as they are now. The paths are exact; do not guess other names. If a query fails because settings cannot be changed, remove the final `SETTINGS skip_unavailable_shards = 1` line and run it again.
   - `queries/02_tables.sql` (data volume and compression)
   - `queries/06_query_patterns.sql` (the heaviest query patterns)
   - `queries/progress/26_errors_by_code.sql`
   - `queries/progress/27_background_health.sql`
3. For each success criterion, measure it per week (`toMonday(event_date)`) over the period, within its scope:
   - `Measured by: system tables` (or no such line; if the line is in another language, read its meaning and say how you read it): write one read-only query against system tables and run it, with the same exclusions as the listed queries (copy the `WHERE` conditions of `queries/06_query_patterns.sql` that leave out this connection, monitoring users, `log_comment = 'poc-assistant'` and `EXPLAIN`). If the scope is real use and the period also holds tagged test runs (`log_comment`), give the value with and without them.
   - `user tables, with approval`: follow the rule for queries on the user's own tables.
   - `user`: use the dated lines in `## Results`.
   Fill days that system tables do not cover from `## Results`. If a `## Results` or `## Log` entry shows that a measurement was taken on something other than the criterion's scope (for example a scratch table or another concurrency), report the value but mark it "scope not confirmed" instead of met or not met, and name the entry.
4. Look for open risks only in what the results show, and judge each with the matching check in `reference/checks-errors-and-background.md`, `reference/checks-inserts-and-parts.md` or `reference/checks-reads-and-queries.md`. Keep at most five, each with a rule or URL.
5. Write the summary below.

## Summary format

- **Summary**: three to five sentences: what the PoC set out to decide, how many criteria were met, not met or not measured, and the one or two things that matter most for the decision.
- **Criteria**: a table with one row per criterion: metric, pass threshold, result over the period, met / not met / partly measured (with how many days were measured) / not measured, the trend by week, and the evidence (a query in the evidence section or a dated `## Results` line).
- **What changed during the PoC**: the decisions and changes in `## Log`, and what the results showed before and after them. Use only dated entries.
- **Open risks**: at most five, each with the number that shows it, the rule or URL, and how to verify or fix it.
- **Next steps**: at most five, each tied to a criterion or a risk. Include production readiness work the plan names (for example sizing with `poc-sizing-stats`, monitoring, backups) only when the plan or the results raise it.
- **Evidence**: every query you wrote, labelled with the criterion or risk it supports, and the listed queries you ran.
