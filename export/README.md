# Export sizing statistics from ClickHouse Cloud

[日本語](README.ja.md)

These queries export, as CSV, the statistics used to size a ClickHouse Cloud service and estimate its cost.

They read system tables only.
They never read rows from your own tables.
Query text is not exported by default.

## What is exported

| File | Contents | Used for |
|---|---|---|
| `01_service` | version, uptime, CPU and memory limits per replica | current configuration |
| `02_tables` | rows, compressed and uncompressed size, parts, partitions, time range of the data (when the partition key is time-based) and sorting key per table | stored volume and compression |
| `03_columns` | type, codec, compressed and uncompressed size per column (largest 2,000 columns) | compression breakdown |
| `04_ingest_daily` | rows and bytes ingested per day and table | daily ingest |
| `05_ingest_hourly` | rows and bytes ingested per hour across all tables | ingest peaks |
| `06_query_patterns` | executions, latency (p50, p90, p99), rows read, memory and CPU time per query pattern (top 100) | query cost |
| `07_query_load_hourly` | SELECT and INSERT count, peak queries per second, latency and CPU time per hour | query rate and peaks |
| `08_resources_hourly` | peak running queries and merges, memory and CPU time per hour and replica | resource use |
| `optional/09_query_patterns_with_text` (optional) | `06` plus one sample query text per pattern (first 300 characters) | what the queries do |

Query patterns are grouped by `normalized_query_hash`, so queries that differ only in literal values fall into the same pattern.
Queries that ClickHouse Cloud runs for its own monitoring (database users whose names end in `-internal`) are excluded, and so are the export user's own reads of system tables.
User names are not exported; only the number of users per pattern is.

The sample text in `09` includes literal values such as those in WHERE clauses.
Export it with `--with-query-text` only if your data-handling rules allow it.

Small tables stored only in compact parts report 0 compressed bytes (and no compression ratio) until they are merged.

## Period

The default is the last 30 days.
System table logs are kept for about 30 days at most, so older data cannot be exported.
Pick the export date so that the period covers the PoC load.

## Steps

### 1. Create a read-only database user

As an admin user, run `setup_user.sql` in the SQL console.
Replace the password.

```sql
CREATE USER IF NOT EXISTS sizing_reader IDENTIFIED BY '<password>';
GRANT SHOW DATABASES, SHOW TABLES, SHOW COLUMNS, SHOW DICTIONARIES ON *.* TO sizing_reader;
GRANT SELECT ON system.* TO sizing_reader;
GRANT REMOTE ON *.* TO sizing_reader;
GRANT CREATE TEMPORARY TABLE ON *.* TO sizing_reader;
```

Use this user only for the export. Its own reads of system tables are left out of the results; other queries of the same user are kept.

If a `SHOW` grant is missing, your tables silently drop out of the results without an error.
Check that `02_tables.csv` lists the tables you expect.

### 2. Export

Run on a machine with `bash` and `curl` (macOS or Linux).
Connect to the HTTPS endpoint (port 8443) shown under **Connect** in the Cloud console.

```bash
export CH_URL="https://<service host>:8443"
export CH_USER="sizing_reader"
read -rs CH_PASSWORD; export CH_PASSWORD   # type the password (not shown)
./export.sh                        # last 30 days
./export.sh 14                     # last 14 days
./export.sh --with-query-text      # last 30 days, with sample query text
```

This writes `sizing_export_<timestamp>.tar.gz`.
The password is passed to curl on standard input, not on the command line.
If a query fails, its error is saved as `<query>.error.txt` in the archive and the script exits with status 1.
Open the CSV files in a spreadsheet and check them before sharing.

You can also run the queries one by one in the SQL console and save each result with **•••** → **Download as CSV**.
To change the period, edit the number in `30 /*days*/` in each query.

### 3. Clean up

When you are done, drop the user.

```sql
DROP USER sizing_reader;
```

## Impact

- The queries read system tables and add load to the service. Run them when the service is quiet.
- Connecting to an idle service wakes it up.
- `clusterAllReplicas` reads every replica's logs. Replicas that do not respond are skipped (`skip_unavailable_shards = 1`).

## References

- Querying system tables on ClickHouse Cloud: https://clickhouse.com/docs/products/cloud/features/monitoring/system-tables
- `system.query_log`: https://clickhouse.com/docs/reference/system-tables/query_log
- For deeper diagnostics (incident investigation), ClickHouse also publishes clickhouse-diagnostics: https://github.com/ClickHouse/clickhouse-diagnostics
