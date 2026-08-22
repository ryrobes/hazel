WITH
activity_values AS (
    SELECT groupArray(item) AS activity
    FROM (
        SELECT CAST((
            substring(query_id, 1, 8),
            current_database,
            user,
            if(client_hostname = '', client_name, client_hostname),
            toString(address),
            lower(query_kind),
            CAST(NULL AS Nullable(String)),
            CAST(NULL AS Nullable(String)),
            query_id,
            upper(query_kind),
            left(
                replaceRegexpAll(
                    replaceRegexpAll(
                        replaceRegexpAll(query, '\\s+', ' '),
                        '''([^'']|'''')*''', '''?'''
                    ),
                    '\\b[0-9]+([.][0-9]+)?\\b', '?'
                ),
                320
            ),
            elapsed,
            elapsed,
            toUInt64(greatest(memory_usage, 0)),
            read_rows,
            read_bytes,
            written_rows,
            written_bytes,
            CAST([] AS Array(String))
        ) AS Tuple(
            pid String,
            database String,
            user String,
            application String,
            client String,
            state String,
            waitType Nullable(String),
            waitEvent Nullable(String),
            queryId String,
            queryVerb String,
            queryText String,
            querySeconds Float64,
            xactSeconds Float64,
            memoryBytes UInt64,
            readRows UInt64,
            readBytes UInt64,
            writtenRows UInt64,
            writtenBytes UInt64,
            blockedBy Array(String)
        )) AS item
        FROM system.processes
        WHERE query_id != currentQueryID()
          AND is_initial_query
        ORDER BY memory_usage DESC, elapsed DESC
        LIMIT 12
    )
),
relation_values AS (
    SELECT groupArray(item) AS relations
    FROM (
        SELECT CAST((
            database,
            table,
            count(),
            sum(rows),
            sum(bytes_on_disk),
            max(level),
            formatDateTime(max(modification_time), '%FT%T')
        ) AS Tuple(
            schema String,
            relation String,
            parts UInt64,
            rows UInt64,
            bytes UInt64,
            maxPartLevel UInt32,
            newestPart String
        )) AS item
        FROM system.parts
        WHERE active
          AND database = currentDatabase()
        GROUP BY database, table
        ORDER BY sum(bytes_on_disk) DESC, count() DESC
        LIMIT 8
    )
),
background_values AS (
    SELECT groupArray(item) AS background
    FROM (
        SELECT item
        FROM (
        SELECT CAST((
            'merge',
            database,
            table,
            if(is_mutation, 'part mutation', if(merge_type = '', 'merge', merge_type)),
            progress,
            elapsed,
            num_parts,
            toInt64(0),
            result_part_name,
            memory_usage,
            rows_read,
            rows_written,
            bytes_read_uncompressed,
            bytes_written_uncompressed,
            toUInt8(0),
            ''
        ) AS Tuple(
            kind String,
            database String,
            table String,
            label String,
            progress Float64,
            elapsed Float64,
            parts UInt64,
            partsToDo Int64,
            target String,
            memoryBytes UInt64,
            rowsRead UInt64,
            rowsWritten UInt64,
            bytesRead UInt64,
            bytesWritten UInt64,
            failed UInt8,
            error String
        )) AS item,
        toUInt8(0) AS sort_failed,
        elapsed AS sort_elapsed
        FROM system.merges
        WHERE database = currentDatabase()

        UNION ALL

        SELECT CAST((
            'mutation',
            database,
            table,
            left(
                replaceRegexpAll(
                    replaceRegexpAll(command, '''([^'']|'''')*''', '''?'''),
                    '\\b[0-9]+([.][0-9]+)?\\b', '?'
                ),
                96
            ),
            toFloat64(if(is_done, 1, 0)),
            toFloat64(dateDiff('second', create_time, now())),
            toUInt64(0),
            parts_to_do,
            mutation_id,
            toUInt64(0),
            toUInt64(0),
            toUInt64(0),
            toUInt64(0),
            toUInt64(0),
            toUInt8(latest_fail_reason != ''),
            left(
                replaceRegexpAll(
                    replaceRegexpAll(latest_fail_reason, '''([^'']|'''')*''', '''?'''),
                    '\\b[0-9]+([.][0-9]+)?\\b', '?'
                ),
                160
            )
        ) AS Tuple(
            kind String,
            database String,
            table String,
            label String,
            progress Float64,
            elapsed Float64,
            parts UInt64,
            partsToDo Int64,
            target String,
            memoryBytes UInt64,
            rowsRead UInt64,
            rowsWritten UInt64,
            bytesRead UInt64,
            bytesWritten UInt64,
            failed UInt8,
            error String
        )) AS item,
        toUInt8(latest_fail_reason != '') AS sort_failed,
        toFloat64(dateDiff('second', create_time, now())) AS sort_elapsed
        FROM system.mutations
        WHERE database = currentDatabase()
          AND is_done = 0

        )
        ORDER BY sort_failed DESC, sort_elapsed DESC
        LIMIT 12
    )
)
SELECT
    1 AS schema,
    'details' AS kind,
    toUnixTimestamp64Milli(now64(3)) AS collectedAtMs,
    activity_values.activity AS activity,
    relation_values.relations AS relations,
    CAST([] AS Array(String)) AS blocking,
    background_values.background AS background,
    background_values.background AS maintenance,
    CAST([] AS Array(String)) AS vacuum
FROM activity_values
CROSS JOIN relation_values
CROSS JOIN background_values;
