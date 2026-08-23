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
    'queryId', NULL,
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
    'querySeconds', CAST(TIME AS UNSIGNED),
    'xactSeconds', COALESCE((
      SELECT TIMESTAMPDIFF(SECOND, trx_started, NOW())
      FROM information_schema.innodb_trx
      WHERE trx_mysql_thread_id = p.ID
      LIMIT 1
    ), 0),
    'blockedBy', JSON_ARRAY()
  ) AS item
  FROM performance_schema.processlist AS p
  WHERE ID <> CONNECTION_ID()
    AND COMMAND <> 'Sleep'
    AND INFO IS NOT NULL
  ORDER BY (STATE LIKE '%lock%') DESC, TIME DESC
  LIMIT 12
), relation_rows AS (
  SELECT JSON_OBJECT(
    'schema', OBJECT_SCHEMA,
    'relation', OBJECT_NAME,
    'rowsRead', COUNT_FETCH,
    'rowsChanged', COUNT_INSERT + COUNT_UPDATE + COUNT_DELETE,
    'inserts', COUNT_INSERT,
    'updates', COUNT_UPDATE,
    'deletes', COUNT_DELETE,
    'totalWaitMs', ROUND(SUM_TIMER_WAIT / 1000000000, 2)
  ) AS item
  FROM performance_schema.table_io_waits_summary_by_table
  WHERE OBJECT_SCHEMA = DATABASE()
  ORDER BY (COUNT_INSERT + COUNT_UPDATE + COUNT_DELETE) DESC, COUNT_FETCH DESC, SUM_TIMER_WAIT DESC
  LIMIT 8
), data_blocking_rows AS (
  SELECT JSON_OBJECT(
    'blockedPid', waiting_thread.PROCESSLIST_ID,
    'blockerPid', blocking_thread.PROCESSLIST_ID,
    'blockedApplication', COALESCE(waiting_process.USER, 'session'),
    'blockerApplication', COALESCE(blocking_process.USER, 'session'),
    'blockerState', blocking_process.COMMAND,
    'waitType', 'DATA',
    'waitEvent', waiting_lock.LOCK_TYPE,
    'lockType', waiting_lock.LOCK_TYPE,
    'lockMode', waiting_lock.LOCK_MODE,
    'lockTarget', CONCAT_WS('.', waiting_lock.OBJECT_SCHEMA, waiting_lock.OBJECT_NAME),
    'blockedSeconds', CAST(COALESCE(waiting_process.TIME, 0) AS UNSIGNED)
  ) AS item
  FROM performance_schema.data_lock_waits AS waits
  JOIN performance_schema.data_locks AS waiting_lock
    ON waiting_lock.ENGINE = waits.ENGINE
   AND waiting_lock.ENGINE_LOCK_ID = waits.REQUESTING_ENGINE_LOCK_ID
  LEFT JOIN performance_schema.threads AS waiting_thread
    ON waiting_thread.THREAD_ID = waits.REQUESTING_THREAD_ID
  LEFT JOIN performance_schema.threads AS blocking_thread
    ON blocking_thread.THREAD_ID = waits.BLOCKING_THREAD_ID
  LEFT JOIN performance_schema.processlist AS waiting_process
    ON waiting_process.ID = waiting_thread.PROCESSLIST_ID
  LEFT JOIN performance_schema.processlist AS blocking_process
    ON blocking_process.ID = blocking_thread.PROCESSLIST_ID
  LIMIT 12
), metadata_blocking_rows AS (
  SELECT JSON_OBJECT(
    'blockedPid', waiting_thread.PROCESSLIST_ID,
    'blockerPid', blocking_thread.PROCESSLIST_ID,
    'blockedApplication', COALESCE(waiting_process.USER, 'session'),
    'blockerApplication', COALESCE(blocking_process.USER, 'session'),
    'blockerState', blocking_process.COMMAND,
    'waitType', 'METADATA',
    'waitEvent', waiting_lock.OBJECT_TYPE,
    'lockType', waiting_lock.LOCK_TYPE,
    'lockMode', waiting_lock.LOCK_DURATION,
    'lockTarget', CONCAT_WS('.', waiting_lock.OBJECT_SCHEMA, waiting_lock.OBJECT_NAME),
    'blockedSeconds', CAST(COALESCE(waiting_process.TIME, 0) AS UNSIGNED)
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
  LEFT JOIN performance_schema.processlist AS waiting_process
    ON waiting_process.ID = waiting_thread.PROCESSLIST_ID
  LEFT JOIN performance_schema.processlist AS blocking_process
    ON blocking_process.ID = blocking_thread.PROCESSLIST_ID
  WHERE waiting_lock.LOCK_STATUS = 'PENDING'
  LIMIT 12
), blocking_rows AS (
  SELECT item FROM data_blocking_rows
  UNION ALL
  SELECT item FROM metadata_blocking_rows
), maintenance_rows AS (
  SELECT JSON_OBJECT(
    'kind', 'purge',
    'worker', NAME,
    'state', PROCESSLIST_STATE
  ) AS item
  FROM performance_schema.threads
  WHERE TYPE = 'BACKGROUND' AND NAME LIKE '%purge%'
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
