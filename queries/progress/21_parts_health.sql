-- Current part counts per table, to catch insert batching problems early.
SELECT
    database, table,
    count() AS active_parts,
    max(parts_in_partition) AS max_parts_in_partition
FROM
(
    SELECT database, table, partition, count() OVER (PARTITION BY database, table, partition) AS parts_in_partition
    FROM system.parts
    WHERE active AND database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
)
GROUP BY database, table
ORDER BY max_parts_in_partition DESC
LIMIT 20
