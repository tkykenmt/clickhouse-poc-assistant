-- Ingest per day and table, from new parts written by INSERTs.
SELECT
    event_date AS day,
    database,
    table,
    count() AS new_parts,
    sum(rows) AS rows,
    sum(bytes_uncompressed) AS uncompressed_bytes,
    sum(size_in_bytes) AS compressed_bytes
FROM clusterAllReplicas('default', merge('system', '^part_log'))
WHERE event_type = 'NewPart'
  AND event_date >= today() - 30 /*days*/
  AND database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
GROUP BY day, database, table
ORDER BY day, database, table
SETTINGS skip_unavailable_shards = 1
