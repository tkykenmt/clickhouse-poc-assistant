-- Storage per column: type, codec and compression, largest first.
-- Note: columns of tables stored only in compact parts report 0 bytes; their ratio is NULL.
SELECT
    database,
    table,
    name AS column,
    type,
    compression_codec,
    is_in_sorting_key,
    data_compressed_bytes AS compressed_bytes,
    data_uncompressed_bytes AS uncompressed_bytes,
    round(data_uncompressed_bytes / nullIf(data_compressed_bytes, 0), 2) AS compression_ratio
FROM system.columns
WHERE database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
ORDER BY compressed_bytes DESC
LIMIT 2000
