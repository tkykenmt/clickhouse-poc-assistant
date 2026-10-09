-- Failed queries by error code and query pattern. Contains no error message text (messages can hold literal values).
SELECT
    errorCodeToName(exception_code) AS error,
    exception_code,
    query_kind,
    toString(normalized_query_hash) AS query_hash,
    arrayStringConcat(any(tables), ' ') AS query_tables,
    count() AS failures,
    min(event_time) AS first_seen,
    max(event_time) AS last_seen
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')
  AND is_initial_query
  AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay (failures before start have no tables and stay)
           AND notEmpty(tables) AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                           OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND log_comment != 'poc-assistant'  -- queries the assistant ran on user tables with the user's approval
  AND event_date >= today() - 30 /*days*/
GROUP BY error, exception_code, query_kind, query_hash
ORDER BY failures DESC
LIMIT 50
SETTINGS skip_unavailable_shards = 1
