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
- `## Results` (or `## 結果`), if present: dated results from daily notes and from the user's own measurements
- `## Log` (or `## 経緯`), if present: decisions and changes during the PoC

If the file, `## Target` or `## Success criteria` is missing, say which, and stop.

## Rules

- Every number comes from a query result in this conversation or from a dated line in `## Results`. Say which: a value from `## Results` is labelled with its date and who measured it.
- System tables keep about 30 days. For weeks older than that, use `## Results` only, and say so. If neither covers a week, write "no data" for it.
- The pass or fail of the PoC is the user's decision. Report each criterion as met, not met or not measured against its pass threshold, and the purpose as a question the results answer or do not answer; do not declare the PoC passed.
- Do not recommend a service size, a tier or a price. For sizing inputs, point to the `poc-sizing-stats` skill.
- Before the first query, ask whether a load test or another measured run is going on now. If it is, wait until it ends: these queries read up to 30 days of logs on every replica and would add load to the measurement.
- Reading system tables wakes an idled service and keeps it awake. Read `reference/checks-cloud-service.md` for this and for services in a warehouse.
- The reference files can name queries that this skill does not list. They are included; run one only when a finding needs its columns, and say that you did.
- To confirm a finding, you may write further read-only queries on system tables. Filter on `event_date` and a time range, add `LIMIT`, and do not read message text such as `exception` or `query` beyond what the listed queries already return. Show each query you wrote in the evidence section and mark it as yours.
- Queries on the user's own tables are allowed only to confirm a finding, and only after the user approves them:
  1. Write every query you plan for this investigation first. For each, give the SQL, what it confirms, and the estimate from `EXPLAIN ESTIMATE <query>` (rows and marks it would read). Ask the user to approve the set, and run nothing on user tables until they do. A query outside the approved set needs approval again.
  2. Return aggregates (counts, sums, whether two results match), not rows. Do not output values of user columns such as IDs, names or free text; database, table and column names are fine.
  3. Add `LIMIT` and `SETTINGS log_comment = 'poc-assistant', max_execution_time = 60`. The listed queries leave out queries with this `log_comment`, so they are not counted as workload. If the connection cannot change settings, run only queries whose estimate is under 100 million rows, without the `SETTINGS` clause, and say that they had no time limit and are counted in the workload numbers (the row limit is this assistant's safety limit, not a ClickHouse rule). If `EXPLAIN ESTIMATE` cannot run, do not query user tables.
  4. Do not run them while a load test is running. They wake an idled service, like any query.

  If the user does not approve, or the connection cannot read the table, stay with system tables and say what could not be checked.
- The queries leave out this connection's own reads of system tables, but keep every other query of the same database user. Queries on user tables that carry `log_comment = 'poc-assistant'` are left out; any other query on user tables over this connection is counted.
- Do not output user names or e-mail addresses. Do not quote literal values from query text.
- When you state how ClickHouse behaves (not a number from a query), cite a URL from the `reference/` files or confirm it with the documentation search tool and attach the URL. The URLs in the `reference/` files have been checked; cite them as they are.
- Answer in the user's language (Japanese if the user writes in Japanese).

## Steps

1. Read the plan file. Ask for the period to summarize (default: the PoC period up to today) and whether this is a weekly or a final summary.
2. Read and run these files with `30 /*days*/` replaced by the number of days in the period (at most 30). The paths are exact; do not guess other names. If a query fails because settings cannot be changed, remove the final `SETTINGS skip_unavailable_shards = 1` line and run it again.
   - `queries/02_tables.sql` (data volume and compression)
   - `queries/06_query_patterns.sql` (the heaviest query patterns)
   - `queries/progress/26_errors_by_code.sql`
   - `queries/progress/27_background_health.sql`
3. For each success criterion, measure it per week (`toMonday(event_date)`) over the period, within its scope:
   - `Measured by: system tables` (or no such line; if the line is in another language, read its meaning and say how you read it): write one read-only query against system tables and run it.
   - `user tables, with approval`: follow the rule for queries on the user's own tables.
   - `user`: use the dated lines in `## Results`.
   Fill weeks that system tables no longer cover from `## Results`.
4. Look for open risks only in what the results show, and judge each with the matching check in `reference/checks-errors-and-background.md`, `reference/checks-inserts-and-parts.md` or `reference/checks-reads-and-queries.md`. Keep at most five, each with a rule or URL.
5. Write the summary below.

## Summary format

- **Summary**: three to five sentences: what the PoC set out to decide, how many criteria were met, not met or not measured, and the one or two things that matter most for the decision.
- **Criteria**: a table with one row per criterion: metric, pass threshold, result over the period, met / not met / not measured, the trend by week, and the evidence (a query in the evidence section or a dated `## Results` line).
- **What changed during the PoC**: the decisions and changes in `## Log`, and what the results showed before and after them. Use only dated entries.
- **Open risks**: at most five, each with the number that shows it, the rule or URL, and how to verify or fix it.
- **Next steps**: at most five, each tied to a criterion or a risk. Include production readiness work the plan names (for example sizing with `poc-sizing-stats`, monitoring, backups) only when the plan or the results raise it.
- **Evidence**: every query you wrote, labelled with the criterion or risk it supports, and the listed queries you ran.
