# Checks: the Cloud service itself

These are rules about the service and about how the skills read it. The URLs have been checked; cite them as they are.

## Reading system tables keeps the service awake

- **Rule**: querying system tables wakes an idled service and keeps it from idling, which can affect cost. Run the skills when the user asks, not continuously; for continuous monitoring point to the Cloud console or the Prometheus endpoint.
- **Source**: https://clickhouse.com/docs/products/cloud/features/monitoring/system-tables

## Services in a warehouse

- **Rule**: `clusterAllReplicas('default', …)` covers only the current service. In a warehouse with several services, `all_groups.default` covers all of them; merges and inserts run by another read-write service of the warehouse are not visible with `default`. If the user says the service is part of a warehouse, say which scope the results cover.
- **Source**: https://clickhouse.com/docs/products/cloud/features/infrastructure/warehouses

## Why the service does not idle

- **Columns**: rows with `check` = `active parts on replica` (`queries/advisor/13_service_objects.sql`), `active_parts` (`queries/advisor/10_table_layout.sql`), running merges (`queries/progress/27_background_health.sql`), query counts by hour (`queries/07_query_load_hourly.sql`).
- **Rule**: the service is not idled while the number of active parts exceeds the threshold (default 10,000) or while merges are running. The documentation does not say which databases' parts count; this assistant compares the replica total from `13`, which includes the `system` database, to be conservative, and says so. Queries from anywhere keep it awake; the default IP access list allows any address, so restricting it is recommended.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/idling

## Did something stop while the service was idle?

- **Columns**: `uptime_seconds` (`queries/01_service.sql`), rows with `check` = `refreshable view failing` (`queries/progress/27_background_health.sql`), `queries` by hour (`queries/07_query_load_hourly.sql`).
- **Rule**: while idle, the service can suspend refreshes of refreshable materialized views, consumption from S3Queue and the scheduling of new merges; merges already running finish first. To keep them running, disable idling. Connections can time out while the service is paused, so a client's first query after a quiet period can fail; the client must tolerate the wake-up delay and retry, and the documentation recommends testing its timeout and retry behaviour against an idle service. The system tables do not record idling itself: when hours with no queries line up with a view that stopped refreshing, S3Queue lag or a connect timeout reported by the user, say that idling is the likely cause and that it is inferred.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/idling

## How far back the evidence goes

- **Rule**: system table data is kept for 30 days (and copied to new replicas when they replace old ones). Findings older than that cannot be checked; say so when the user asks about an earlier period.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/make-before-break

## Usage limits

- **Columns**: rows with `check` = `databases` and `tables` (`queries/advisor/13_service_objects.sql`).
- **Rule**: ClickHouse Cloud enforces soft limits on the number of tables, databases, views, dictionaries and other objects; the documentation lists default values (for example 1000 databases, 5000 tables, and views and dictionaries counted separately), and the service's own values below take precedence. One database or table per tenant does not scale to thousands of tenants; the multi-tenancy guide describes the alternatives. Read the service's own values with `SELECT name, value FROM system.server_settings WHERE name LIKE 'max_%_num_to_warn' OR name LIKE 'max_%_num_to_throw'` and compare with the counts; quote the documented default only when the service's value is not available.
- **Source**: https://clickhouse.com/docs/products/cloud/guides/best-practices/usagelimits , https://clickhouse.com/docs/products/cloud/guides/best-practices/multitenancy

## ClickPipes

- **Rule**: ClickPipes latency, errors and replica CPU are not in the service's system tables; they are in the Prometheus endpoint (for example `ClickPipes_Latency`) and the console. Point the user there instead of guessing.
- **Source**: https://clickhouse.com/docs/integrations/clickpipes/monitoring

## Did the server version change during the PoC?

- **Columns**: rows with `check` = `server revision seen` (the server's build revision: it changes with many releases but is not unique per version) (`queries/advisor/13_service_objects.sql`), `version` per replica (`queries/01_service.sql`).
- **Rule**: more than one revision in the period means the server was upgraded or rebuilt during the PoC; results measured before and after are not directly comparable. One revision does not prove there was no upgrade; give the current `version` from `01`. ClickHouse Cloud has release channels; agree on the channel at the start of the PoC, and note that moving to a slower channel does not downgrade the service.
- **Source**: https://clickhouse.com/docs/products/cloud/features/admin-features/upgrades , ClickHouse source: https://github.com/ClickHouse/ClickHouse/blob/master/cmake/autogenerated_versions.txt (`VERSION_REVISION`)

## Kafka engine tables on ClickHouse Cloud

- **Columns**: rows with `check` = `kafka engine table` (`queries/advisor/13_service_objects.sql`).
- **Rule**: on ClickHouse Cloud the documentation recommends ClickPipes instead of the Kafka table engine; ClickPipes supports private network connections and scales ingestion separately from the service.
- **Source**: https://clickhouse.com/docs/integrations/connectors/data-ingestion/kafka/kafka-table-engine
