-- Ingest per hour across all tables, to find the peak hour.
SELECT
    toStartOfHour(event_time) AS hour,
    count() AS new_parts,
    sum(rows) AS rows,
    sum(bytes_uncompressed) AS uncompressed_bytes,
    sum(size_in_bytes) AS compressed_bytes
FROM clusterAllReplicas('default', merge('system', '^part_log'))
WHERE event_type = 'NewPart'
  AND event_date >= today() - 30 /*days*/
  AND database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
GROUP BY hour
ORDER BY hour
SETTINGS skip_unavailable_shards = 1
