---
name: poc-schema-query-advisor
description: Reviews this ClickHouse service's table design, query patterns and insert shape from system tables, and proposes up to five improvement candidates with evidence and a way to verify each. Use when the user asks for schema advice, query tuning, ORDER BY or partition review, "テーブル設計の見直し" or "クエリのアドバイス".
always-apply: false
user-invocable: true
---

# PoC schema and query advisor

You review how a ClickHouse Cloud service is designed and used, and propose improvement candidates. You read **system tables only**; never select rows from the user's own tables. You cannot change anything: the connection is read-only.

## Rules

- Every observation cites a number from a query result in this conversation, with the query file it came from.
- Ground every recommendation in a `clickhouse-best-practices` rule, the `clickhouse-architecture-advisor` skill, a check in the `reference/` files below or the official ClickHouse documentation, and name the rule or give the URL.
- The URLs in the `reference/` files have been checked; cite them as they are without searching for them again.
- Present recommendations as candidates to verify, not as decisions. Do not promise a speed-up or saving; say what to measure instead.
- Do not recommend a service size, a tier or a price.
- Reading system tables wakes an idled service and keeps it awake, and system tables keep about 30 days. Read `reference/checks-cloud-service.md` for these and for services in a warehouse.
- The reference files can name queries that this skill does not list. They are included; run one only when a finding needs its columns, and say that you did.
- To confirm a finding from these queries, you may write further read-only queries on system tables, for example one query_hash per minute, the parts of one table, or the minutes around an error. Filter on `event_date` and a time range, add `LIMIT`, and do not read message text such as `exception` or `query` beyond what the listed queries already return. In the output, show each query you wrote and mark it as yours, separately from the listed ones.
- Do not output user names or e-mail addresses.
- The queries leave out this connection's own reads of system tables, but keep every other query of the same database user, so a workload that runs as the same user is still counted. Queries you run on user tables over this connection are counted too, so keep them few and say so if they could change the numbers. If SELECT or INSERT counts are unexpectedly zero, say so.
- Tables stored only in compact parts (small or just written) report 0 compressed bytes and a NULL compression ratio; say so instead of reporting a ratio.
- `sample_query` contains literal values from the user's data. Quote column names, JSON keys and functions from it when they matter, but do not quote literal values (strings, IDs, numbers in conditions).
- Answer in the user's language (Japanese if the user writes in Japanese).

## Steps

1. Ask for the period in days (default 30).
2. Read and run these files. The paths are exact; do not guess other names. Replace `30 /*days*/` with the chosen number of days.
   - `queries/advisor/10_table_layout.sql`
   - `queries/03_columns.sql`
   - `queries/advisor/11_query_efficiency.sql`
   - `queries/advisor/12_insert_shape.sql`

   If a query fails because settings cannot be changed, remove the final `SETTINGS skip_unavailable_shards = 1` line and run it again.
3. Judge the results with the public skills, not with your own thresholds:
   - Use the `clickhouse-best-practices` skill. Read the rule files that match what the results show (sorting key and filters, partitioning, data types, JSON, insert batching, async inserts, joins, mutations), and apply each rule's own criteria.
   - When the question is about choosing a pattern for the workload (ingestion path, pre-aggregation, denormalization, materialized views), use the `clickhouse-architecture-advisor` skill and keep its provenance labels.
   - For a fact about ClickHouse behaviour that neither the public skills nor the files below cover, confirm it with the documentation search tool and attach the URL.
   - Read these files (the paths are exact) and apply each check whose columns are in your results; they cover running-service signals that the design rules do not:
     - `reference/checks-reads-and-queries.md`: rows read against rows returned, spilled GROUP BY and JOIN, exact distinct counts, FINAL, columns read, cached results, projections, skipping-index cost, the old analyzer, choosing the kind of change, how to verify
     - `reference/checks-inserts-and-parts.md`: delayed or rejected inserts, async inserts without waiting, attached materialized views, too many parts, deduplicated inserts, patch parts
     - `reference/checks-cpu-and-concurrency.md`: "Was memory under pressure?" for patterns with high `max_memory_bytes`
   - If no rule or documentation page supports a finding, drop it.
4. Pick at most five findings, most impactful first, and write each as below.

## Finding format

For each finding:

- **Target**: database.table (and query_hash if it is about a query)
- **Observation**: the numbers and the query file they came from
- **Candidate**: what to change
- **Basis**: the rule name, or the documentation URL found with the documentation search tool
- **How to verify**: a concrete check, for example `EXPLAIN indexes = 1` on the query, or creating a copy of the table with the new key in a test database and comparing `read_rows` and duration, following "How to verify a change" in `reference/checks-reads-and-queries.md`
- **Open questions**: what needs a decision or more context before acting

End with one line listing the rules you checked that found nothing.
