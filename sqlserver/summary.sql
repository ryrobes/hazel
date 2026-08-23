SET NOCOUNT ON;

DECLARE @now_ms bigint = DATEDIFF_BIG(millisecond, '19700101', SYSUTCDATETIME());
DECLARE @batch_total bigint = 0;
DECLARE @log_bytes bigint = 0;
DECLARE @page_reads bigint = 0;
DECLARE @page_lookups bigint = 0;

SELECT @batch_total = COALESCE(MAX(cntr_value), 0)
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:SQL Statistics%'
  AND counter_name = 'Batch Requests/sec';

SELECT @log_bytes = COALESCE(MAX(cntr_value), 0)
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%'
  AND counter_name = 'Log Bytes Flushed/sec'
  AND instance_name = DB_NAME();

SELECT
  @page_reads = COALESCE(MAX(CASE WHEN counter_name = 'Page reads/sec' THEN cntr_value ELSE 0 END), 0),
  @page_lookups = COALESCE(MAX(CASE WHEN counter_name = 'Page lookups/sec' THEN cntr_value ELSE 0 END), 0)
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Buffer Manager%'
  AND counter_name IN ('Page reads/sec', 'Page lookups/sec');

;WITH session_values AS (
  SELECT
    COUNT_BIG(*) AS used,
    COALESCE(SUM(CASE WHEN r.session_id IS NOT NULL THEN 1 ELSE 0 END), 0) AS active,
    COALESCE(SUM(CASE WHEN s.status = 'sleeping' THEN 1 ELSE 0 END), 0) AS idle,
    COALESCE(MAX(CASE WHEN s.status = 'running' THEN DATEDIFF(second, r.start_time, SYSUTCDATETIME()) ELSE 0 END), 0) AS oldest_query_seconds,
    COALESCE(MAX(CASE WHEN s.open_transaction_count > 0 THEN DATEDIFF(second, s.last_request_start_time, SYSUTCDATETIME()) ELSE 0 END), 0) AS oldest_xact_seconds,
    COALESCE(MAX(CASE WHEN s.status = 'sleeping' AND s.open_transaction_count > 0 THEN DATEDIFF(second, s.last_request_end_time, SYSUTCDATETIME()) ELSE 0 END), 0) AS oldest_idle_xact_seconds,
    COALESCE(SUM(CASE WHEN s.status = 'sleeping' AND s.open_transaction_count > 0 THEN 1 ELSE 0 END), 0) AS idle_in_transaction
  FROM sys.dm_exec_sessions AS s
  LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
  WHERE s.is_user_process = 1
    AND s.session_id <> @@SPID
), wait_values AS (
  SELECT
    COUNT(DISTINCT waiting_task_address) AS waiting,
    COALESCE(MAX(wait_duration_ms), 0) / 1000.0 AS oldest_wait_seconds
  FROM sys.dm_os_waiting_tasks AS waiting_tasks
  JOIN sys.dm_exec_sessions AS waiting_sessions ON waiting_sessions.session_id = waiting_tasks.session_id
  WHERE waiting_tasks.session_id <> @@SPID
    AND waiting_sessions.is_user_process = 1
    AND waiting_tasks.wait_type NOT LIKE 'SLEEP%'
), blocking_values AS (
  SELECT
    COUNT(DISTINCT session_id) AS blocked,
    COALESCE(MAX(DATEDIFF(second, start_time, SYSUTCDATETIME())), 0) AS oldest_blocked_seconds
  FROM sys.dm_exec_requests
  WHERE session_id <> @@SPID
    AND blocking_session_id > 0
), worker_values AS (
  SELECT
    COALESCE(SUM(active_workers_count), 0) AS used,
    (SELECT max_workers_count FROM sys.dm_os_sys_info) AS maximum
  FROM sys.dm_os_schedulers
  WHERE status = 'VISIBLE ONLINE'
), log_values AS (
  SELECT
    used_log_space_in_bytes AS used_bytes,
    total_log_size_in_bytes AS total_bytes,
    used_log_space_in_percent AS used_percent
  FROM sys.dm_db_log_space_usage
), identity_values AS (
  SELECT
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS product_version,
    CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(128)) AS product_level,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS edition,
    TRY_CONVERT(int, PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)), 4)) AS major_version,
    sqlserver_start_time
  FROM sys.dm_os_sys_info
)
SELECT
  1 AS [schema],
  'summary' AS [kind],
  @now_ms AS collectedAtMs,
  'sqlserver' AS engine,
  JSON_QUERY((
    SELECT
      DB_NAME() AS [database],
      ORIGINAL_LOGIN() AS [user],
      identity_values.product_version AS [version],
      CONCAT('SQL Server ', identity_values.product_level, ' · ', identity_values.edition) AS versionComment,
      'sqlserver' AS family,
      identity_values.major_version AS versionNum,
      CAST(CASE WHEN DATABASEPROPERTYEX(DB_NAME(), 'Updateability') <> 'READ_WRITE' THEN 1 ELSE 0 END AS bit) AS inRecovery,
      DATEDIFF(second, identity_values.sqlserver_start_time, SYSUTCDATETIME()) AS uptimeSeconds
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  )) AS [identity],
  JSON_QUERY((
    SELECT
      CAST(1 AS bit) AS fullStats,
      CAST(1 AS bit) AS performanceSchema,
      CAST(1 AS bit) AS dataLocks,
      CAST(1 AS bit) AS metadataLocks,
      CAST(0 AS bit) AS pgRvbbit
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  )) AS capabilities,
  JSON_QUERY((
    SELECT
      session_values.used AS used,
      (SELECT CASE WHEN value_in_use = 0 THEN 32767 ELSE value_in_use END FROM sys.configurations WHERE name = 'user connections') AS [max],
      session_values.active AS active,
      session_values.idle AS idle,
      session_values.idle_in_transaction AS idleInTransaction,
      wait_values.waiting AS waiting,
      blocking_values.blocked AS lockWaiting,
      blocking_values.blocked AS blocked,
      CASE WHEN blocking_values.oldest_blocked_seconds > wait_values.oldest_wait_seconds
        THEN blocking_values.oldest_blocked_seconds ELSE wait_values.oldest_wait_seconds END AS oldestLockWaitSeconds,
      session_values.oldest_xact_seconds AS oldestXactSeconds,
      session_values.oldest_idle_xact_seconds AS oldestIdleXactSeconds,
      session_values.oldest_query_seconds AS oldestQuerySeconds
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  )) AS connections,
  JSON_QUERY((
    SELECT
      @batch_total AS workTotal,
      CAST(0 AS bigint) AS rowsReturned,
      CAST(0 AS bigint) AS rowsModified,
      @page_reads AS blocksRead,
      CASE WHEN @page_lookups > @page_reads THEN @page_lookups - @page_reads ELSE 0 END AS blocksHit,
      @log_bytes AS logBytes,
      CONVERT(varchar(33), identity_values.sqlserver_start_time, 126) AS statsReset,
      CONVERT(varchar(33), identity_values.sqlserver_start_time, 126) AS logStatsReset
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  )) AS counters,
  JSON_QUERY((
    SELECT
      'log' AS kind,
      'LOG USED' AS backlogLabel,
      'TABLE PRESSURE' AS surfaceLabel,
      log_values.used_bytes AS backlog,
      CAST(0 AS int) AS workerCount,
      CAST(0 AS int) AS autoWorkerCount,
      log_values.used_bytes AS dirtyPages,
      log_values.total_bytes AS totalPages,
      CAST(0 AS bigint) AS bufferWaitFree,
      (SELECT log_reuse_wait_desc FROM sys.databases WHERE database_id = DB_ID()) AS logReuseWait,
      log_values.used_percent AS logUsedPercent
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  )) AS maintenance,
  JSON_QUERY((
    SELECT
      worker_values.used AS memoryUsed,
      worker_values.maximum AS memoryMax,
      worker_values.used AS workersUsed,
      worker_values.maximum AS workersMax,
      log_values.used_bytes AS logUsed,
      log_values.total_bytes AS logTotal
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
  )) AS capacity,
  JSON_QUERY('{"replicaCount":0,"maxByteLag":0}') AS [replication]
FROM session_values, wait_values, blocking_values, worker_values, log_values, identity_values
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
GO
