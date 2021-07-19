/*[[Show TiDB time consumings within 10 minutes
    --[[
        &filter: default={value>0 and (:V1 IS NULL OR lower(instance) LIKE lower(concat('%',:V1,'%')))}
    --]]
]]*/

COL "Avg|Time,Avg|Dur,0 Min|Time,1 Min|Time,2 Min|Time,3 Min|Time,4 Min|Time,5 Min|Time,6 Min|Time,7 Min|Time,8 Min|Time,9 Min|Time" FOR usmhd2
COL "Avg|Count,0 Min|Count,1 Min|Count,2 Min|Count,3 Min|Count,4 Min|Count,5 Min|Count,6 Min|Count,7 Min|Count,8 Min|Count,9 Min|Count" FOR TMB2

WITH R AS(
    select 'tidb_get_token' n,time,'t' t,instance,value v from metrics_schema.tidb_get_token_total_time where &filter union all
    select 'tikv_scheduler_command',time,'t',instance,value from metrics_schema.tikv_scheduler_command_total_time where &filter union all
    select 'tikv_storage_async_request',time,'t',instance,value from metrics_schema.tikv_storage_async_request_total_time where &filter union all
    select 'tidb_kv_request',time,'t',instance,value from metrics_schema.tidb_kv_request_total_time where &filter union all
    select 'tikv_grpc_message',time,'t',instance,value from metrics_schema.tikv_grpc_message_total_time where &filter union all
    select 'tikv_raftstore_commit_log',time,'t',instance,value from metrics_schema.tikv_raftstore_commit_log_total_time where &filter union all
    select 'tidb_transaction',time,'t',instance,value from metrics_schema.tidb_transaction_total_time where &filter union all
    select 'tidb_query',time,'t',instance,value from metrics_schema.tidb_query_total_time where &filter union all
    select 'tidb_execute',time,'t',instance,value from metrics_schema.tidb_execute_total_time where &filter union all
    select 'tikv_raftstore_propose_wait',time,'t',instance,value from metrics_schema.tikv_raftstore_propose_wait_total_time where &filter union all
    select 'tidb_txn_cmd',time,'t',instance,value from metrics_schema.tidb_txn_cmd_total_time where &filter union all
    select 'tikv_raftstore_process',time,'t',instance,value from metrics_schema.tikv_raftstore_process_total_time where &filter union all
    select 'tikv_raftstore_append_log',time,'t',instance,value from metrics_schema.tikv_raftstore_append_log_total_time where &filter union all
    select 'tikv_scheduler_latch_wait',time,'t',instance,value from metrics_schema.tikv_scheduler_latch_wait_total_time where &filter union all
    select 'tikv_scheduler_processing_read',time,'t',instance,value from metrics_schema.tikv_scheduler_processing_read_total_time where &filter union all
    select 'tidb_cop',time,'t',instance,value from metrics_schema.tidb_cop_total_time where &filter union all
    select 'tidb_compile',time,'t',instance,value from metrics_schema.tidb_compile_total_time where &filter union all
    select 'tikv_raftstore_apply_log',time,'t',instance,value from metrics_schema.tikv_raftstore_apply_log_total_time where &filter union all
    select 'pd_client_cmd',time,'t',instance,value from metrics_schema.pd_client_cmd_total_time where &filter union all
    select 'tidb_distsql_execution',time,'t',instance,value from metrics_schema.tidb_distsql_execution_total_time where &filter union all
    select 'tikv_cop_request',time,'t',instance,value from metrics_schema.tikv_cop_request_total_time where &filter union all
    select 'tidb_kv_backoff',time,'t',instance,value from metrics_schema.tidb_kv_backoff_total_time where &filter union all
    select 'tikv_cop_handle',time,'t',instance,value from metrics_schema.tikv_cop_handle_total_time where &filter union all
    select 'tidb_slow_query',time,'t',instance,value from metrics_schema.tidb_slow_query_total_time where &filter union all
    select 'pd_tso_wait',time,'t',instance,value from metrics_schema.pd_tso_wait_total_time where &filter union all
    select 'tikv_lock_manager_waiter_lifetime',time,'t',instance,value from metrics_schema.tikv_lock_manager_waiter_lifetime_total_time where &filter union all
    select 'pd_tso_rpc',time,'t',instance,value from metrics_schema.pd_tso_rpc_total_time where &filter union all
    select 'pd_request_rpc',time,'t',instance,value from metrics_schema.pd_request_rpc_total_time where &filter union all
    select 'tidb_statistics_auto_analyze',time,'t',instance,value from metrics_schema.tidb_statistics_auto_analyze_total_time where &filter union all
    select 'tikv_raftstore_apply_wait',time,'t',instance,value from metrics_schema.tikv_raftstore_apply_wait_total_time where &filter union all
    select 'tikv_cop_wait',time,'t',instance,value from metrics_schema.tikv_cop_wait_total_time where &filter union all
    select 'tidb_slow_query_cop_process',time,'t',instance,value from metrics_schema.tidb_slow_query_cop_process_total_time where &filter union all
    select 'pd_grpc_completed_commands',time,'t',instance,value from metrics_schema.pd_grpc_completed_commands_total_time where &filter union all
    select 'tikv_check_split',time,'t',instance,value from metrics_schema.tikv_check_split_total_time where &filter union all
    select 'tidb_meta_operation',time,'t',instance,value from metrics_schema.tidb_meta_operation_total_time where &filter union all
    select 'tidb_parse',time,'t',instance,value from metrics_schema.tidb_parse_total_time where &filter union all
    select 'tikv_pd_request',time,'t',instance,value from metrics_schema.tikv_pd_request_total_time where &filter union all
    select 'etcd_wal_fsync',time,'t',instance,value from metrics_schema.etcd_wal_fsync_total_time where &filter union all
    select 'pd_handle_transactions',time,'t',instance,value from metrics_schema.pd_handle_transactions_total_time where &filter union all
    select 'tidb_auto_id_request',time,'t',instance,value from metrics_schema.tidb_auto_id_request_total_time where &filter union all
    select 'tidb_gc',time,'t',instance,value from metrics_schema.tidb_gc_total_time where &filter union all
    select 'tidb_load_schema',time,'t',instance,value from metrics_schema.tidb_load_schema_total_time where &filter union all
    select 'tikv_raft_store_events',time,'t',instance,value from metrics_schema.tikv_raft_store_events_total_time where &filter union all
    select 'tikv_lock_manager_deadlock_detect',time,'t',instance,value from metrics_schema.tikv_lock_manager_deadlock_detect_total_time where &filter union all
    select 'tidb_gc_push_task',time,'t',instance,value from metrics_schema.tidb_gc_push_task_total_time where &filter union all
    select 'tidb_batch_client_unavailable',time,'t',instance,value from metrics_schema.tidb_batch_client_unavailable_total_time where &filter
    UNION ALL
    select 'tidb_get_token',time,'c',instance,value from metrics_schema.tidb_get_token_total_count where &filter union all
    select 'tikv_scheduler_command',time,'c',instance,value from metrics_schema.tikv_scheduler_command_total_count where &filter union all
    select 'tikv_storage_async_request',time,'c',instance,value from metrics_schema.tikv_storage_async_request_total_count where &filter union all
    select 'tidb_kv_request',time,'c',instance,value from metrics_schema.tidb_kv_request_total_count where &filter union all
    select 'tikv_grpc_message',time,'c',instance,value from metrics_schema.tikv_grpc_message_total_count where &filter union all
    select 'tikv_raftstore_commit_log',time,'c',instance,value from metrics_schema.tikv_raftstore_commit_log_total_count where &filter union all
    select 'tidb_transaction',time,'c',instance,value from metrics_schema.tidb_transaction_total_count where &filter union all
    select 'tidb_query',time,'c',instance,value from metrics_schema.tidb_query_total_count where &filter union all
    select 'tidb_execute',time,'c',instance,value from metrics_schema.tidb_execute_total_count where &filter union all
    select 'tikv_raftstore_propose_wait',time,'c',instance,value from metrics_schema.tikv_raftstore_propose_wait_total_count where &filter union all
    select 'tidb_txn_cmd',time,'c',instance,value from metrics_schema.tidb_txn_cmd_total_count where &filter union all
    select 'tikv_raftstore_process',time,'c',instance,value from metrics_schema.tikv_raftstore_process_total_count where &filter union all
    select 'tikv_raftstore_append_log',time,'c',instance,value from metrics_schema.tikv_raftstore_append_log_total_count where &filter union all
    select 'tikv_scheduler_latch_wait',time,'c',instance,value from metrics_schema.tikv_scheduler_latch_wait_total_count where &filter union all
    select 'tikv_scheduler_processing_read',time,'c',instance,value from metrics_schema.tikv_scheduler_processing_read_total_count where &filter union all
    select 'tidb_cop',time,'c',instance,value from metrics_schema.tidb_cop_total_count where &filter union all
    select 'tidb_compile',time,'c',instance,value from metrics_schema.tidb_compile_total_count where &filter union all
    select 'tikv_raftstore_apply_log',time,'c',instance,value from metrics_schema.tikv_raftstore_apply_log_total_count where &filter union all
    select 'pd_client_cmd',time,'c',instance,value from metrics_schema.pd_client_cmd_total_count where &filter union all
    select 'tidb_distsql_execution',time,'c',instance,value from metrics_schema.tidb_distsql_execution_total_count where &filter union all
    select 'tikv_cop_request',time,'c',instance,value from metrics_schema.tikv_cop_request_total_count where &filter union all
    select 'tidb_kv_backoff',time,'c',instance,value from metrics_schema.tidb_kv_backoff_total_count where &filter union all
    select 'tikv_cop_handle',time,'c',instance,value from metrics_schema.tikv_cop_handle_total_count where &filter union all
    select 'tidb_slow_query',time,'c',instance,value from metrics_schema.tidb_slow_query_total_count where &filter union all
    select 'pd_tso_wait',time,'c',instance,value from metrics_schema.pd_tso_wait_total_count where &filter union all
    select 'tikv_lock_manager_waiter_lifetime',time,'c',instance,value from metrics_schema.tikv_lock_manager_waiter_lifetime_total_count where &filter union all
    select 'pd_tso_rpc',time,'c',instance,value from metrics_schema.pd_tso_rpc_total_count where &filter union all
    select 'pd_request_rpc',time,'c',instance,value from metrics_schema.pd_request_rpc_total_count where &filter union all
    select 'tidb_statistics_auto_analyze',time,'c',instance,value from metrics_schema.tidb_statistics_auto_analyze_total_count where &filter union all
    select 'tikv_raftstore_apply_wait',time,'c',instance,value from metrics_schema.tikv_raftstore_apply_wait_total_count where &filter union all
    select 'tikv_cop_wait',time,'c',instance,value from metrics_schema.tikv_cop_wait_total_count where &filter union all
    select 'tidb_slow_query_cop_process',time,'c',instance,value from metrics_schema.tidb_slow_query_cop_process_total_count where &filter union all
    select 'pd_grpc_completed_commands',time,'c',instance,value from metrics_schema.pd_grpc_completed_commands_total_count where &filter union all
    select 'tikv_check_split',time,'c',instance,value from metrics_schema.tikv_check_split_total_count where &filter union all
    select 'tidb_meta_operation',time,'c',instance,value from metrics_schema.tidb_meta_operation_total_count where &filter union all
    select 'tidb_parse',time,'c',instance,value from metrics_schema.tidb_parse_total_count where &filter union all
    select 'tikv_pd_request',time,'c',instance,value from metrics_schema.tikv_pd_request_total_count where &filter union all
    select 'etcd_wal_fsync',time,'c',instance,value from metrics_schema.etcd_wal_fsync_total_count where &filter union all
    select 'pd_handle_transactions',time,'c',instance,value from metrics_schema.pd_handle_transactions_total_count where &filter union all
    select 'tidb_auto_id_request',time,'c',instance,value from metrics_schema.tidb_auto_id_request_total_count where &filter union all
    select 'tidb_gc',time,'c',instance,value from metrics_schema.tidb_gc_total_count where &filter union all
    select 'tidb_load_schema',time,'c',instance,value from metrics_schema.tidb_load_schema_total_count where &filter union all
    select 'tikv_raft_store_events',time,'c',instance,value from metrics_schema.tikv_raft_store_events_total_count where &filter union all
    select 'tikv_lock_manager_deadlock_detect',time,'c',instance,value from metrics_schema.tikv_lock_manager_deadlock_detect_total_count where &filter union all
    select 'tidb_gc_push_task',time,'c',instance,value from metrics_schema.tidb_gc_push_task_total_count where &filter union all
    select 'tidb_batch_client_unavailable',time,'c',instance,value from metrics_schema.tidb_batch_client_unavailable_total_count where &filter
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
           round(SUM(v)/60*if(t='t',1e6,1),2) v
    FROM   r
    GROUP  BY n,ts,t) A
GROUP BY n
ORDER BY `0 Min|Time`+`1 Min|Time`+`2 Min|Time`+`3 Min|Time` DESC;