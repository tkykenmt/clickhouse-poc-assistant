-- Async insert flushes that failed, per table and status. No message text.
-- Needs system.asynchronous_insert_log; if the table does not exist on the service, say so instead of reporting zero.
SELECT
    concat(database, '.', table) AS target_table,
    toString(status) AS status,
    count() AS failed_inserts,
    min(event_time) AS first_seen,
    max(event_time) AS last_seen
FROM clusterAllReplicas('default', merge('system', '^asynchronous_insert_log'))
WHERE status != 'Ok'
  AND event_date >= today() - 30 /*days*/
GROUP BY target_table, status
ORDER BY failed_inserts DESC
LIMIT 50
SETTINGS skip_unavailable_shards = 1
