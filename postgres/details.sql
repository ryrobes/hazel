WITH activity_rows AS (
  SELECT jsonb_build_object(
    'pid', pid,
    'database', datname,
    'user', usename,
    'application', application_name,
    'client', coalesce(client_addr::text, 'local'),
    'state', state,
    'waitType', wait_event_type,
    'waitEvent', wait_event,
    'queryId', query_id,
    'queryVerb', upper(coalesce(substring(ltrim(query) FROM '^([[:alpha:]]+)'), 'QUERY')),
    'queryText', left(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(query, E'[\\n\\r\\t ]+', ' ', 'g'),
              E'\\$[A-Za-z_][A-Za-z0-9_]*\\$.*\\$[A-Za-z_][A-Za-z0-9_]*\\$', '$tag$?$tag$', 'g'
            ),
            E'\\$\\$.*\\$\\$', '$$?$$', 'g'
          ),
          $$'([^']|'')*'$$, '''?''', 'g'
        ),
        $$\m[0-9]+(\.[0-9]+)?\M$$, '?', 'g'
      ),
      320
    ),
    'querySeconds', CASE
      WHEN state = 'active' AND query_start IS NOT NULL
        THEN extract(epoch FROM clock_timestamp() - query_start)::double precision
      ELSE 0
    END,
    'xactSeconds', CASE
      WHEN xact_start IS NOT NULL
        THEN extract(epoch FROM clock_timestamp() - xact_start)::double precision
      ELSE 0
    END,
    'blockedBy', to_jsonb(pg_blocking_pids(pid))
  ) AS item
  FROM pg_stat_activity
  WHERE pid <> pg_backend_pid()
    AND backend_type = 'client backend'
    AND state = 'active'
    AND application_name IS DISTINCT FROM 'hazel-monitor'
  ORDER BY
    (cardinality(pg_blocking_pids(pid)) > 0) DESC,
    (wait_event IS NOT NULL) DESC,
    xact_start ASC NULLS LAST,
    query_start ASC NULLS LAST
  LIMIT 12
), relation_rows AS (
  SELECT jsonb_build_object(
    'schema', schemaname,
    'relation', relname,
    'liveTuples', n_live_tup,
    'deadTuples', n_dead_tup,
    'deadPercent', CASE
      WHEN n_live_tup + n_dead_tup > 0
        THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
      ELSE 0
    END,
    'inserts', n_tup_ins,
    'updates', n_tup_upd,
    'deletes', n_tup_del,
    'lastAutovacuum', last_autovacuum,
    'lastAutoanalyze', last_autoanalyze,
    'autovacuumCount', autovacuum_count,
    'autoanalyzeCount', autoanalyze_count
  ) AS item
  FROM pg_stat_user_tables
  ORDER BY n_dead_tup DESC, n_live_tup DESC
  LIMIT 8
), blocking_rows AS (
  SELECT jsonb_build_object(
    'blockedPid', blocked.pid,
    'blockerPid', blocker.blocker_pid,
    'blockedApplication', coalesce(nullif(blocked.application_name, ''), blocked.usename, 'session'),
    'blockerApplication', coalesce(nullif(blocker_activity.application_name, ''), blocker_activity.usename, 'session'),
    'blockerState', blocker_activity.state,
    'waitType', blocked.wait_event_type,
    'waitEvent', blocked.wait_event,
    'lockType', waiting_lock.locktype,
    'lockMode', waiting_lock.mode,
    'lockTarget', CASE
      WHEN waiting_relation.oid IS NOT NULL
        THEN format('%I.%I', waiting_namespace.nspname, waiting_relation.relname)
      WHEN waiting_lock.transactionid IS NOT NULL
        THEN 'transaction ' || waiting_lock.transactionid::text
      WHEN waiting_lock.virtualxid IS NOT NULL
        THEN 'virtual transaction ' || waiting_lock.virtualxid
      ELSE waiting_lock.locktype
    END,
    'blockedSeconds', CASE
      WHEN blocked.query_start IS NOT NULL
        THEN extract(epoch FROM clock_timestamp() - blocked.query_start)::double precision
      ELSE 0
    END
  ) AS item
  FROM pg_stat_activity AS blocked
  CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS blocker(blocker_pid)
  LEFT JOIN pg_stat_activity AS blocker_activity ON blocker_activity.pid = blocker.blocker_pid
  LEFT JOIN LATERAL (
    SELECT locktype, mode, relation, transactionid, virtualxid
    FROM pg_locks
    WHERE pid = blocked.pid AND NOT granted
    ORDER BY relation NULLS LAST, transactionid::text NULLS LAST
    LIMIT 1
  ) AS waiting_lock ON true
  LEFT JOIN pg_class AS waiting_relation ON waiting_relation.oid = waiting_lock.relation
  LEFT JOIN pg_namespace AS waiting_namespace ON waiting_namespace.oid = waiting_relation.relnamespace
  WHERE blocked.pid <> pg_backend_pid()
    AND blocked.application_name IS DISTINCT FROM 'hazel-monitor'
  ORDER BY blocked.query_start ASC NULLS LAST
  LIMIT 12
)
SELECT jsonb_build_object(
  'schema', 1,
  'kind', 'details',
  'collectedAtMs', floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint,
  'activity', coalesce((SELECT jsonb_agg(item) FROM activity_rows), '[]'::jsonb),
  'relations', coalesce((SELECT jsonb_agg(item) FROM relation_rows), '[]'::jsonb),
  'blocking', coalesce((SELECT jsonb_agg(item) FROM blocking_rows), '[]'::jsonb),
  'vacuum', '[]'::jsonb
);
