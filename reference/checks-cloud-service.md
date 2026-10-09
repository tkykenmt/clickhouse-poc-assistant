# Checks: the Cloud service itself

These are rules about the service and about how the skills read it. The URLs have been checked; cite them as they are.

## Reading system tables keeps the service awake

- **Rule**: querying system tables wakes an idled service and keeps it from idling, which can affect cost. Run the skills when the user asks, not continuously; for continuous monitoring point to the Cloud console or the Prometheus endpoint.
- **Source**: https://clickhouse.com/docs/products/cloud/features/monitoring/system-tables

## Services in a warehouse

- **Rule**: `clusterAllReplicas('default', …)` covers only the current service. In a warehouse with several services, `all_groups.default` covers all of them; merges and inserts run by another read-write service of the warehouse are not visible with `default`. If the user says the service is part of a warehouse, say which scope the results cover.
- **Source**: https://clickhouse.com/docs/products/cloud/features/infrastructure/warehouses

## Why the service does not idle

- **Columns**: `active_parts` (`queries/advisor/10_table_layout.sql`), running merges (`queries/progress/27_background_health.sql`), query counts by hour (`queries/07_query_load_hourly.sql`).
- **Rule**: the service is not idled while the number of active parts exceeds the threshold (default 10,000) or while merges are running. Queries from anywhere keep it awake; the default IP access list allows any address, so restricting it is recommended.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/idling

## How far back the evidence goes

- **Rule**: system table data is kept for 30 days (and copied to new replicas when they replace old ones). Findings older than that cannot be checked; say so when the user asks about an earlier period.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/make-before-break

## Usage limits

- **Rule**: ClickHouse Cloud enforces soft limits on the number of tables, databases, views, dictionaries and other objects. Read the service's own values with `SELECT name, value FROM system.server_settings WHERE name LIKE 'max_%_num_to_warn' OR name LIKE 'max_%_num_to_throw'` and compare with the counts; do not quote a default.
- **Source**: https://clickhouse.com/docs/products/cloud/guides/best-practices/usagelimits

## ClickPipes

- **Rule**: ClickPipes latency, errors and replica CPU are not in the service's system tables; they are in the Prometheus endpoint (for example `ClickPipes_Latency`) and the console. Point the user there instead of guessing.
- **Source**: https://clickhouse.com/docs/integrations/clickpipes/monitoring
