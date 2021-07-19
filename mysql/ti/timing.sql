/*[[Show TiDB metrics time modules within 10 minutes. Usage: @@NAME [<instance> | {-m <metric_name>}]  [-a]
    -m <metric_name>: The <metric_name> that can be found as table of metrics_schema.<metric_name>_*
    -a              : Use metrics_summary as the source table 
    --[[
        &filter: default={value>0 and (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))}
        &grp   : default={--}     a={}
        &grp1  : default={--}     m={}
        &grp2  : default={}       a={--}
        &c1    : default={&grp}   m={} 
        &c2    : default={}       m={&grp}
        &c3    : default={}       a={&grp1}
        &c4    : default={}       m={&grp2}
    --]]
]]*/

COL "time,duration,avg_time,Avg|Time,Avg|Dur,0 Min|Time,1 Min|Time,2 Min|Time,3 Min|Time,4 Min|Time,5 Min|Time,6 Min|Time,7 Min|Time,8 Min|Time,9 Min|Time" FOR usmhd2
COL "count,Avg|Count,0 Min|Count,1 Min|Count,2 Min|Count,3 Min|Count,4 Min|Count,5 Min|Count,6 Min|Count,7 Min|Count,8 Min|Count,9 Min|Count" FOR TMB2
/* --Query to build the "UNION ALL" block
WITH r AS
 (SELECT REPLACE(A.table_name, '_' || substring_index(table_name, '_', -2), '') t
  FROM   information_schema.METRICS_TABLES A
  JOIN   (SELECT DISTINCT table_name
         FROM   information_schema.COLUMNS
         WHERE  UPPER(COLUMN_NAME) = 'INSTANCE'
         AND    UPPER(TABLE_SCHEMA) = 'METRICS_SCHEMA') B
  USING  (table_name)
  WHERE  substring_index(table_name, '_', -2) IN('total_time','total_count')
  GROUP  BY t
  HAVING COUNT(1) = 2
  AND    t NOT IN('tidb_connection_idle')
  ORDER  BY 1)
SELECT 'select '''||t||''', time, instance, ''t'',value from metrics_schema.'||t||'_total_time where &filter union all' FROM r
UNION ALL
SELECT 'select '''||t|| ''', time, instance, ''c'',value from metrics_schema.' || t || '_total_count where &filter union all'
FROM   r;
*/

&c1./*

WITH R AS(
    select 'etcd_wal_fsync' n, time, instance, 't' t,value v from metrics_schema.etcd_wal_fsync_total_time where &filter union all
    select 'tidb_batch_client_wait', time, instance, 't',value from metrics_schema.tidb_batch_client_wait_total_time where &filter union all
    select 'pd_client_cmd', time, instance, 't',value from metrics_schema.pd_client_cmd_total_time where &filter union all
    select 'pd_grpc_completed_commands', time, instance, 't',value from metrics_schema.pd_grpc_completed_commands_total_time where &filter union all
    select 'pd_handle_transactions', time, instance, 't',value from metrics_schema.pd_handle_transactions_total_time where &filter union all
    select 'pd_peer_round_trip', time, instance, 't',value from metrics_schema.pd_peer_round_trip_total_time where &filter union all
    select 'pd_request_rpc', time, instance, 't',value from metrics_schema.pd_request_rpc_total_time where &filter union all
    select 'pd_start_tso_wait', time, instance, 't',value from metrics_schema.pd_start_tso_wait_total_time where &filter union all
    select 'pd_tso_rpc', time, instance, 't',value from metrics_schema.pd_tso_rpc_total_time where &filter union all
    select 'pd_tso_wait', time, instance, 't',value from metrics_schema.pd_tso_wait_total_time where &filter union all
    select 'tidb_auto_id_request', time, instance, 't',value from metrics_schema.tidb_auto_id_request_total_time where &filter union all
    select 'tidb_batch_client_unavailable', time, instance, 't',value from metrics_schema.tidb_batch_client_unavailable_total_time where &filter union all
    select 'tidb_batch_client_wait_conn', time, instance, 't',value from metrics_schema.tidb_batch_client_wait_conn_total_time where &filter union all
    select 'tidb_compile', time, instance, 't',value from metrics_schema.tidb_compile_total_time where &filter union all
    select 'tidb_cop', time, instance, 't',value from metrics_schema.tidb_cop_total_time where &filter union all
    select 'tidb_ddl', time, instance, 't',value from metrics_schema.tidb_ddl_total_time where &filter union all
    select 'tidb_ddl_batch_add_index', time, instance, 't',value from metrics_schema.tidb_ddl_batch_add_index_total_time where &filter union all
    select 'tidb_ddl_deploy_syncer', time, instance, 't',value from metrics_schema.tidb_ddl_deploy_syncer_total_time where &filter union all
    select 'tidb_ddl_update_self_version', time, instance, 't',value from metrics_schema.tidb_ddl_update_self_version_total_time where &filter union all
    select 'tidb_ddl_worker', time, instance, 't',value from metrics_schema.tidb_ddl_worker_total_time where &filter union all
    select 'tidb_distsql_execution', time, instance, 't',value from metrics_schema.tidb_distsql_execution_total_time where &filter union all
    select 'tidb_execute', time, instance, 't',value from metrics_schema.tidb_execute_total_time where &filter union all
    select 'tidb_gc', time, instance, 't',value from metrics_schema.tidb_gc_total_time where &filter union all
    select 'tidb_gc_push_task', time, instance, 't',value from metrics_schema.tidb_gc_push_task_total_time where &filter union all
    select 'tidb_get_token', time, instance, 't',value from metrics_schema.tidb_get_token_total_time where &filter union all
    select 'tidb_kv_backoff', time, instance, 't',value from metrics_schema.tidb_kv_backoff_total_time where &filter union all
    select 'tidb_kv_request', time, instance, 't',value from metrics_schema.tidb_kv_request_total_time where &filter union all
    select 'tidb_load_schema', time, instance, 't',value from metrics_schema.tidb_load_schema_total_time where &filter union all
    select 'tidb_meta_operation', time, instance, 't',value from metrics_schema.tidb_meta_operation_total_time where &filter union all
    select 'tidb_new_etcd_session', time, instance, 't',value from metrics_schema.tidb_new_etcd_session_total_time where &filter union all
    select 'tidb_owner_handle_syncer', time, instance, 't',value from metrics_schema.tidb_owner_handle_syncer_total_time where &filter union all
    select 'tidb_parse', time, instance, 't',value from metrics_schema.tidb_parse_total_time where &filter union all
    select 'tidb_query', time, instance, 't',value from metrics_schema.tidb_query_total_time where &filter union all
    select 'tidb_slow_query', time, instance, 't',value from metrics_schema.tidb_slow_query_total_time where &filter union all
    select 'tidb_slow_query_cop_process', time, instance, 't',value from metrics_schema.tidb_slow_query_cop_process_total_time where &filter union all
    select 'tidb_slow_query_cop_wait', time, instance, 't',value from metrics_schema.tidb_slow_query_cop_wait_total_time where &filter union all
    select 'tidb_statistics_auto_analyze', time, instance, 't',value from metrics_schema.tidb_statistics_auto_analyze_total_time where &filter union all
    select 'tidb_transaction', time, instance, 't',value from metrics_schema.tidb_transaction_total_time where &filter union all
    select 'tidb_transaction_local_latch_wait', time, instance, 't',value from metrics_schema.tidb_transaction_local_latch_wait_total_time where &filter union all
    select 'tidb_txn_cmd', time, instance, 't',value from metrics_schema.tidb_txn_cmd_total_time where &filter union all
    select 'tikv_backup', time, instance, 't',value from metrics_schema.tikv_backup_total_time where &filter union all
    select 'tikv_backup_range', time, instance, 't',value from metrics_schema.tikv_backup_range_total_time where &filter union all
    select 'tikv_check_split', time, instance, 't',value from metrics_schema.tikv_check_split_total_time where &filter union all
    select 'tikv_cop_handle', time, instance, 't',value from metrics_schema.tikv_cop_handle_total_time where &filter union all
    select 'tikv_cop_request', time, instance, 't',value from metrics_schema.tikv_cop_request_total_time where &filter union all
    select 'tikv_cop_wait', time, instance, 't',value from metrics_schema.tikv_cop_wait_total_time where &filter union all
    select 'tikv_gc_tasks', time, instance, 't',value from metrics_schema.tikv_gc_tasks_total_time where &filter union all
    select 'tikv_grpc_message', time, instance, 't',value from metrics_schema.tikv_grpc_message_total_time where &filter union all
    select 'tikv_handle_snapshot', time, instance, 't',value from metrics_schema.tikv_handle_snapshot_total_time where &filter union all
    select 'tikv_ingest_sst', time, instance, 't',value from metrics_schema.tikv_ingest_sst_total_time where &filter union all
    select 'tikv_lock_manager_deadlock_detect', time, instance, 't',value from metrics_schema.tikv_lock_manager_deadlock_detect_total_time where &filter union all
    select 'tikv_lock_manager_waiter_lifetime', time, instance, 't',value from metrics_schema.tikv_lock_manager_waiter_lifetime_total_time where &filter union all
    select 'tikv_pd_request', time, instance, 't',value from metrics_schema.tikv_pd_request_total_time where &filter union all
    select 'tikv_raft_store_events', time, instance, 't',value from metrics_schema.tikv_raft_store_events_total_time where &filter union all
    select 'tikv_raftstore_append_log', time, instance, 't',value from metrics_schema.tikv_raftstore_append_log_total_time where &filter union all
    select 'tikv_raftstore_apply_log', time, instance, 't',value from metrics_schema.tikv_raftstore_apply_log_total_time where &filter union all
    select 'tikv_raftstore_apply_wait', time, instance, 't',value from metrics_schema.tikv_raftstore_apply_wait_total_time where &filter union all
    select 'tikv_raftstore_commit_log', time, instance, 't',value from metrics_schema.tikv_raftstore_commit_log_total_time where &filter union all
    select 'tikv_raftstore_process', time, instance, 't',value from metrics_schema.tikv_raftstore_process_total_time where &filter union all
    select 'tikv_raftstore_propose_wait', time, instance, 't',value from metrics_schema.tikv_raftstore_propose_wait_total_time where &filter union all
    select 'tikv_scheduler_command', time, instance, 't',value from metrics_schema.tikv_scheduler_command_total_time where &filter union all
    select 'tikv_scheduler_latch_wait', time, instance, 't',value from metrics_schema.tikv_scheduler_latch_wait_total_time where &filter union all
    select 'tikv_scheduler_processing_read', time, instance, 't',value from metrics_schema.tikv_scheduler_processing_read_total_time where &filter union all
    select 'tikv_send_snapshot', time, instance, 't',value from metrics_schema.tikv_send_snapshot_total_time where &filter union all
    select 'tikv_storage_async_request', time, instance, 't',value from metrics_schema.tikv_storage_async_request_total_time where &filter
    union all
    select 'tidb_batch_client_wait', time, instance, 'c',value from metrics_schema.tidb_batch_client_wait_total_count where &filter union all
    select 'etcd_wal_fsync', time, instance, 'c',value from metrics_schema.etcd_wal_fsync_total_count where &filter union all
    select 'pd_client_cmd', time, instance, 'c',value from metrics_schema.pd_client_cmd_total_count where &filter union all
    select 'pd_grpc_completed_commands', time, instance, 'c',value from metrics_schema.pd_grpc_completed_commands_total_count where &filter union all
    select 'pd_handle_transactions', time, instance, 'c',value from metrics_schema.pd_handle_transactions_total_count where &filter union all
    select 'pd_peer_round_trip', time, instance, 'c',value from metrics_schema.pd_peer_round_trip_total_count where &filter union all
    select 'pd_request_rpc', time, instance, 'c',value from metrics_schema.pd_request_rpc_total_count where &filter union all
    select 'pd_start_tso_wait', time, instance, 'c',value from metrics_schema.pd_start_tso_wait_total_count where &filter union all
    select 'pd_tso_rpc', time, instance, 'c',value from metrics_schema.pd_tso_rpc_total_count where &filter union all
    select 'pd_tso_wait', time, instance, 'c',value from metrics_schema.pd_tso_wait_total_count where &filter union all
    select 'tidb_auto_id_request', time, instance, 'c',value from metrics_schema.tidb_auto_id_request_total_count where &filter union all
    select 'tidb_batch_client_unavailable', time, instance, 'c',value from metrics_schema.tidb_batch_client_unavailable_total_count where &filter union all
    select 'tidb_batch_client_wait_conn', time, instance, 'c',value from metrics_schema.tidb_batch_client_wait_conn_total_count where &filter union all
    select 'tidb_compile', time, instance, 'c',value from metrics_schema.tidb_compile_total_count where &filter union all
    select 'tidb_cop', time, instance, 'c',value from metrics_schema.tidb_cop_total_count where &filter union all
    select 'tidb_ddl', time, instance, 'c',value from metrics_schema.tidb_ddl_total_count where &filter union all
    select 'tidb_ddl_batch_add_index', time, instance, 'c',value from metrics_schema.tidb_ddl_batch_add_index_total_count where &filter union all
    select 'tidb_ddl_deploy_syncer', time, instance, 'c',value from metrics_schema.tidb_ddl_deploy_syncer_total_count where &filter union all
    select 'tidb_ddl_update_self_version', time, instance, 'c',value from metrics_schema.tidb_ddl_update_self_version_total_count where &filter union all
    select 'tidb_ddl_worker', time, instance, 'c',value from metrics_schema.tidb_ddl_worker_total_count where &filter union all
    select 'tidb_distsql_execution', time, instance, 'c',value from metrics_schema.tidb_distsql_execution_total_count where &filter union all
    select 'tidb_execute', time, instance, 'c',value from metrics_schema.tidb_execute_total_count where &filter union all
    select 'tidb_gc', time, instance, 'c',value from metrics_schema.tidb_gc_total_count where &filter union all
    select 'tidb_gc_push_task', time, instance, 'c',value from metrics_schema.tidb_gc_push_task_total_count where &filter union all
    select 'tidb_get_token', time, instance, 'c',value from metrics_schema.tidb_get_token_total_count where &filter union all
    select 'tidb_kv_backoff', time, instance, 'c',value from metrics_schema.tidb_kv_backoff_total_count where &filter union all
    select 'tidb_kv_request', time, instance, 'c',value from metrics_schema.tidb_kv_request_total_count where &filter union all
    select 'tidb_load_schema', time, instance, 'c',value from metrics_schema.tidb_load_schema_total_count where &filter union all
    select 'tidb_meta_operation', time, instance, 'c',value from metrics_schema.tidb_meta_operation_total_count where &filter union all
    select 'tidb_new_etcd_session', time, instance, 'c',value from metrics_schema.tidb_new_etcd_session_total_count where &filter union all
    select 'tidb_owner_handle_syncer', time, instance, 'c',value from metrics_schema.tidb_owner_handle_syncer_total_count where &filter union all
    select 'tidb_parse', time, instance, 'c',value from metrics_schema.tidb_parse_total_count where &filter union all
    select 'tidb_query', time, instance, 'c',value from metrics_schema.tidb_query_total_count where &filter union all
    select 'tidb_slow_query', time, instance, 'c',value from metrics_schema.tidb_slow_query_total_count where &filter union all
    select 'tidb_slow_query_cop_process', time, instance, 'c',value from metrics_schema.tidb_slow_query_cop_process_total_count where &filter union all
    select 'tidb_slow_query_cop_wait', time, instance, 'c',value from metrics_schema.tidb_slow_query_cop_wait_total_count where &filter union all
    select 'tidb_statistics_auto_analyze', time, instance, 'c',value from metrics_schema.tidb_statistics_auto_analyze_total_count where &filter union all
    select 'tidb_transaction', time, instance, 'c',value from metrics_schema.tidb_transaction_total_count where &filter union all
    select 'tidb_transaction_local_latch_wait', time, instance, 'c',value from metrics_schema.tidb_transaction_local_latch_wait_total_count where &filter union all
    select 'tidb_txn_cmd', time, instance, 'c',value from metrics_schema.tidb_txn_cmd_total_count where &filter union all
    select 'tikv_backup', time, instance, 'c',value from metrics_schema.tikv_backup_total_count where &filter union all
    select 'tikv_backup_range', time, instance, 'c',value from metrics_schema.tikv_backup_range_total_count where &filter union all
    select 'tikv_check_split', time, instance, 'c',value from metrics_schema.tikv_check_split_total_count where &filter union all
    select 'tikv_cop_handle', time, instance, 'c',value from metrics_schema.tikv_cop_handle_total_count where &filter union all
    select 'tikv_cop_request', time, instance, 'c',value from metrics_schema.tikv_cop_request_total_count where &filter union all
    select 'tikv_cop_wait', time, instance, 'c',value from metrics_schema.tikv_cop_wait_total_count where &filter union all
    select 'tikv_gc_tasks', time, instance, 'c',value from metrics_schema.tikv_gc_tasks_total_count where &filter union all
    select 'tikv_grpc_message', time, instance, 'c',value from metrics_schema.tikv_grpc_message_total_count where &filter union all
    select 'tikv_handle_snapshot', time, instance, 'c',value from metrics_schema.tikv_handle_snapshot_total_count where &filter union all
    select 'tikv_ingest_sst', time, instance, 'c',value from metrics_schema.tikv_ingest_sst_total_count where &filter union all
    select 'tikv_lock_manager_deadlock_detect', time, instance, 'c',value from metrics_schema.tikv_lock_manager_deadlock_detect_total_count where &filter union all
    select 'tikv_lock_manager_waiter_lifetime', time, instance, 'c',value from metrics_schema.tikv_lock_manager_waiter_lifetime_total_count where &filter union all
    select 'tikv_pd_request', time, instance, 'c',value from metrics_schema.tikv_pd_request_total_count where &filter union all
    select 'tikv_raft_store_events', time, instance, 'c',value from metrics_schema.tikv_raft_store_events_total_count where &filter union all
    select 'tikv_raftstore_append_log', time, instance, 'c',value from metrics_schema.tikv_raftstore_append_log_total_count where &filter union all
    select 'tikv_raftstore_apply_log', time, instance, 'c',value from metrics_schema.tikv_raftstore_apply_log_total_count where &filter union all
    select 'tikv_raftstore_apply_wait', time, instance, 'c',value from metrics_schema.tikv_raftstore_apply_wait_total_count where &filter union all
    select 'tikv_raftstore_commit_log', time, instance, 'c',value from metrics_schema.tikv_raftstore_commit_log_total_count where &filter union all
    select 'tikv_raftstore_process', time, instance, 'c',value from metrics_schema.tikv_raftstore_process_total_count where &filter union all
    select 'tikv_raftstore_propose_wait', time, instance, 'c',value from metrics_schema.tikv_raftstore_propose_wait_total_count where &filter union all
    select 'tikv_scheduler_command', time, instance, 'c',value from metrics_schema.tikv_scheduler_command_total_count where &filter union all
    select 'tikv_scheduler_latch_wait', time, instance, 'c',value from metrics_schema.tikv_scheduler_latch_wait_total_count where &filter union all
    select 'tikv_scheduler_processing_read', time, instance, 'c',value from metrics_schema.tikv_scheduler_processing_read_total_count where &filter union all
    select 'tikv_send_snapshot', time, instance, 'c',value from metrics_schema.tikv_send_snapshot_total_count where &filter union all
    select 'tikv_storage_async_request', time, instance, 'c',value from metrics_schema.tikv_storage_async_request_total_count where &filter
)
SELECT n `Unit: per second|Metric Name`,
       '|' `|`,
       MAX(inst) `Inst|Count`,
       AVG(if(t='t',v,NULL)) `Avg|Time`,
       AVG(if(t='c',v,NULL)) `Avg|Count`,
       Round(AVG(if(t='t',v,NULL))/AVG(if(t='c',v,NULL)),2) `Avg|Dur`,
       '|'  `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(now(),'%m%d-%H:%i'),v,0)) `0 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(now(),'%m%d-%H:%i'),v,0)) `0 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -1 minute),'%m%d-%H:%i'),v,0)) `1 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -1 minute),'%m%d-%H:%i'),v,0)) `1 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -2 minute),'%m%d-%H:%i'),v,0)) `2 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -2 minute),'%m%d-%H:%i'),v,0)) `2 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -3 minute),'%m%d-%H:%i'),v,0)) `3 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -3 minute),'%m%d-%H:%i'),v,0)) `3 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -4 minute),'%m%d-%H:%i'),v,0)) `4 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -4 minute),'%m%d-%H:%i'),v,0)) `4 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -5 minute),'%m%d-%H:%i'),v,0)) `5 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -5 minute),'%m%d-%H:%i'),v,0)) `5 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -6 minute),'%m%d-%H:%i'),v,0)) `6 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -6 minute),'%m%d-%H:%i'),v,0)) `6 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -7 minute),'%m%d-%H:%i'),v,0)) `7 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -7 minute),'%m%d-%H:%i'),v,0)) `7 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -8 minute),'%m%d-%H:%i'),v,0)) `8 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -8 minute),'%m%d-%H:%i'),v,0)) `8 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=DATE_FORMAT(date_add(now(), interval -9 minute),'%m%d-%H:%i'),v,0)) `9 Min|Time`,
       MAX(if(t='c' AND ts=DATE_FORMAT(date_add(now(), interval -9 minute),'%m%d-%H:%i'),v,0)) `9 Min|Count`
FROM (
    SELECT n,
           DATE_FORMAT(time,'%m%d-%H:%i') ts,
           t,
           count(distinct instance) inst,
           round(SUM(v)/60*CASE WHEN t='t' AND n='tidb_batch_client_wait' THEN 1e-3 WHEN t='t' and n!='tidb_get_token' THEN 1E6 ELSE 1 END,2) v
    FROM   r
    GROUP  BY n,ts,t) A
GROUP BY n
ORDER BY `Avg|Time` DESC;

&c1.*/ 

&c2./*

col qry new_value qry noprint
col minute break -
env colsep |

SELECT concat('select A.*,time/count avg_time from (\n',group_concat(qry ORDER BY n separator '\n'),'\n) A order by Minute desc,time desc') qry
FROM (
SELECT concat(IF(n = 'A1', '  SELECT * FROM ', '  JOIN '),
              qry,
              ' ',
              n,
              IF(n = 'A1', '', CONCAT(' USING(', concat_ws(',', 'Minute', cols), ')'))) qry,n
FROM   (SELECT concat_ws(' ','(SELECT',
                      concat_ws(',',
                                'DATE_FORMAT(time,''%m-%d %H:%i'') Minute',
                                cols,
                                IF(unit = 'time','Count(1) Instances',null),
                                CONCAT(IF(unit = 'duration', 'AVG(value)', 'SUM(value)/60'),
                                       CASE WHEN unit = 'count' OR table_name LIKE 'tidb_get_token%' THEN ' '
                                            WHEN unit!= 'count' AND table_name like 'tidb_batch_client_wait%' THEN '*1e-3 '
                                            ELSE '*1e6 '
                                       END,
                                       unit)),
                      'from',
                      'metrics_schema.',
                      table_name,
                      'where value>0',
                      concat_ws(',', 'group by Minute', cols),
                      ')') qry,
               CASE unit WHEN 'time' THEN 'A1' WHEN 'count' THEN 'A2' ELSE 'A3' END n,
               cols
        FROM   information_schema.METRICS_TABLES A
        JOIN   (SELECT table_name,
                      substring_index(lower(table_name), '_', -1) unit,
                      MAX(CASE WHEN lower(column_name) in ('type','sql_type') THEN lower(column_name) END) cols
               FROM   information_schema.COLUMNS
               WHERE  lower(table_name) LIKE lower('&V1%')
               GROUP  BY table_name) B
        USING  (table_name)
        WHERE  lower(table_name) regexp lower('&V1(_total_time|_total_count|_duration)$')) C
ORDER BY n) d;
ECHO =============================================================================
ECHO Querying tables metrics_schema.&V1. ...
ECHO =============================================================================
&qry;

&c2.*/

&c3./*
SELECT n `Metric Name`,
       MAX(IF(t='time',s,0)) `Time`,
       MAX(IF(t='count',s,0)) `Count`,
       MAX(IF(t='duration',s,0)) `Duration`,
       MAX(IF(t='time',s,0))/NULLIF(MAX(IF(t='count',s,NULL)),0) `avg_time`,
       MAX(IF(t='count',c,NULL)) COMMENT
FROM (
    SELECT lower(REPLACE(REPLACE(metrics_name, concat('_', substring_index(metrics_name, '_', -1)), ''), '_total', '')) n,
           substring_index(metrics_name, '_', -1) t,
           sum_value*CASE WHEN substring_index(metrics_name, '_', -1) IN('duration','time') THEN 
                          CASE WHEN metrics_name LIKE 'tidb_batch_client_wait%' THEN 1e-3 
                               WHEN metrics_name LIKE 'tidb_get_token%' THEN 1
                               ELSE 1e6
                          END
                          ELSE 1
                     END s,
           COMMENT c
    FROM   information_schema.metrics_summary
    WHERE  SUM_VALUE > 0
    AND    lower(metrics_name) NOT LIKE 'tidb_connection_idle%'
    AND    lower(metrics_name) regexp '(_total_count|_total_time|_duration)$') A
GROUP BY n
HAVING `Time`>0 AND `Count`>0
ORDER BY `Time` DESC;

&c3.*/

&c4./*

SELECT label,
       count(DISTINCT inst) `Instances`,
       SUM(IF(t='time',s,0)) `Time`,
       SUM(IF(t='count',s,0)) `Count`,
       AVG(IF(t='duration',s,NULL)) `Duration`,
       SUM(IF(t='time',s,0))/NULLIF(SUM(IF(t='count',s,NULL)),0) `Avg_Time`,
       MAX(IF(t='count',c,NULL)) COMMENT
FROM (
    SELECT REPLACE(REPLACE(metrics_name, concat('_', substring_index(metrics_name, '_', -1)), ''), '_total', '') n,
           label,
           substring_index(metrics_name, '_', -1) t,
           sum_value*CASE WHEN substring_index(metrics_name, '_', -1) IN('duration','time') THEN 
                          CASE WHEN metrics_name LIKE 'tidb_batch_client_wait%' THEN 1e-3 
                               WHEN metrics_name LIKE 'tidb_get_token%' THEN 1
                               ELSE 1e6
                          END
                          ELSE 1
                     END s,
           COMMENT c,
           Instance inst
    FROM   information_schema.metrics_summary_by_label
    WHERE  SUM_VALUE > 0
    AND    lower(metrics_name) regexp lower('&V1(_total_time|_total_count|_duration)$')) A
GROUP BY label
HAVING `Time`>0 AND `Count`>0
ORDER BY `Time` DESC;

&c4.*/