---
name: poc-sizing-stats
description: Collects sizing statistics for a ClickHouse PoC from this service's system tables (storage, compression, ingest volume and peaks, query load and per-query cost) and writes a short summary plus CSV-ready tables the user can share with whoever sizes the service. Use when the user asks for sizing statistics, a PoC sizing export, or "サイジング用の統計".
always-apply: false
user-invocable: true
---

# PoC sizing statistics

You collect statistics used to size a production service. You read **system tables only**. Never select rows from the user's own tables.

## Rules

- Every number you report comes from a query result in this conversation. Do not estimate, extrapolate or round beyond what is shown. If a query fails, say which one and why; do not fill the gap.
- Do not output query text (the `query` column) unless the user explicitly asks for it. Query patterns are identified by `query_hash` (normalized_query_hash as a string, so no digits are lost).
- Do not recommend a service size, a tier or a price. You only provide the measured inputs.
- When you state how ClickHouse behaves (not a number from a query), confirm it with the documentation search tool and attach the URL.
- Answer in the user's language (Japanese if the user writes in Japanese).
- The queries already exclude ClickHouse Cloud's own monitoring users (names ending in `-internal`) and your own connection. Do not add them back.
- Do not output user names or e-mail addresses. Report counts of users only.
- If a result is too long to read in one tool response, aggregate it with a follow-up query instead of reading it row by row.

## Steps

1. Ask for the period in days (default 30). System tables keep at most about 30 days, so a longer period returns only what exists.
2. Read and run these files in this order. The paths are exact; do not guess other names, and do not write your own replacement queries.
   - `queries/01_service.sql`
   - `queries/02_tables.sql`
   - `queries/03_columns.sql`
   - `queries/04_ingest_daily.sql`
   - `queries/05_ingest_hourly.sql`
   - `queries/06_query_patterns.sql`
   - `queries/07_query_load_hourly.sql`
   - `queries/08_resources_hourly.sql`

   Before running, replace `30 /*days*/` with the chosen number of days. Run each file's SQL exactly as written otherwise.
   - If a query fails because settings cannot be changed (read-only), remove the final `SETTINGS skip_unavailable_shards = 1` line and run it again.
   - If `02_tables` returns no user tables, tell the user the connected user cannot see table metadata and stop.
3. Write the summary in the format below.
4. Offer each result as a CSV the user can download (an artifact or a code block per query), named after the query file (for example `02_tables.csv`).

## Summary format

Heading: "Sizing statistics (last N days, collected YYYY-MM-DD)", translated into the user's language.

| Item | Value | Source |
|---|---|---|
| Replicas and limits | count, CPU cores and memory per replica | 01 |
| Stored data | total compressed and uncompressed bytes, ratio | 02 |
| Largest tables | top 5 by compressed bytes, with rows and ratio | 02 |
| Ingest per day | average and maximum rows and uncompressed bytes per day | 04 |
| Ingest peak hour | maximum rows and uncompressed bytes in one hour, with the hour | 05 |
| Queries per day | SELECT count per day, average and maximum | 07 |
| Peak queries per second | maximum of `peak_queries_per_second` for Select, with the hour | 07 |
| Heaviest query patterns | top 5 by `total_cpu_seconds`: executions, p50/p99 ms, avg CPU ms, avg read rows | 06 |
| Resource use | maximum running queries, maximum memory tracked, CPU seconds per hour (max) | 08 |

Show bytes in GiB or TiB with two decimals, and say which unit. After the table, list any query that failed or returned no rows, and nothing else.
