-- Storage per table: rows, compressed and uncompressed bytes, parts and partitions.
-- Note: compact parts (small, recently written) can report 0 compressed bytes until they are merged into wide parts.
SELECT
    p.database AS database,
    p.table AS table,
    any(t.engine) AS engine,
    any(t.partition_key) AS partition_key,
    any(t.sorting_key) AS sorting_key,
    count() AS active_parts,
    uniqExact(p.partition) AS partitions,
    nullIf(min(p.min_time), toDateTime(0)) AS data_min_time,  -- NULL unless the partition key is time-based
    nullIf(max(p.max_time), toDateTime(0)) AS data_max_time,
    sum(p.rows) AS rows,
    sum(p.data_compressed_bytes) AS compressed_bytes,
    sum(p.data_uncompressed_bytes) AS uncompressed_bytes,
    round(sum(p.data_uncompressed_bytes) / nullIf(sum(p.data_compressed_bytes), 0), 2) AS compression_ratio,
    sum(p.primary_key_bytes_in_memory) AS primary_key_bytes_in_memory
FROM system.parts AS p
LEFT JOIN system.tables AS t ON p.database = t.database AND p.table = t.name
WHERE p.active AND p.database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
GROUP BY p.database, p.table
ORDER BY compressed_bytes DESC
