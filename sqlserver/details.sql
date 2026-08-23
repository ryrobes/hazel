SET NOCOUNT ON;

DECLARE @now_ms bigint = DATEDIFF_BIG(millisecond, '19700101', SYSUTCDATETIME());

SELECT
  1 AS [schema],
  'details' AS [kind],
  @now_ms AS collectedAtMs,
  JSON_QUERY(COALESCE((
    SELECT TOP (12)
      r.session_id AS pid,
      DB_NAME(r.database_id) AS [database],
      s.login_name AS [user],
      s.program_name AS application,
      s.host_name AS client,
      LOWER(r.status) AS state,
      CASE WHEN r.wait_type LIKE 'LCK[_]%' THEN 'Lock' ELSE r.wait_type END AS waitType,
      r.wait_resource AS waitEvent,
      CONVERT(varchar(34), r.query_hash, 1) AS queryId,
      UPPER(r.command) AS queryVerb,
      CONCAT(
        UPPER(r.command),
        CASE WHEN st.objectid IS NOT NULL
          THEN CONCAT(' · ', QUOTENAME(OBJECT_SCHEMA_NAME(st.objectid, st.dbid)), '.', QUOTENAME(OBJECT_NAME(st.objectid, st.dbid)))
          ELSE CONCAT(' · query ', COALESCE(CONVERT(varchar(34), r.query_hash, 1), 'unavailable'))
        END
      ) AS queryText,
      DATEDIFF(second, r.start_time, SYSUTCDATETIME()) AS querySeconds,
      CASE WHEN at.transaction_begin_time IS NULL THEN 0 ELSE DATEDIFF(second, at.transaction_begin_time, SYSUTCDATETIME()) END AS xactSeconds,
      JSON_QUERY(CASE WHEN r.blocking_session_id > 0 THEN CONCAT('[', r.blocking_session_id, ']') ELSE '[]' END) AS blockedBy
    FROM sys.dm_exec_requests AS r
    JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
    LEFT JOIN sys.dm_tran_session_transactions AS tst ON tst.session_id = r.session_id
    LEFT JOIN sys.dm_tran_active_transactions AS at ON at.transaction_id = tst.transaction_id
    WHERE r.session_id <> @@SPID
      AND s.is_user_process = 1
      AND r.status IN ('running', 'runnable', 'suspended')
    ORDER BY CASE WHEN r.blocking_session_id > 0 THEN 0 ELSE 1 END, r.start_time
    FOR JSON PATH
  ), '[]')) AS activity,
  JSON_QUERY(COALESCE((
    SELECT TOP (8)
      SCHEMA_NAME(t.schema_id) AS [schema],
      t.name AS relation,
      COALESCE(usage_values.rows_read, 0) AS rowsRead,
      COALESCE(usage_values.rows_changed, 0) AS rowsChanged,
      CAST(0 AS bigint) AS inserts,
      COALESCE(usage_values.rows_changed, 0) AS updates,
      CAST(0 AS bigint) AS deletes,
      CAST(COALESCE(wait_values.total_wait_ms, 0) AS decimal(20, 2)) AS totalWaitMs,
      COALESCE(row_values.row_count, 0) AS [rowCount]
    FROM sys.tables AS t
    OUTER APPLY (
      SELECT
        SUM(user_seeks + user_scans + user_lookups) AS rows_read,
        SUM(user_updates) AS rows_changed
      FROM sys.dm_db_index_usage_stats
      WHERE database_id = DB_ID()
        AND object_id = t.object_id
    ) AS usage_values
    OUTER APPLY (
      SELECT SUM(row_lock_wait_in_ms + page_lock_wait_in_ms) AS total_wait_ms
      FROM sys.dm_db_index_operational_stats(DB_ID(), t.object_id, NULL, NULL)
    ) AS wait_values
    OUTER APPLY (
      SELECT SUM(row_count) AS row_count
      FROM sys.dm_db_partition_stats
      WHERE object_id = t.object_id
        AND index_id IN (0, 1)
    ) AS row_values
    WHERE t.is_ms_shipped = 0
    ORDER BY totalWaitMs DESC, rowsChanged DESC, rowsRead DESC
    FOR JSON PATH
  ), '[]')) AS relations,
  JSON_QUERY(COALESCE((
    SELECT TOP (12)
      blocked.session_id AS blockedPid,
      blocked.blocking_session_id AS blockerPid,
      COALESCE(blocked_session.program_name, blocked_session.login_name, 'session') AS blockedApplication,
      COALESCE(blocker_session.program_name, blocker_session.login_name, 'session') AS blockerApplication,
      blocker_session.status AS blockerState,
      CASE WHEN blocked.wait_type LIKE 'LCK[_]%' THEN 'LOCK' ELSE 'WAIT' END AS waitType,
      blocked.wait_type AS waitEvent,
      blocked.wait_type AS lockType,
      blocked.wait_resource AS lockMode,
      blocked.wait_resource AS lockTarget,
      DATEDIFF(second, blocked.start_time, SYSUTCDATETIME()) AS blockedSeconds
    FROM sys.dm_exec_requests AS blocked
    LEFT JOIN sys.dm_exec_sessions AS blocked_session ON blocked_session.session_id = blocked.session_id
    LEFT JOIN sys.dm_exec_sessions AS blocker_session ON blocker_session.session_id = blocked.blocking_session_id
    WHERE blocked.session_id <> @@SPID
      AND blocked.blocking_session_id > 0
    ORDER BY blocked.start_time
    FOR JSON PATH
  ), '[]')) AS blocking,
  JSON_QUERY(COALESCE((
    SELECT
      'log' AS kind,
      DB_NAME() AS worker,
      log_reuse_wait_desc AS state
    FROM sys.databases
    WHERE database_id = DB_ID()
    FOR JSON PATH
  ), '[]')) AS maintenance,
  JSON_QUERY('[]') AS vacuum
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
GO
