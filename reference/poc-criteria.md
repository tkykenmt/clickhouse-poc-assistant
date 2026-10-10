# PoC evaluation areas from public ClickHouse sources

Each area lists what to measure and where the idea comes from. Every source is a public page on clickhouse.com.
Pass thresholds are always the user's numbers; this file gives none.

## Principle: test with your own data and queries

- Measure with data and queries that represent the real workload, under the same conditions as production, not with the simplest query possible.
  - Attentive: replayed production traffic for inserts and used mock datasets for queries. https://clickhouse.com/blog/confoundingly-fast-inside-attentives-migration-to-clickhouse
  - Mercado Libre: benchmark the same workload under the same conditions; index design is iterative; tune batch size for your own volume. https://clickhouse.com/blog/mercado-libre-observability-on-clickhouse-cloud
  - m3ter: a fixed set of data and queries representing the real workload, with minimum targets defined per criterion. https://clickhouse.com/blog/why-m3ter-clickhouse-cloud

## Areas

| Area | What to measure | How to measure on ClickHouse Cloud | Sources |
|---|---|---|---|
| Data volume and storage | stored bytes compressed and uncompressed, compression ratio, rows | `system.parts` (active parts: rows, compressed and uncompressed bytes) | m3ter (store large volumes); https://clickhouse.com/docs/products/cloud/features/monitoring/system-tables |
| Ingest throughput | rows and bytes per second or per day at the target rate; insert latency | `system.part_log` NewPart rows and bytes per day or hour; `system.query_log` Insert duration | m3ter (sustain high ingest); Attentive (replay production traffic); https://clickhouse.com/docs/concepts/features/operations/insert/bulkinserts ; https://clickhouse.com/docs/concepts/features/operations/insert/asyncinserts |
| Data freshness | delay from event time to queryable | the user's own tables: the newest event time against `now()`, run by the assistant only with the user's approval; for ClickPipes, the lag metrics in the console or the Prometheus endpoint (https://clickhouse.com/docs/integrations/clickpipes/monitoring) | m3ter (ease of data ingest); Mercado Libre (batching) |
| Query latency | p50, p90, p99 per query type | `system.query_log` finished queries grouped by `normalized_query_hash` or `log_comment` | Insider One (tracks p50, p75, p90, p99) https://clickhouse.com/blog/insiderone-customer-data-platform ; https://clickhouse.com/docs/reference/system-tables/query_log |
| Concurrency | latency and errors as concurrent queries rise; sustained queries per second | `clickhouse-benchmark` with increasing `--concurrency`; `system.query_log` queries per second | trip.com (query templates, clickhouse-benchmark, p50 to p9999) https://clickhouse.com/blog/how-trip.com-migrated-from-elasticsearch-and-built-a-50pb-logging-solution-with-clickhouse ; Adevinta (QPS with a response-time SLA) https://clickhouse.com/blog/serving-real-time-analytics-across-marketplaces-at-adevinta ; https://clickhouse.com/docs/concepts/features/tools-and-utilities/clickhouse-benchmark |
| Deduplication and updates | duplicates removed as expected; update and delete behaviour and cost | user's tables; `system.mutations`, `system.query_log` | m3ter (eliminate duplicate data, data deletion); https://clickhouse.com/docs/concepts/features/operations/update/replacing-merge-tree ; https://clickhouse.com/docs/reference/statements/delete |
| Bulk export | time to export the needed data | `system.query_log` for the export queries | m3ter (bulk data export) |
| Scaling | behaviour while scaling up or out; no downtime | Cloud console scaling settings and activity; `system.query_log` errors during the change | m3ter (scalable with zero downtime); https://clickhouse.com/docs/products/cloud/features/autoscaling/overview |
| Availability and recovery | backup and restore time; replica failure handling | Cloud console backups; restore to a new service | m3ter (HA and DR); https://clickhouse.com/docs/products/cloud/features/backups/overview |
| Monitoring | the team can see query and resource metrics it needs | `system.query_log`, `system.metric_log`, Cloud console dashboards | m3ter (monitor high-level and low-level performance; query_log); Mercado Libre (monitor clusters with system tables) |
| Cost | usage stays within the user's budget for the measured workload | Cloud console Usage Breakdown (CSV); https://clickhouse.com/pricing | m3ter (overall cost of solution) |

## Test design

Agree on these before the first measured run and record the decisions in the plan's `## Log`.

- **Representative data**: a small sample replayed or looped compresses unlike production and gives misleading results; use data with production's volume and distribution, or synthetic data generated to match it. https://clickhouse.com/blog/building-clickcannon-a-tool-for-benchmark-clickhouse
- **Server time, not client time**: `system.query_log` and `clickhouse-benchmark` report server-side time by default; `--client-side-time` adds network time. Compare the client's numbers with `query_duration_ms`, and use the `Null` output format when only execution is measured. https://clickhouse.com/docs/concepts/features/tools-and-utilities/clickhouse-benchmark , https://clickhouse.com/docs/reference/formats/Null
- **Failed runs**: a query that fails is logged as `ExceptionBeforeStart` or `ExceptionWhileProcessing`, not as `QueryFinish`; count errors per run so a failing run does not read as a fast one. https://clickhouse.com/docs/reference/system-tables/query_log
- **Medians of repeated runs, one change at a time**: compare medians of several runs after warm-up, keep the data, filters and cache state the same between compared runs, and change one thing at a time. https://clickhouse.com/blog/testing-the-performance-of-click-house , https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/isolate-query-bottlenecks
- **Tag test traffic**: set `log_comment` per test or step so results can be separated in `system.query_log`. https://clickhouse.com/docs/reference/settings/session-settings/log#log_comment
- **Server version**: agree on the release channel; an upgrade during the PoC makes earlier results not directly comparable. https://clickhouse.com/docs/products/cloud/features/admin-features/upgrades
- **Read after write**: a read right after an insert or an `ALTER` can reach a replica that has not seen it yet; check counts after the write has settled, and read the guidance before turning on sequential consistency. https://clickhouse.com/docs/products/cloud/features/infrastructure/shared-merge-tree
- **Backfills**: split large loads into batches by range or file so a failure does not restart everything; `INSERT ... SELECT` runs on one replica unless parallel inserts are enabled. https://clickhouse.com/docs/guides/clickhouse/data-modelling/backfilling , https://clickhouse.com/docs/reference/settings/session-settings/parallel
- **One large query and many replicas**: a query runs on one replica unless parallel replicas are enabled, which helps queries that read a lot and can slow small ones. https://clickhouse.com/docs/products/cloud/features/infrastructure/parallel-replicas
- **Ingest from Kafka**: on ClickHouse Cloud use ClickPipes rather than the Kafka table engine. https://clickhouse.com/docs/integrations/connectors/data-ingestion/kafka/kafka-table-engine
- **ClickPipes CDC sync interval**: it can be set to any positive value but is recommended to stay above 10 seconds. https://clickhouse.com/docs/integrations/clickpipes/postgres/controlling-sync
- **Ported queries return the same results**: outer JOINs return default values instead of NULL unless `join_use_nulls = 1`, and a CTE is re-executed at each reference; check result equivalence as a criterion when queries are ported. https://clickhouse.com/docs/concepts/best-practices/minimize-optimize-joins , https://clickhouse.com/docs/reference/statements/select/with
- **Partition and sorting keys**: choose a low-cardinality partition key for data management, and an ordering key that starts with the columns queries filter on. https://clickhouse.com/docs/concepts/best-practices/partitioning-keys , https://clickhouse.com/docs/concepts/best-practices/choosing-a-primary-key

## Migration

If the PoC replaces another system, follow the official migration guide for that source to plan schema, data load and query translation: https://clickhouse.com/docs/get-started/migrate/overview
