-- Service-wide objects and events that PoCs often trip over: active parts on each replica (all databases, including
-- system, as the idling threshold counts them), object counts against usage limits, Kafka engine tables, rollup tables,
-- tables whose columns are mostly Nullable, server revisions seen in the period, deletes and updates, and long or failed
-- INSERT ... SELECT, dictionaries that are empty or failed to load, and memory held now by merges, dictionaries,
-- in-memory tables and primary keys (a snapshot, in bytes). One row per finding: check, object, value, detail.
-- No message or query text.
SELECT check, object, value, detail
FROM
(
    SELECT 'active parts on replica' AS check, hostName() AS object, toFloat64(count()) AS value,
           concat('system database: ', toString(countIf(database = 'system'))) AS detail
    FROM clusterAllReplicas('default', system.parts)
    WHERE active
    GROUP BY object

    UNION ALL

    SELECT 'databases' AS check, '' AS object, toFloat64(count()) AS value, '' AS detail
    FROM system.databases
    WHERE name NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')

    UNION ALL

    SELECT 'tables' AS check, '' AS object, toFloat64(countIf(engine NOT IN ('View', 'MaterializedView', 'LiveView', 'WindowView', 'Dictionary'))) AS value,
           concat('views: ', toString(countIf(engine IN ('View', 'MaterializedView', 'LiveView', 'WindowView'))),
                  ' dictionaries: ', toString(countIf(engine = 'Dictionary'))) AS detail
    FROM system.tables
    WHERE database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema') AND NOT is_temporary

    UNION ALL

    SELECT 'kafka engine table' AS check, concat(database, '.', name) AS object, 1 AS value, engine AS detail
    FROM system.tables
    WHERE engine = 'Kafka'

    UNION ALL

    SELECT 'rollup table' AS check, concat(database, '.', name) AS object, toFloat64(total_rows) AS value,
           concat(engine, ' sorting_key=', sorting_key) AS detail
    FROM system.tables
    WHERE engine LIKE '%SummingMergeTree' OR engine LIKE '%AggregatingMergeTree'

    UNION ALL

    SELECT 'mostly nullable table' AS check, concat(database, '.', table) AS object,
           round(countIf(type LIKE '%Nullable(%') / count(), 2) AS value,
           concat(toString(countIf(type LIKE '%Nullable(%')), ' of ', toString(count()), ' columns') AS detail
    FROM system.columns
    WHERE database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
    GROUP BY database, table
    HAVING countIf(type LIKE '%Nullable(%') / count() > 0.5 AND count() >= 4

    UNION ALL

    SELECT 'server revision seen' AS check, toString(revision) AS object, toFloat64(count()) AS value,
           concat('first=', toString(min(event_time)), ' last=', toString(max(event_time))) AS detail
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE event_date >= today() - 30 /*days*/ AND type = 'QueryFinish'
    GROUP BY object

    UNION ALL

    SELECT 'deletes and updates' AS check, query_kind AS object, toFloat64(count()) AS value,
           concat('tables: ', toString(length(arrayDistinct(groupArrayArray(tables))))) AS detail
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE event_date >= today() - 30 /*days*/ AND type = 'QueryFinish' AND is_initial_query
      AND (query_kind IN ('Delete', 'Update') OR (query_kind = 'Alter' AND match(query, '(?is)^\\s*ALTER\\s+TABLE\\s+\\S+(\\s+ON\\s+CLUSTER\\s+\\S+)?\\s+(UPDATE|DELETE)\\b')))
      AND user NOT LIKE '%-internal'
      AND log_comment != 'poc-assistant'
    GROUP BY query_kind

    UNION ALL

    SELECT 'insert select' AS check, '' AS object, toFloat64(count()) AS value,
           concat('max_duration_s=', toString(round(max(query_duration_ms) / 1e3)),
                  ' failed=', toString(countIf(type != 'QueryFinish')),
                  ' memory_limit=', toString(countIf(exception_code = 241)),
                  ' too_many_parts=', toString(countIf(exception_code = 252))) AS detail
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE event_date >= today() - 30 /*days*/ AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
      AND is_initial_query AND query_kind = 'Insert' AND positionCaseInsensitive(query, 'SELECT') > 0
      AND user NOT LIKE '%-internal'
      AND log_comment != 'poc-assistant'
    HAVING count() > 0

    UNION ALL

    -- NOT_LOADED is normal: dictionaries load on first use.
    SELECT 'dictionary empty or failed' AS check, concat(database, '.', name, ' on ', hostName()) AS object,
           toFloat64(element_count) AS value, concat('status=', toString(status)) AS detail
    FROM clusterAllReplicas('default', system.dictionaries)
    -- Direct and cache layouts hold no elements by design.
    WHERE status IN ('FAILED', 'FAILED_AND_RELOADING')
       OR (status IN ('LOADED', 'LOADED_AND_RELOADING') AND element_count = 0
           AND type NOT IN ('Direct', 'ComplexKeyDirect', 'Cache', 'ComplexKeyCache', 'SSDCache', 'SSDComplexKeyCache'))

    UNION ALL

    SELECT 'memory held' AS check, concat(kind, ' on ', host) AS object, toFloat64(bytes) AS value, '' AS detail
    FROM
    (
        SELECT 'merges' AS kind, hostName() AS host, sum(memory_usage) AS bytes
        FROM clusterAllReplicas('default', system.merges) GROUP BY host
        UNION ALL
        SELECT 'dictionaries' AS kind, hostName() AS host, sum(bytes_allocated) AS bytes
        FROM clusterAllReplicas('default', system.dictionaries) GROUP BY host
        UNION ALL
        SELECT 'Memory, Set and Join tables' AS kind, hostName() AS host, sum(ifNull(total_bytes, 0)) AS bytes
        FROM clusterAllReplicas('default', system.tables) WHERE engine IN ('Memory', 'Set', 'Join') GROUP BY host
        UNION ALL
        SELECT 'primary keys' AS kind, hostName() AS host, sum(primary_key_bytes_in_memory) AS bytes
        FROM clusterAllReplicas('default', system.parts) WHERE active GROUP BY host
    )
    WHERE bytes > 0
)
ORDER BY check, value DESC
LIMIT 50 BY check
SETTINGS skip_unavailable_shards = 1
