-- Background work that is stuck or failing: unfinished mutations, failed merges and mutations of parts,
-- failing refreshable materialized views, and the longest running merges. One row per finding, no message text.
-- In ClickHouse Cloud every node holds all mutations, so system.mutations is read without clusterAllReplicas.
SELECT check, object, detail, occurrences, first_time, last_time
FROM
(
    SELECT
        'unfinished mutation' AS check,
        concat(database, '.', table) AS object,
        concat(mutation_id, ' parts_to_do=', toString(parts_to_do),
               if(latest_fail_error_code_name != '', concat(' failing=', latest_fail_error_code_name), ''),
               if(is_killed = 1, ' killed', '')) AS detail,
        toUInt64(1) AS occurrences,
        create_time AS first_time,
        greatest(create_time, latest_fail_time) AS last_time
    FROM system.mutations
    WHERE is_done = 0

    UNION ALL

    SELECT
        if(errorCodeToName(error) = 'INSERT_WAS_DEDUPLICATED', 'deduplicated insert', concat('failed ', toString(event_type))) AS check,
        concat(database, '.', table) AS object,
        errorCodeToName(error) AS detail,
        count() AS occurrences,
        min(event_time) AS first_time,
        max(event_time) AS last_time
    FROM clusterAllReplicas('default', merge('system', '^part_log'))
    WHERE error != 0
      AND event_type IN ('NewPart', 'MergeParts', 'MutatePart', 'DownloadPart')
      AND event_date >= today() - 30 /*days*/
    GROUP BY check, object, detail

    UNION ALL

    SELECT
        'refreshable view failing' AS check,
        concat(database, '.', view) AS object,
        concat('status=', any(status), ' retry=', toString(max(retry))) AS detail,
        count() AS occurrences,
        min(ifNull(last_success_time, toDateTime(0))) AS first_time,
        max(ifNull(last_refresh_time, toDateTime(0))) AS last_time
    FROM clusterAllReplicas('default', system.view_refreshes)
    WHERE exception != ''
    GROUP BY object

    UNION ALL

    SELECT
        if(is_mutation = 1, 'running mutation of a part', 'running merge') AS check,
        concat(database, '.', table) AS object,
        concat('elapsed_s=', toString(round(elapsed)), ' progress=', toString(round(progress, 2)), ' parts=', toString(num_parts)) AS detail,
        toUInt64(1) AS occurrences,
        now() - toIntervalSecond(toUInt64(elapsed)) AS first_time,
        now() AS last_time
    FROM clusterAllReplicas('default', system.merges)
    ORDER BY elapsed DESC
    LIMIT 5
)
ORDER BY check, last_time DESC
LIMIT 100
SETTINGS skip_unavailable_shards = 1
