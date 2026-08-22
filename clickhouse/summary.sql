WITH
event_values AS (
    SELECT
        sumIf(value, event = 'Query') AS queries,
        sumIf(value, event = 'SelectedRows') AS selected_rows,
        sumIf(value, event = 'SelectedBytes') AS selected_bytes,
        sumIf(value, event = 'InsertedRows') AS inserted_rows,
        sumIf(value, event = 'InsertedBytes') AS inserted_bytes,
        sumIf(value, event = 'FailedQuery') AS failed_queries
    FROM system.events
),
metric_values AS (
    SELECT
        maxIf(toUInt64(value), metric = 'TCPConnection') AS tcp_connections,
        maxIf(toUInt64(value), metric = 'MemoryTracking') AS memory_used
    FROM system.metrics
),
async_values AS (
    SELECT
        maxIf(toUInt64(value), metric = 'CGroupMemoryTotal') AS cgroup_memory_total,
        maxIf(toUInt64(value), metric = 'OSMemoryTotal') AS os_memory_total,
        maxIf(toUInt64(value), metric = 'MaxPartCountForPartition') AS max_part_count
    FROM system.asynchronous_metrics
),
process_values AS (
    SELECT
        countIf(query_id != currentQueryID()) AS active_queries,
        maxIf(elapsed, query_id != currentQueryID()) AS oldest_query_seconds
    FROM system.processes
),
merge_values AS (
    SELECT count() AS active_merges
    FROM system.merges
    WHERE database = currentDatabase()
),
mutation_values AS (
    SELECT
        countIf(is_done = 0) AS pending_mutations,
        sumIf(greatest(parts_to_do, 0), is_done = 0) AS mutation_parts,
        countIf(is_done = 0 AND latest_fail_reason != '') AS failed_mutations
    FROM system.mutations
    WHERE database = currentDatabase()
),
part_values AS (
    SELECT
        count() AS active_parts,
        uniqExact(partition_id) AS active_partitions,
        greatest(active_parts - active_partitions, 0) AS mergeable_parts
    FROM system.parts
    WHERE active AND database = currentDatabase()
),
disk_values AS (
    SELECT
        sum(total_space - free_space) AS disk_used,
        sum(total_space) AS disk_total
    FROM system.disks
),
connection_limit AS (
    SELECT toUInt64OrZero(maxIf(value, name = 'max_connections')) AS max_connections
    FROM system.server_settings
),
replication_values AS (
    SELECT
        count() AS replica_queue,
        countIf(last_exception != '') AS replica_failures
    FROM system.replication_queue
    WHERE database = currentDatabase()
)
SELECT
    1 AS schema,
    'summary' AS kind,
    toUnixTimestamp64Milli(now64(3)) AS collectedAtMs,
    'clickhouse' AS engine,
    CAST((
        currentDatabase(),
        currentUser(),
        version(),
        'clickhouse',
        toUInt8(0),
        toUInt64(uptime())
    ) AS Tuple(
        database String,
        user String,
        version String,
        family String,
        inRecovery UInt8,
        uptimeSeconds UInt64
    )) AS identity,
    CAST((
        toUInt8(1),
        toUInt8(1),
        toUInt8(1),
        toUInt8(1)
    ) AS Tuple(
        fullStats UInt8,
        processes UInt8,
        merges UInt8,
        mutations UInt8
    )) AS capabilities,
    CAST((
        if(metric_values.tcp_connections > 0, metric_values.tcp_connections - 1, 0),
        connection_limit.max_connections,
        process_values.active_queries,
        toUInt64(0),
        toUInt64(0),
        toUInt64(0),
        toUInt64(0),
        toFloat64(0),
        toFloat64(0),
        toFloat64(0),
        process_values.oldest_query_seconds
    ) AS Tuple(
        used UInt64,
        max UInt64,
        active UInt64,
        idle UInt64,
        idleInTransaction UInt64,
        waiting UInt64,
        lockWaiting UInt64,
        blocked Float64,
        oldestLockWaitSeconds Float64,
        oldestXactSeconds Float64,
        oldestQuerySeconds Float64
    )) AS connections,
    CAST((
        event_values.queries,
        event_values.selected_rows,
        event_values.inserted_rows,
        event_values.selected_bytes,
        event_values.inserted_bytes,
        event_values.failed_queries,
        formatDateTime(now() - toIntervalSecond(uptime()), '%FT%T'),
        formatDateTime(now() - toIntervalSecond(uptime()), '%FT%T')
    ) AS Tuple(
        workTotal UInt64,
        rowsReturned UInt64,
        rowsModified UInt64,
        blocksRead UInt64,
        logBytes UInt64,
        failedQueries UInt64,
        statsReset String,
        logStatsReset String
    )) AS counters,
    CAST((
        'merge',
        'MERGE DEBT',
        'PART SURFACE',
        part_values.mergeable_parts + mutation_values.mutation_parts + replication_values.replica_queue,
        merge_values.active_merges,
        mutation_values.pending_mutations,
        merge_values.active_merges,
        mutation_values.pending_mutations,
        mutation_values.mutation_parts,
        mutation_values.failed_mutations + replication_values.replica_failures,
        part_values.active_parts,
        async_values.max_part_count
    ) AS Tuple(
        kind String,
        backlogLabel String,
        surfaceLabel String,
        backlog UInt64,
        workerCount UInt64,
        autoWorkerCount UInt64,
        activeMerges UInt64,
        pendingMutations UInt64,
        mutationParts UInt64,
        failedMutations UInt64,
        activeParts UInt64,
        maxPartCount UInt64
    )) AS maintenance,
    CAST((
        metric_values.memory_used,
        if(async_values.cgroup_memory_total > 0, async_values.cgroup_memory_total, async_values.os_memory_total),
        disk_values.disk_used,
        disk_values.disk_total
    ) AS Tuple(
        memoryUsed UInt64,
        memoryMax UInt64,
        diskUsed UInt64,
        diskTotal UInt64
    )) AS capacity,
    CAST((
        replication_values.replica_queue,
        replication_values.replica_failures
    ) AS Tuple(
        replicaCount UInt64,
        failures UInt64
    )) AS replication
FROM event_values
CROSS JOIN metric_values
CROSS JOIN async_values
CROSS JOIN process_values
CROSS JOIN merge_values
CROSS JOIN mutation_values
CROSS JOIN part_values
CROSS JOIN disk_values
CROSS JOIN connection_limit
CROSS JOIN replication_values;
