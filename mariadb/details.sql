WITH activity_rows AS (
  SELECT JSON_OBJECT(
    'pid', ID,
    'database', DB,
    'user', USER,
    'application', USER,
    'client', HOST,
    'state', LOWER(COMMAND),
    'waitType', CASE WHEN STATE LIKE '%lock%' THEN 'Lock' ELSE NULL END,
    'waitEvent', STATE,
    'queryId', QUERY_ID,
    'queryVerb', UPPER(COALESCE(SUBSTRING_INDEX(TRIM(INFO), ' ', 1), COMMAND, 'QUERY')),
    'queryText', LEFT(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(COALESCE(INFO, COMMAND), '[[:space:]]+', ' '),
          '''([^'']|'''')*''', '''?'''
        ),
        '[0-9]+([.][0-9]+)?', '?'
      ),
      320
    ),
    'querySeconds', TIME,
    'xactSeconds', COALESCE((
      SELECT TIMESTAMPDIFF(SECOND, trx_started, NOW())
      FROM information_schema.INNODB_TRX
      WHERE trx_mysql_thread_id = p.ID
      LIMIT 1
    ), 0),
    'blockedBy', JSON_ARRAY()
  ) AS item
  FROM information_schema.PROCESSLIST AS p
  WHERE ID <> CONNECTION_ID()
    AND COMMAND <> 'Sleep'
    AND INFO IS NOT NULL
  ORDER BY (STATE LIKE '%lock%') DESC, TIME DESC
  LIMIT 12
), relation_source AS (
  SELECT
    OBJECT_SCHEMA AS schema_name,
    OBJECT_NAME AS relation_name,
    COUNT_FETCH AS rows_read,
    COUNT_INSERT + COUNT_UPDATE + COUNT_DELETE AS rows_changed,
    COUNT_INSERT AS inserts,
    COUNT_UPDATE AS updates,
    COUNT_DELETE AS deletes,
    ROUND(SUM_TIMER_WAIT / 1000000000, 2) AS total_wait_ms,
    FALSE AS limited_visibility,
    NULL AS estimated_rows
  FROM performance_schema.table_io_waits_summary_by_table
  WHERE @@performance_schema <> 0
    AND OBJECT_SCHEMA = DATABASE()
  UNION ALL
  SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    0,
    0,
    0,
    0,
    0,
    0,
    TRUE,
    COALESCE(TABLE_ROWS, 0)
  FROM information_schema.TABLES
  WHERE @@performance_schema = 0
    AND TABLE_SCHEMA = DATABASE()
), relation_rows AS (
  SELECT JSON_OBJECT(
    'schema', schema_name,
    'relation', relation_name,
    'rowsRead', rows_read,
    'rowsChanged', rows_changed,
    'inserts', inserts,
    'updates', updates,
    'deletes', deletes,
    'totalWaitMs', total_wait_ms,
    'limited', limited_visibility,
    'estimatedRows', estimated_rows
  ) AS item
  FROM relation_source
  ORDER BY rows_changed DESC, rows_read DESC, estimated_rows DESC, total_wait_ms DESC
  LIMIT 8
), data_blocking_rows AS (
  SELECT JSON_OBJECT(
    'blockedPid', waiting_trx.trx_mysql_thread_id,
    'blockerPid', blocking_trx.trx_mysql_thread_id,
    'blockedApplication', COALESCE(waiting_process.USER, 'session'),
    'blockerApplication', COALESCE(blocking_process.USER, 'session'),
    'blockerState', blocking_process.COMMAND,
    'waitType', 'DATA',
    'waitEvent', waiting_lock.lock_type,
    'lockType', waiting_lock.lock_type,
    'lockMode', waiting_lock.lock_mode,
    'lockTarget', REPLACE(waiting_lock.lock_table, '`', ''),
    'blockedSeconds', COALESCE(TIMESTAMPDIFF(SECOND, waiting_trx.trx_wait_started, NOW()), waiting_process.TIME, 0)
  ) AS item
  FROM information_schema.INNODB_LOCK_WAITS AS waits
  JOIN information_schema.INNODB_LOCKS AS waiting_lock
    ON waiting_lock.lock_id = waits.requested_lock_id
  JOIN information_schema.INNODB_LOCKS AS blocking_lock
    ON blocking_lock.lock_id = waits.blocking_lock_id
  JOIN information_schema.INNODB_TRX AS waiting_trx
    ON waiting_trx.trx_id = waits.requesting_trx_id
  JOIN information_schema.INNODB_TRX AS blocking_trx
    ON blocking_trx.trx_id = waits.blocking_trx_id
  LEFT JOIN information_schema.PROCESSLIST AS waiting_process
    ON waiting_process.ID = waiting_trx.trx_mysql_thread_id
  LEFT JOIN information_schema.PROCESSLIST AS blocking_process
    ON blocking_process.ID = blocking_trx.trx_mysql_thread_id
  LIMIT 12
), metadata_blocking_rows AS (
  SELECT JSON_OBJECT(
    'blockedPid', waiting_thread.PROCESSLIST_ID,
    'blockerPid', blocking_thread.PROCESSLIST_ID,
    'blockedApplication', COALESCE(waiting_thread.PROCESSLIST_USER, 'session'),
    'blockerApplication', COALESCE(blocking_thread.PROCESSLIST_USER, 'session'),
    'blockerState', blocking_thread.PROCESSLIST_COMMAND,
    'waitType', 'METADATA',
    'waitEvent', waiting_lock.OBJECT_TYPE,
    'lockType', waiting_lock.LOCK_TYPE,
    'lockMode', waiting_lock.LOCK_DURATION,
    'lockTarget', CONCAT_WS('.', waiting_lock.OBJECT_SCHEMA, waiting_lock.OBJECT_NAME),
    'blockedSeconds', COALESCE(waiting_thread.PROCESSLIST_TIME, 0)
  ) AS item
  FROM performance_schema.metadata_locks AS waiting_lock
  JOIN performance_schema.metadata_locks AS blocking_lock
    ON blocking_lock.OBJECT_TYPE = waiting_lock.OBJECT_TYPE
   AND blocking_lock.OBJECT_SCHEMA <=> waiting_lock.OBJECT_SCHEMA
   AND blocking_lock.OBJECT_NAME <=> waiting_lock.OBJECT_NAME
   AND blocking_lock.LOCK_STATUS = 'GRANTED'
   AND blocking_lock.OWNER_THREAD_ID <> waiting_lock.OWNER_THREAD_ID
  LEFT JOIN performance_schema.threads AS waiting_thread
    ON waiting_thread.THREAD_ID = waiting_lock.OWNER_THREAD_ID
  LEFT JOIN performance_schema.threads AS blocking_thread
    ON blocking_thread.THREAD_ID = blocking_lock.OWNER_THREAD_ID
  WHERE waiting_lock.LOCK_STATUS = 'PENDING'
  LIMIT 12
), blocking_rows AS (
  SELECT item FROM data_blocking_rows
  UNION ALL
  SELECT item FROM metadata_blocking_rows
), maintenance_rows AS (
  SELECT JSON_OBJECT(
    'kind', 'purge',
    'worker', CONCAT('purge threads ×', @@innodb_purge_threads),
    'state', 'configured'
  ) AS item
)
SELECT JSON_OBJECT(
  'schema', 1,
  'kind', 'details',
  'collectedAtMs', CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3)) * 1000 AS UNSIGNED),
  'activity', COALESCE((SELECT JSON_ARRAYAGG(item) FROM activity_rows), JSON_ARRAY()),
  'relations', COALESCE((SELECT JSON_ARRAYAGG(item) FROM relation_rows), JSON_ARRAY()),
  'blocking', COALESCE((SELECT JSON_ARRAYAGG(item) FROM blocking_rows), JSON_ARRAY()),
  'maintenance', COALESCE((SELECT JSON_ARRAYAGG(item) FROM maintenance_rows), JSON_ARRAY()),
  'vacuum', JSON_ARRAY()
);
