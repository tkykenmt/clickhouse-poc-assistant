-- Table layout: engine, keys, part counts and sizes, partitions. Basis for schema advice.
SELECT
    t.database AS database,
    t.name AS table,
    t.engine AS engine,
    t.partition_key AS partition_key,
    t.sorting_key AS sorting_key,
    t.primary_key AS primary_key,
    t.total_rows AS total_rows,
    t.total_bytes AS total_bytes,
    p.active_parts AS active_parts,
    p.partitions AS partitions,
    p.max_parts_in_partition AS max_parts_in_partition,
    p.median_part_rows AS median_part_rows,
    p.small_parts AS parts_under_1m_rows
FROM system.tables AS t
LEFT JOIN
(
    SELECT
        database, table,
        count() AS active_parts,
        uniqExact(partition) AS partitions,
        max(parts_per_partition) AS max_parts_in_partition,
        round(median(rows)) AS median_part_rows,
        countIf(rows < 1000000) AS small_parts
    FROM
    (
        SELECT database, table, partition, rows, count() OVER (PARTITION BY database, table, partition) AS parts_per_partition
        FROM system.parts
        WHERE active
    )
    GROUP BY database, table
) AS p ON p.database = t.database AND p.table = t.name
WHERE t.database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
  AND t.is_temporary = 0
ORDER BY t.total_bytes DESC NULLS LAST
LIMIT 200
