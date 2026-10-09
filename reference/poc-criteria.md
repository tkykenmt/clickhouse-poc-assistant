# PoC evaluation areas from public ClickHouse sources

Each area lists what to measure and where the idea comes from. Every source is a public page on clickhouse.com.
Pass lines are always the user's numbers; this file gives none.

## Principle: test with your own data and queries

- Measure with data and queries that represent the real workload, under the same conditions as production, not with the simplest query possible.
  - Attentive: replayed production traffic for inserts and used mock datasets for queries. https://clickhouse.com/blog/confoundingly-fast-inside-attentives-migration-to-clickhouse
  - Mercado Libre: benchmark the same workload under the same conditions; index design is iterative; tune batch size for your own volume. https://clickhouse.com/blog/mercado-libre-observability-on-clickhouse-cloud
  - m3ter: a fixed set of data and queries representing the real workload, with minimum targets defined per criterion. https://clickhouse.com/blog/why-m3ter-clickhouse-cloud

## Areas

| Area | What to measure | How to measure on ClickHouse Cloud | Sources |
|---|---|---|---|
| Data volume and storage | stored bytes compressed and uncompressed, compression ratio, rows | `system.parts` (query `02_tables`) | m3ter (store large volumes); https://clickhouse.com/docs/products/cloud/features/monitoring/system-tables |
| Ingest throughput | rows and bytes per second or per day at the target rate; insert latency | `system.part_log` NewPart, `system.query_log` Insert (queries `04`, `05`, `07`) | m3ter (sustain high ingest); Attentive (replay production traffic); https://clickhouse.com/docs/concepts/features/operations/insert/bulkinserts ; https://clickhouse.com/docs/concepts/features/operations/insert/asyncinserts |
| Data freshness | delay from event time to queryable | the user's own tables (newest event time against now); not visible from system tables alone | m3ter (ease of data ingest); Mercado Libre (batching) |
| Query latency | p50, p90, p99 per query type | `system.query_log` grouped by `normalized_query_hash` or `log_comment` (query `06`) | Insider One (tracks p50, p75, p90, p99) https://clickhouse.com/blog/insiderone-customer-data-platform ; https://clickhouse.com/docs/reference/system-tables/query_log |
| Concurrency | latency and errors as concurrent queries rise; sustained queries per second | `clickhouse-benchmark` with increasing `--concurrency`; `system.query_log` per second (query `07`) | trip.com (query templates, clickhouse-benchmark, p50 to p9999) https://clickhouse.com/blog/how-trip.com-migrated-from-elasticsearch-and-built-a-50pb-logging-solution-with-clickhouse ; Adevinta (QPS with a response-time SLA) https://clickhouse.com/blog/serving-real-time-analytics-across-marketplaces-at-adevinta ; https://clickhouse.com/docs/concepts/features/tools-and-utilities/clickhouse-benchmark |
| Deduplication and updates | duplicates removed as expected; update and delete behaviour and cost | user's tables; `system.mutations`, `system.query_log` | m3ter (eliminate duplicate data, data deletion); https://clickhouse.com/docs/concepts/features/operations/update/replacing-merge-tree ; https://clickhouse.com/docs/reference/statements/delete |
| Bulk export | time to export the needed data | `system.query_log` for the export queries | m3ter (bulk data export) |
| Scaling | behaviour while scaling up or out; no downtime | Cloud console scaling settings and activity; `system.query_log` errors during the change | m3ter (scalable with zero downtime); https://clickhouse.com/docs/products/cloud/features/autoscaling/overview |
| Availability and recovery | backup and restore time; replica failure handling | Cloud console backups; restore to a new service | m3ter (HA and DR); https://clickhouse.com/docs/products/cloud/features/backups/overview |
| Monitoring | the team can see query and resource metrics it needs | `system.query_log`, `system.metric_log`, Cloud console dashboards | m3ter (monitor high-level and low-level performance; query_log); Mercado Libre (monitor clusters with system tables) |
| Cost | usage stays within the user's budget for the measured workload | Cloud console Usage Breakdown (CSV); https://clickhouse.com/pricing | m3ter (overall cost of solution) |

## Migration

If the PoC replaces another system, follow the official migration guide for that source to plan schema, data load and query translation: https://clickhouse.com/docs/get-started/migrate/overview
