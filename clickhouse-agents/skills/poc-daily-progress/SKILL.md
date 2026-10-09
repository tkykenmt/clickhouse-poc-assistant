---
name: poc-daily-progress
description: Writes the daily PoC progress note for this ClickHouse service - what changed in the last 24 hours, where each success criterion stands, new table and query advice limited to what changed, and the next actions - using the PoC plan file attached to the agent. Use for the scheduled daily run, or when the user asks for PoC progress, "進捗", "日次のまとめ" or "ネクストアクション".
always-apply: false
user-invocable: true
---

# PoC daily progress

You write a short daily note on a ClickHouse Cloud PoC. You read **system tables only**; never select rows from the user's own tables.

## Input: the PoC plan file

The PoC plan is a file attached to this agent as file context, named like `poc-plan*.md`. Find it with the file search tool and read these sections:

- `## Target` (or `## 対象`): the service, the PoC period and the start date
- `## Success criteria` (or `## 成功基準`): one item per criterion - the metric, the pass line and how to measure it
- `## Log` (or `## 経緯`), if present: earlier decisions and open next actions

If the file or either required section is missing, say which section is missing, list the required sections above, and stop. Nothing is written back to the file: compare with the previous day by querying system tables again, not by remembering.

## Rules

- Every number comes from a query result in this conversation. Show the SQL you wrote for a criterion.
- Do not recommend a service size, a tier or a price. Do not output user names or e-mail addresses.
- When you state how ClickHouse behaves (not a number from a query), confirm it with the documentation search tool and attach the URL.
- Answer in the user's language (Japanese if the user writes in Japanese). Keep the note under 40 lines.

## Steps

1. Read and run these files. The paths are exact; do not guess other names.
   - `queries/progress/20_daily_digest.sql`
   - `queries/progress/21_parts_health.sql`
   - `queries/progress/22_new_query_patterns.sql`
   - `queries/progress/23_changed_query_patterns.sql`
   - `queries/progress/24_table_changes.sql`
   - `queries/progress/25_insert_shape_change.sql`

   If a query fails because settings cannot be changed, remove the final `SETTINGS skip_unavailable_shards = 1` line and run it again.
2. For each success criterion, write one read-only query against system tables that measures it for the last 24 hours and for the 7 days before, run it, and compare both with the pass line. If a criterion cannot be measured from system tables, say so.
3. Find what is new or changed. Look only at these, so advice is not repeated on days when nothing changed:
   - new SELECT patterns from `22` that are among the heaviest (by `total_cpu_seconds`) or read most of their tables (`marks_read_ratio`)
   - patterns from `23` whose `p99_ratio` or `read_rows_ratio` is 2 or more with at least 10 executions in the last 24 hours (this is a reporting threshold for change, not a ClickHouse recommendation)
   - tables from `24` that were created or altered
   - tables from `25` whose `p50_rows_per_insert_24h` fell to half or less of the 7-day value, and tables from `21` whose `max_parts_in_partition` stands out
   For each of these, check the matching rule in the `clickhouse-best-practices` skill (and `clickhouse-architecture-advisor` for pattern choices) and the documentation search tool. Keep at most three findings that a rule or a documentation page supports; drop the rest. `sample_query` contains literal values: quote column names, JSON keys and functions, not literal values.
4. Write the note:
   - **Last 24 hours**: ingest and query volume against the previous 7-day average, p99 latency, errors, the table with the most parts in one partition. Mention only what changed notably.
   - **Success criteria**: one line each - value in the last 24 hours, value over the 7 days before, pass line, met / not met / not measurable.
   - **New advice**: at most three findings from step 3. For each: target (table or query_hash), what changed with the numbers, candidate, rule name or documentation URL, and how to verify. If there is nothing, write a single line saying there is no new finding.
   - **Next actions**: at most three, each tied to a criterion, an observation or a finding above.
