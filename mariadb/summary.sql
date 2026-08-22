WITH status_values AS (
  SELECT
    MAX(CASE WHEN VARIABLE_NAME = 'Uptime' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS uptime_seconds,
    MAX(CASE WHEN VARIABLE_NAME = 'Threads_connected' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS threads_connected,
    MAX(CASE WHEN VARIABLE_NAME = 'Threads_running' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS threads_running,
    MAX(CASE WHEN VARIABLE_NAME = 'Questions' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS questions,
    SUM(CASE WHEN VARIABLE_NAME LIKE 'Handler_read_%' THEN CAST(VARIABLE_VALUE AS UNSIGNED) ELSE 0 END) AS rows_read,
    MAX(CASE WHEN VARIABLE_NAME = 'Handler_write' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS rows_inserted,
    MAX(CASE WHEN VARIABLE_NAME = 'Handler_update' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS rows_updated,
    MAX(CASE WHEN VARIABLE_NAME = 'Handler_delete' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS rows_deleted,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_read_requests' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS read_requests,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_reads' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS physical_reads,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_dirty' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS dirty_pages,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_pages_total' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS total_pages,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_buffer_pool_wait_free' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS buffer_wait_free,
    MAX(CASE WHEN VARIABLE_NAME = 'Innodb_os_log_written' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS redo_bytes,
    MAX(CASE WHEN VARIABLE_NAME = 'Created_tmp_disk_tables' THEN CAST(VARIABLE_VALUE AS UNSIGNED) END) AS disk_temp_tables
  FROM information_schema.GLOBAL_STATUS
), process_values AS (
  SELECT
    COUNT(*) AS used,
    COALESCE(SUM(COMMAND <> 'Sleep'), 0) AS active,
    COALESCE(SUM(COMMAND = 'Sleep'), 0) AS idle,
    COALESCE(MAX(CASE WHEN COMMAND <> 'Sleep' THEN TIME ELSE 0 END), 0) AS oldest_query_seconds
  FROM information_schema.PROCESSLIST
  WHERE ID <> CONNECTION_ID()
    AND COMMAND <> 'Daemon'
), transaction_values AS (
  SELECT
    COUNT(*) AS transactions,
    COALESCE(SUM(COALESCE((
      SELECT COMMAND = 'Sleep'
      FROM information_schema.PROCESSLIST
      WHERE ID = trx_mysql_thread_id
      LIMIT 1
    ), 0)), 0) AS idle_transactions,
    COALESCE(MAX(TIMESTAMPDIFF(SECOND, trx_started, NOW())), 0) AS oldest_xact_seconds,
    COALESCE(MAX(CASE WHEN COALESCE((
      SELECT COMMAND = 'Sleep'
      FROM information_schema.PROCESSLIST
      WHERE ID = trx_mysql_thread_id
      LIMIT 1
    ), 0) THEN TIMESTAMPDIFF(SECOND, trx_started, NOW()) ELSE 0 END), 0) AS oldest_idle_xact_seconds,
    COALESCE(MAX(CASE WHEN trx_wait_started IS NOT NULL THEN TIMESTAMPDIFF(SECOND, trx_wait_started, NOW()) ELSE 0 END), 0) AS oldest_lock_wait_seconds
  FROM information_schema.INNODB_TRX
  WHERE trx_mysql_thread_id <> CONNECTION_ID()
), data_waits AS (
  SELECT COUNT(DISTINCT requesting_trx_id) AS waiting
  FROM information_schema.INNODB_LOCK_WAITS
), metadata_waits AS (
  SELECT
    COUNT(DISTINCT locks.OWNER_THREAD_ID) AS waiting,
    COALESCE(MAX(threads.PROCESSLIST_TIME), 0) AS oldest_wait_seconds
  FROM performance_schema.metadata_locks AS locks
  LEFT JOIN performance_schema.threads AS threads
    ON threads.THREAD_ID = locks.OWNER_THREAD_ID
  WHERE locks.LOCK_STATUS = 'PENDING'
), metadata_capability AS (
  SELECT COUNT(*) > 0 AS enabled
  FROM performance_schema.setup_instruments
  WHERE NAME LIKE 'wait/lock/metadata%'
    AND ENABLED = 'YES'
), purge_values AS (
  SELECT COALESCE(MAX(CASE WHEN NAME = 'trx_rseg_history_len' THEN COUNT END), 0) AS history_length
  FROM information_schema.INNODB_METRICS
)
SELECT JSON_OBJECT(
  'schema', 1,
  'kind', 'summary',
  'collectedAtMs', CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3)) * 1000 AS UNSIGNED),
  'engine', 'mariadb',
  'identity', JSON_OBJECT(
    'database', DATABASE(),
    'user', CURRENT_USER(),
    'version', @@version,
    'versionComment', @@version_comment,
    'family', 'mysql',
    'versionNum', CAST(REPLACE(SUBSTRING_INDEX(@@version, '-', 1), '.', '') AS UNSIGNED),
    'inRecovery', @@read_only + 0,
    'uptimeSeconds', status_values.uptime_seconds
  ),
  'capabilities', JSON_OBJECT(
    'fullStats', @@performance_schema <> 0,
    'performanceSchema', @@performance_schema + 0,
    'dataLocks', FALSE,
    'innodbLockWaits', TRUE,
    'metadataLocks', metadata_capability.enabled,
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
    'rowsReturned', COALESCE(status_values.rows_read, 0),
    'rowsModified', COALESCE(status_values.rows_inserted, 0) + COALESCE(status_values.rows_updated, 0) + COALESCE(status_values.rows_deleted, 0),
    'blocksRead', COALESCE(status_values.physical_reads, 0),
    'blocksHit', IF(COALESCE(status_values.read_requests, 0) >= COALESCE(status_values.physical_reads, 0), status_values.read_requests - status_values.physical_reads, 0),
    'logBytes', COALESCE(status_values.redo_bytes, 0),
    'bufferWaitFree', COALESCE(status_values.buffer_wait_free, 0),
    'diskTempTables', COALESCE(status_values.disk_temp_tables, 0),
    'statsReset', DATE_FORMAT(DATE_SUB(NOW(), INTERVAL status_values.uptime_seconds SECOND), '%Y-%m-%dT%H:%i:%s'),
    'logStatsReset', DATE_FORMAT(DATE_SUB(NOW(), INTERVAL status_values.uptime_seconds SECOND), '%Y-%m-%dT%H:%i:%s')
  ),
  'maintenance', JSON_OBJECT(
    'kind', 'purge',
    'backlogLabel', 'PURGE DEBT',
    'surfaceLabel', 'INNODB SURFACE',
    'backlog', purge_values.history_length,
    'workerCount', @@innodb_purge_threads,
    'autoWorkerCount', @@innodb_purge_threads,
    'dirtyPages', status_values.dirty_pages,
    'totalPages', status_values.total_pages,
    'bufferWaitFree', status_values.buffer_wait_free,
    'lastMaintenance', NULL
  ),
  'replication', JSON_OBJECT('replicaCount', 0, 'maxByteLag', 0)
)
FROM status_values, process_values, transaction_values, data_waits, metadata_waits, metadata_capability, purge_values;
