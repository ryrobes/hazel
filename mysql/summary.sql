WITH status_values AS (
  SELECT
    MAX(CASE WHEN VARIABLE_NAME = 'Uptime' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS uptime_seconds,
    MAX(CASE WHEN VARIABLE_NAME = 'Threads_connected' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS threads_connected,
    MAX(CASE WHEN VARIABLE_NAME = 'Threads_running' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS threads_running,
    MAX(CASE WHEN VARIABLE_NAME = 'Questions' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS questions,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_rows_read' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS rows_read,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_rows_inserted' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS rows_inserted,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_rows_updated' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS rows_updated,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_rows_deleted' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS rows_deleted,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_read_requests' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS read_requests,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_reads' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS physical_reads,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_dirty' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS dirty_pages,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_total' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS total_pages,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_wait_free' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS buffer_wait_free,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_os_log_written' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS redo_bytes,
    MAX(CASE WHEN VARIABLE_NAME = 'Created_tmp_disk_tables' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS disk_temp_tables
  FROM performance_schema.global_status
), process_values AS (
  SELECT
    COUNT(*) AS used,
    SUM(COMMAND <> 'Sleep') AS active,
    SUM(COMMAND = 'Sleep') AS idle,
    COALESCE(MAX(CASE WHEN COMMAND <> 'Sleep' THEN TIME ELSE 0 END), 0) AS oldest_query_seconds
  FROM performance_schema.processlist
  WHERE ID <> CONNECTION_ID()
    AND COMMAND <> 'Daemon'
), transaction_values AS (
  SELECT
    COUNT(*) AS transactions,
    COALESCE(SUM(COALESCE((
      SELECT COMMAND = 'Sleep'
      FROM performance_schema.processlist
      WHERE ID = trx_mysql_thread_id
      LIMIT 1
    ), 0)), 0) AS idle_transactions,
    COALESCE(MAX(TIMESTAMPDIFF(SECOND, trx_started, NOW())), 0) AS oldest_xact_seconds,
    COALESCE(MAX(CASE WHEN COALESCE((
      SELECT COMMAND = 'Sleep'
      FROM performance_schema.processlist
      WHERE ID = trx_mysql_thread_id
      LIMIT 1
    ), 0) THEN TIMESTAMPDIFF(SECOND, trx_started, NOW()) ELSE 0 END), 0) AS oldest_idle_xact_seconds,
    COALESCE(MAX(CASE WHEN trx_wait_started IS NOT NULL THEN TIMESTAMPDIFF(SECOND, trx_wait_started, NOW()) ELSE 0 END), 0) AS oldest_lock_wait_seconds
  FROM information_schema.innodb_trx
  WHERE trx_mysql_thread_id <> CONNECTION_ID()
), data_waits AS (
  SELECT COUNT(DISTINCT REQUESTING_THREAD_ID) AS waiting
  FROM performance_schema.data_lock_waits
), metadata_waits AS (
  SELECT
    COUNT(DISTINCT locks.OWNER_THREAD_ID) AS waiting,
    COALESCE(MAX(processes.TIME), 0) AS oldest_wait_seconds
  FROM performance_schema.metadata_locks AS locks
  LEFT JOIN performance_schema.threads AS threads
    ON threads.THREAD_ID = locks.OWNER_THREAD_ID
  LEFT JOIN performance_schema.processlist AS processes
    ON processes.ID = threads.PROCESSLIST_ID
  WHERE locks.LOCK_STATUS = 'PENDING'
), purge_values AS (
  SELECT COALESCE(MAX(CASE WHEN NAME = 'trx_rseg_history_len' THEN COUNT END), 0) AS history_length
  FROM information_schema.innodb_metrics
), purge_threads AS (
  SELECT COUNT(*) AS workers
  FROM performance_schema.threads
  WHERE TYPE = 'BACKGROUND' AND NAME LIKE '%purge%'
)
SELECT JSON_OBJECT(
  'schema', 1,
  'kind', 'summary',
  'collectedAtMs', CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3)) * 1000 AS UNSIGNED),
  'engine', 'mysql',
  'identity', JSON_OBJECT(
    'database', DATABASE(),
    'user', CURRENT_USER(),
    'version', @@version,
    'versionComment', @@version_comment,
    'versionNum', CAST(REPLACE(SUBSTRING_INDEX(@@version, '-', 1), '.', '') AS UNSIGNED),
    'inRecovery', @@read_only OR @@super_read_only,
    'uptimeSeconds', status_values.uptime_seconds
  ),
  'capabilities', JSON_OBJECT(
    'fullStats', TRUE,
    'performanceSchema', @@performance_schema,
    'pgRvbbit', FALSE
  ),
  'connections', JSON_OBJECT(
    'used', process_values.used,
    'max', @@max_connections,
    'active', process_values.active,
    'idle', process_values.idle,
    'idleInTransaction', transaction_values.idle_transactions,
    'waiting', data_waits.waiting + metadata_waits.waiting,
    'lockWaiting', data_waits.waiting + metadata_waits.waiting,
    'blocked', data_waits.waiting + metadata_waits.waiting,
    'oldestLockWaitSeconds', GREATEST(transaction_values.oldest_lock_wait_seconds, metadata_waits.oldest_wait_seconds),
    'oldestXactSeconds', transaction_values.oldest_xact_seconds,
    'oldestIdleXactSeconds', transaction_values.oldest_idle_xact_seconds,
    'oldestQuerySeconds', process_values.oldest_query_seconds
  ),
  'counters', JSON_OBJECT(
    'workTotal', status_values.questions,
    'rowsReturned', status_values.rows_read,
    'rowsModified', status_values.rows_inserted + status_values.rows_updated + status_values.rows_deleted,
    'blocksRead', status_values.physical_reads,
    'blocksHit', GREATEST(status_values.read_requests - status_values.physical_reads, 0),
    'logBytes', status_values.redo_bytes,
    'bufferWaitFree', status_values.buffer_wait_free,
    'diskTempTables', status_values.disk_temp_tables,
    'statsReset', DATE_FORMAT(DATE_SUB(NOW(), INTERVAL status_values.uptime_seconds SECOND), '%Y-%m-%dT%H:%i:%s'),
    'logStatsReset', DATE_FORMAT(DATE_SUB(NOW(), INTERVAL status_values.uptime_seconds SECOND), '%Y-%m-%dT%H:%i:%s')
  ),
  'maintenance', JSON_OBJECT(
    'kind', 'purge',
    'backlogLabel', 'PURGE DEBT',
    'surfaceLabel', 'INNODB SURFACE',
    'backlog', purge_values.history_length,
    'workerCount', purge_threads.workers,
    'autoWorkerCount', purge_threads.workers,
    'dirtyPages', status_values.dirty_pages,
    'totalPages', status_values.total_pages,
    'bufferWaitFree', status_values.buffer_wait_free,
    'lastMaintenance', NULL
  ),
  'replication', JSON_OBJECT('replicaCount', 0, 'maxByteLag', 0)
)
FROM status_values, process_values, transaction_values, data_waits, metadata_waits, purge_values, purge_threads;
