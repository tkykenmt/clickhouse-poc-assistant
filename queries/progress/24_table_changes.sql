-- Tables created or altered in the last 24 hours, with their layout.
SELECT
    database,
    name AS table,
    engine,
    metadata_modification_time,
    partition_key,
    sorting_key,
    total_rows,
    total_bytes
FROM system.tables
WHERE database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
  AND is_temporary = 0
  AND metadata_modification_time >= now() - INTERVAL 1 DAY
ORDER BY metadata_modification_time DESC
LIMIT 30
