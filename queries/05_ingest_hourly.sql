-- Ingest per hour across all tables, to find the peak hour. Rows written by materialized views into their target
-- tables are included (data stored, not data sent by clients); see 04 for the split per table.
SELECT
    toStartOfHour(event_time) AS hour,
    count() AS new_parts,
    sum(rows) AS rows,
    sum(bytes_uncompressed) AS uncompressed_bytes,
    sum(size_in_bytes) AS compressed_bytes
FROM clusterAllReplicas('default', merge('system', '^part_log'))
WHERE event_type = 'NewPart'
  AND error = 0                               -- deduplicated retries are logged with an error
  AND NOT startsWith(partition_id, 'patch-')  -- patch parts of lightweight updates
  AND event_date >= today() - 30 /*days*/
  AND database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
GROUP BY hour
ORDER BY hour
SETTINGS skip_unavailable_shards = 1
