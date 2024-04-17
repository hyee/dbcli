/*[[Show locks
    Ref: https://github.com/pgexperts/pgx_scripts/blob/master/locks/log_locks.sh
]]*/
env feed off

WITH table_locks AS
 (SELECT pid,
         relation::INT AS relation,
         (relation::regclass)::text AS locked_relation,
         MODE,
         page || ':' || tuple AS locked_tuple,
         locktype,
         coalesce(transactionid::text, virtualxid) AS lxid,
         granted
  FROM   pg_locks
  JOIN   pg_database
  ON     pg_locks.database = pg_database.oid
  WHERE  relation IS NOT NULL
  AND    pg_database.datname = current_database()
  AND    locktype IN ('relation', 'extend', 'page', 'tuple')),
lock_granted AS
 (SELECT * FROM table_locks WHERE granted),
lock_waiting AS
 (SELECT * FROM table_locks WHERE NOT granted)
SELECT now() AS lock_ts,
       current_database() AS dbname,
       lock_waiting.pid AS waiting_pid,
       lock_waiting.lxid AS wait_xid,
       lock_granted.pid AS locked_pid,
       lock_granted.lxid AS locked_xid,
       lock_granted.locked_relation,
       lock_waiting.locktype AS waiting_type,
       lock_waiting.mode AS waiting_mode,
       lock_waiting.locked_tuple AS tuple_waiting,
       lock_granted.locktype AS locked_type,
       lock_granted.mode AS lock_mode,
       lock_granted.locked_tuple AS tuple_locked,
       waiting_proc.application_name AS waiting_app,
       waiting_proc.client_addr AS waiting_addr,
       waiting_proc.xact_start AS waiting_xact_start,
       waiting_proc.query_start AS waiting_query_start,
       waiting_proc.state_change AS waiting_start,
       waiting_proc.query AS waiting_query,
       locked_proc.application_name AS locked_app,
       locked_proc.client_addr AS locked_addr,
       locked_proc.xact_start AS locked_xact_start,
       locked_proc.query_start AS locked_query_start,
       locked_proc.state AS locked_state,
       locked_proc.state_change AS locked_state_start,
       locked_proc.query AS locked_last_query
FROM   lock_waiting
JOIN   pg_stat_activity AS waiting_proc
ON     lock_waiting.pid = waiting_proc.pid
LEFT   OUTER JOIN lock_granted
ON     lock_waiting.relation = lock_granted.relation
LEFT   OUTER JOIN pg_stat_activity AS locked_proc
ON     lock_granted.pid = locked_proc.pid
ORDER  BY locked_pid, locked_relation;

WITH mylocks AS
 (SELECT * FROM pg_locks WHERE locktype IN ('transactionid', 'virtualxid')),
table_locks AS
 (SELECT pid,
         (relation::regclass)::TEXT AS lockobj,
         CASE
             WHEN page IS NOT NULL AND tuple IS NOT NULL THEN
              MODE || ' on ' || page::text || ':' || tuple::text
             ELSE
              MODE
         END AS lock_mode,
         locktype
  FROM   mylocks
  JOIN   pg_database
  ON     mylocks.database = pg_database.oid
  WHERE  relation IS NOT NULL
  AND    pg_database.datname = current_database()
  ORDER  BY lockobj),
locked_list AS
 (SELECT pid,
         array_agg(lockobj) AS lock_relations,
         array_agg(lock_mode) AS lock_modes,
         array_agg(locktype) AS lock_types
  FROM   table_locks
  GROUP  BY pid),
txn_locks AS
 (SELECT pid, transactionid::text AS lxid, granted
  FROM   mylocks
  WHERE  locktype = 'transactionid'
  UNION ALL
  SELECT pid, virtualxid::text AS lxid, granted
  FROM   mylocks
  WHERE  locktype = 'virtualxid'),
txn_granted AS
 (SELECT pid, lxid FROM txn_locks WHERE granted),
txn_waiting AS
 (SELECT pid, lxid FROM txn_locks WHERE NOT granted)
SELECT now() AS lock_ts,
       current_database() AS dbname,
       txn_waiting.pid AS waiting_pid,
       txn_waiting.lxid AS wait_xid,
       txn_granted.pid AS locked_pid,
       waiting_proc.application_name AS waiting_app,
       waiting_proc.client_addr AS waiting_addr,
       waiting_proc.xact_start AS waiting_xact_start,
       waiting_proc.query_start AS waiting_query_start,
       waiting_proc.state_change AS waiting_start,
       waiting_proc.query AS waiting_query,
       locked_proc.application_name AS locked_app,
       locked_proc.client_addr AS locked_addr,
       locked_proc.xact_start AS locked_xact_start,
       locked_proc.query_start AS locked_query_start,
       locked_proc.state AS locked_state,
       locked_proc.state_change AS locked_state_start,
       locked_proc.query AS locked_last_query,
       waiting_locks.lock_relations AS waiting_relations,
       waiting_locks.lock_modes AS waiting_modes,
       waiting_locks.lock_types AS waiting_lock_types,
       locked_locks.lock_relations AS locked_relations,
       locked_locks.lock_modes AS locked_modes,
       locked_locks.lock_types AS locked_lock_types
FROM   txn_waiting
JOIN   pg_stat_activity AS waiting_proc
ON     txn_waiting.pid = waiting_proc.pid
LEFT   OUTER JOIN txn_granted
ON     txn_waiting.lxid = txn_granted.lxid
LEFT   OUTER JOIN pg_stat_activity AS locked_proc
ON     txn_granted.pid = locked_proc.pid
LEFT   OUTER JOIN locked_list AS waiting_locks
ON     txn_waiting.pid = waiting_locks.pid
LEFT   OUTER JOIN locked_list AS locked_locks
ON     txn_granted.pid = locked_locks.pid;
