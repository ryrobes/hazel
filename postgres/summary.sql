BEGIN READ ONLY;

SELECT
  CASE
    WHEN current_setting('server_version_num')::integer >= 120000
      THEN 'pg_catalog.pg_stat_progress_vacuum'
    ELSE $hazel$(SELECT NULL::integer AS pid WHERE false) AS hazel_legacy_vacuum_progress$hazel$
  END AS hazel_vacuum_progress_source,
  CASE
    WHEN current_setting('server_version_num')::integer >= 140000
      THEN 'pg_catalog.pg_stat_wal'
    ELSE $hazel$(
      SELECT
        CASE
          WHEN pg_is_in_recovery()
            THEN pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0')
          ELSE pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')
        END::numeric AS wal_bytes,
        NULL::bigint AS wal_records,
        NULL::bigint AS wal_fpi,
        NULL::timestamp with time zone AS stats_reset
    ) AS hazel_legacy_wal$hazel$
  END AS hazel_wal_source
\gset

WITH identity AS (
  SELECT
    current_database() AS database_name,
    current_user AS user_name,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num')::integer AS server_version_num,
    current_setting('max_connections')::integer AS max_connections,
    pg_is_in_recovery() AS in_recovery,
    extract(epoch FROM clock_timestamp() - pg_postmaster_start_time())::double precision AS uptime_seconds,
    pg_has_role(current_user, 'pg_monitor', 'member')
      OR pg_has_role(current_user, 'pg_read_all_stats', 'member') AS full_stats,
    to_regclass('public.pg_stat_statements') IS NOT NULL AS has_stat_statements,
    EXISTS (
      SELECT 1 FROM pg_extension WHERE extname = 'pg_rvbbit'
    ) AS has_pg_rvbbit
), activity AS (
  SELECT
    count(*) FILTER (WHERE backend_type = 'client backend')::integer AS used,
    count(*) FILTER (WHERE backend_type = 'client backend' AND state = 'active')::integer AS active,
    count(*) FILTER (WHERE backend_type = 'client backend' AND state = 'idle')::integer AS idle,
    count(*) FILTER (
      WHERE backend_type = 'client backend' AND state LIKE 'idle in transaction%'
    )::integer AS idle_in_transaction,
    count(*) FILTER (
      WHERE backend_type = 'client backend' AND state = 'active' AND wait_event IS NOT NULL
    )::integer AS waiting,
    count(*) FILTER (
      WHERE backend_type = 'client backend' AND wait_event_type = 'Lock'
    )::integer AS lock_waiting,
    count(*) FILTER (
      WHERE backend_type = 'client backend' AND cardinality(pg_blocking_pids(pid)) > 0
    )::integer AS blocked,
    count(*) FILTER (
      WHERE backend_type = 'autovacuum worker'
    )::integer AS autovacuum_workers,
    coalesce(max(extract(epoch FROM clock_timestamp() - xact_start)) FILTER (
      WHERE backend_type = 'client backend' AND xact_start IS NOT NULL
    ), 0)::double precision AS oldest_xact_seconds,
    coalesce(max(extract(epoch FROM clock_timestamp() - xact_start)) FILTER (
      WHERE backend_type = 'client backend'
        AND state LIKE 'idle in transaction%'
        AND xact_start IS NOT NULL
    ), 0)::double precision AS oldest_idle_xact_seconds,
    coalesce(max(extract(epoch FROM clock_timestamp() - query_start)) FILTER (
      WHERE backend_type = 'client backend' AND state = 'active' AND query_start IS NOT NULL
    ), 0)::double precision AS oldest_query_seconds,
    coalesce(max(extract(epoch FROM clock_timestamp() - query_start)) FILTER (
      WHERE backend_type = 'client backend'
        AND state = 'active'
        AND wait_event_type = 'Lock'
        AND query_start IS NOT NULL
    ), 0)::double precision AS oldest_lock_wait_seconds
  FROM pg_stat_activity
  WHERE pid <> pg_backend_pid()
    AND application_name IS DISTINCT FROM 'hazel-monitor'
), database_stats AS (
  SELECT
    numbackends,
    xact_commit,
    xact_rollback,
    tup_returned,
    tup_fetched,
    tup_inserted,
    tup_updated,
    tup_deleted,
    blks_read,
    blks_hit,
    temp_bytes,
    deadlocks,
    stats_reset
  FROM pg_stat_database
  WHERE datname = current_database()
), relation_stats AS (
  SELECT
    coalesce(sum(n_live_tup), 0)::bigint AS live_tuples,
    coalesce(sum(n_dead_tup), 0)::bigint AS dead_tuples,
    count(*) FILTER (WHERE n_dead_tup > 0)::integer AS relations_with_dead_tuples,
    coalesce(sum(autovacuum_count), 0)::bigint AS autovacuum_count,
    coalesce(sum(vacuum_count), 0)::bigint AS vacuum_count,
    max(last_autovacuum) AS last_autovacuum,
    max(last_vacuum) AS last_vacuum
  FROM pg_stat_user_tables
), vacuum_progress AS (
  SELECT count(*)::integer AS workers
  FROM :hazel_vacuum_progress_source
), wal_stats AS (
  SELECT wal_bytes, wal_records, wal_fpi, stats_reset
  FROM :hazel_wal_source
), replication AS (
  SELECT
    count(*)::integer AS replica_count,
    coalesce(max(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)), 0)::numeric AS max_byte_lag
  FROM pg_stat_replication
)
SELECT jsonb_build_object(
  'schema', 1,
  'kind', 'summary',
  'collectedAtMs', floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint,
  'engine', 'postgresql',
  'identity', jsonb_build_object(
    'database', identity.database_name,
    'user', identity.user_name,
    'version', identity.server_version,
    'versionNum', identity.server_version_num,
    'inRecovery', identity.in_recovery,
    'uptimeSeconds', identity.uptime_seconds
  ),
  'capabilities', jsonb_build_object(
    'fullStats', identity.full_stats,
    'statStatements', identity.has_stat_statements,
    'pgRvbbit', identity.has_pg_rvbbit
  ),
  'connections', jsonb_build_object(
    'used', activity.used,
    'max', identity.max_connections,
    'active', activity.active,
    'idle', activity.idle,
    'idleInTransaction', activity.idle_in_transaction,
    'waiting', activity.waiting,
    'lockWaiting', activity.lock_waiting,
    'blocked', activity.blocked,
    'oldestLockWaitSeconds', activity.oldest_lock_wait_seconds,
    'oldestXactSeconds', activity.oldest_xact_seconds,
    'oldestIdleXactSeconds', activity.oldest_idle_xact_seconds,
    'oldestQuerySeconds', activity.oldest_query_seconds
  ),
  'counters', jsonb_build_object(
    'xactCommit', database_stats.xact_commit,
    'xactRollback', database_stats.xact_rollback,
    'tuplesReturned', database_stats.tup_returned,
    'tuplesFetched', database_stats.tup_fetched,
    'tuplesInserted', database_stats.tup_inserted,
    'tuplesUpdated', database_stats.tup_updated,
    'tuplesDeleted', database_stats.tup_deleted,
    'blocksRead', database_stats.blks_read,
    'blocksHit', database_stats.blks_hit,
    'tempBytes', database_stats.temp_bytes,
    'deadlocks', database_stats.deadlocks,
    'walBytes', wal_stats.wal_bytes,
    'walRecords', wal_stats.wal_records,
    'walFpi', wal_stats.wal_fpi,
    'databaseStatsReset', database_stats.stats_reset,
    'walStatsReset', wal_stats.stats_reset
  ),
  'mvcc', jsonb_build_object(
    'liveTuples', relation_stats.live_tuples,
    'deadTuples', relation_stats.dead_tuples,
    'relationsWithDeadTuples', relation_stats.relations_with_dead_tuples,
    'autovacuumCount', relation_stats.autovacuum_count,
    'vacuumCount', relation_stats.vacuum_count,
    'autovacuumWorkers', activity.autovacuum_workers,
    'vacuumWorkers', vacuum_progress.workers,
    'lastAutovacuum', relation_stats.last_autovacuum,
    'lastVacuum', relation_stats.last_vacuum
  ),
  'maintenance', jsonb_build_object(
    'kind', 'vacuum',
    'backlogLabel', 'DEAD TUPLES',
    'surfaceLabel', 'MVCC SURFACE',
    'backlog', relation_stats.dead_tuples,
    'workerCount', vacuum_progress.workers,
    'autoWorkerCount', activity.autovacuum_workers,
    'dirtyPages', 0,
    'totalPages', 0,
    'bufferWaitFree', 0,
    'lastMaintenance', greatest(relation_stats.last_autovacuum, relation_stats.last_vacuum)
  ),
  'replication', jsonb_build_object(
    'replicaCount', replication.replica_count,
    'maxByteLag', replication.max_byte_lag,
    'replayDelaySeconds', CASE
      WHEN identity.in_recovery AND pg_last_xact_replay_timestamp() IS NOT NULL
        THEN greatest(0, extract(epoch FROM clock_timestamp() - pg_last_xact_replay_timestamp()))::double precision
      ELSE NULL
    END
  )
)
FROM identity, activity, database_stats, relation_stats, vacuum_progress, wal_stats, replication;

COMMIT;
