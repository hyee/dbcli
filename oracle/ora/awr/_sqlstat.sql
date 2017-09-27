SET FEED OFF VERIFY OFF
VAR awr$sqlstat VARCHAR2;

BEGIN
    :awr$sqlstat:=q'[
       (SELECT --+merge leading(s) use_hash(s h) no_expand
               h.*,begin_interval_time,end_interval_time,
               begin_interval_time + 0 begin_time,
               end_interval_time + 0 end_time,
               decode(force_matching_signature, 0, sql_id, to_char(force_matching_signature)) signature,
               sign(elapsed_time_delta) delta_flag,
               decode(elapsed_time_delta, 0, fetches_total, fetches_delta) fetches,
               decode(elapsed_time_delta, 0, end_of_fetch_count_total, end_of_fetch_count_delta) end_of_fetch_count,
               decode(elapsed_time_delta, 0, sorts_total, sorts_delta) sorts,
               decode(elapsed_time_delta, 0, executions_total, executions_delta) executions,
               decode(elapsed_time_delta, 0, px_servers_execs_total, px_servers_execs_delta) px_servers_execs,
               decode(elapsed_time_delta, 0, loads_total, loads_delta) loads,
               decode(elapsed_time_delta, 0, invalidations_total, invalidations_delta) invalidations,
               decode(elapsed_time_delta, 0, parse_calls_total, parse_calls_delta) parse_calls,
               decode(elapsed_time_delta, 0, disk_reads_total, disk_reads_delta)*(select value from v$parameter where name='db_block_size') disk_reads,
               decode(elapsed_time_delta, 0, buffer_gets_total, buffer_gets_delta)*(select value from v$parameter where name='db_block_size') buffer_gets,
               decode(elapsed_time_delta, 0, direct_writes_total, direct_writes_delta)*(select value from v$parameter where name='db_block_size') direct_writes,
               decode(elapsed_time_delta, 0, rows_processed_total, rows_processed_delta) rows_processed,
               decode(elapsed_time_delta, 0, elapsed_time_total, elapsed_time_delta)*1e-6 elapsed_time,
               decode(elapsed_time_delta, 0, cpu_time_total, cpu_time_delta)*1e-6 cpu_time,
               decode(elapsed_time_delta, 0, iowait_total, iowait_delta)*1e-6 iowait,
               decode(elapsed_time_delta, 0, clwait_total, clwait_delta)*1e-6 clwait,
               decode(elapsed_time_delta, 0, apwait_total, apwait_delta)*1e-6 apwait,
               decode(elapsed_time_delta, 0, ccwait_total, ccwait_delta)*1e-6 ccwait,
               decode(elapsed_time_delta, 0, plsexec_time_total, plsexec_time_delta)*1e-6 plsexec_time,
               decode(elapsed_time_delta, 0, javexec_time_total, javexec_time_delta)*1e-6 javexec_time
        FROM   dba_hist_sqlstat h, dba_hist_snapshot s
        WHERE  greatest(h.elapsed_time_delta, elapsed_time_total) > 0
        AND    s.snap_id = h.snap_id
        AND    s.dbid = h.dbid
        AND    s.instance_number = h.instance_number )]';
END;
/
SET FEED BACK VERIFY BACK;