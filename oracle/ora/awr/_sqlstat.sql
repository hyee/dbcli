
SET FEED OFF VERIFY OFF
VAR awr$sqlstat VARCHAR2;
DECLARE
    sq VARCHAR2(8000);
BEGIN
    sq:=q'[
       (SELECT --+merge leading(s) use_hash(s h) no_expand
               h.*,begin_interval_time,end_interval_time,
               begin_interval_time + 0 begin_time,
               end_interval_time + 0 end_time,
               decode(force_matching_signature, 0, sql_id, to_char(force_matching_signature)) signature,
               decode(delta_flag, 0, fetches_total, fetches_delta) fetches,
               decode(delta_flag, 0, end_of_fetch_count_total, end_of_fetch_count_delta) end_of_fetch_count,
               decode(delta_flag, 0, sorts_total, sorts_delta) sorts,
               decode(delta_flag, 0, executions_total, executions_delta) executions,
               decode(delta_flag, 0, px_servers_execs_total, px_servers_execs_delta) px_servers_execs,
               decode(delta_flag, 0, loads_total, loads_delta) loads,
               decode(delta_flag, 0, invalidations_total, invalidations_delta) invalidations,
               decode(delta_flag, 0, parse_calls_total, parse_calls_delta) parse_calls,
               decode(delta_flag, 0, disk_reads_total, disk_reads_delta)*(select value from v$parameter where name='db_block_size') disk_reads,
               decode(delta_flag, 0, buffer_gets_total, buffer_gets_delta)*(select value from v$parameter where name='db_block_size') buffer_gets,
               decode(delta_flag, 0, direct_writes_total, direct_writes_delta)*(select value from v$parameter where name='db_block_size') direct_writes,
               decode(delta_flag, 0, rows_processed_total, rows_processed_delta) rows_processed,
               decode(delta_flag, 0, elapsed_time_total, elapsed_time_delta)*1e-6 elapsed_time,
               decode(delta_flag, 0, cpu_time_total, cpu_time_delta)*1e-6 cpu_time,
               decode(delta_flag, 0, iowait_total, iowait_delta)*1e-6 iowait,
               decode(delta_flag, 0, clwait_total, clwait_delta)*1e-6 clwait,
               decode(delta_flag, 0, apwait_total, apwait_delta)*1e-6 apwait,
               decode(delta_flag, 0, ccwait_total, ccwait_delta)*1e-6 ccwait,
               decode(delta_flag, 0, plsexec_time_total, plsexec_time_delta)*1e-6 plsexec_time,
               decode(delta_flag, 0, javexec_time_total, javexec_time_delta)*1e-6 javexec_time
               @11g@
        FROM   (select h.*,sign(elapsed_time_delta) delta_flag from dba_hist_sqlstat H /*where BITAND(NVL(flag, 0), 1) = 0*/) h, dba_hist_snapshot s
        WHERE  greatest(h.elapsed_time_delta, elapsed_time_total) > 0
        AND    s.snap_id = h.snap_id
        AND    s.dbid = h.dbid
        AND    s.instance_number = h.instance_number )]';
    IF dbms_db_version.version>11 or (dbms_db_version.version>10 and dbms_db_version.release>1) THEN
        sq := replace(sq,'@11g@','
               ,decode(delta_flag, 0, physical_read_bytes_total, physical_read_bytes_delta) phyread
               ,decode(delta_flag, 0, physical_write_bytes_total, physical_write_bytes_delta) phywrite
               ,decode(delta_flag, 0, io_offload_elig_bytes_total, io_offload_elig_bytes_delta) oflin
               ,decode(delta_flag, 0, io_offload_return_bytes_total, io_offload_return_bytes_delta) oflout
               ,decode(delta_flag, 0, io_interconnect_bytes_total, io_interconnect_bytes_delta) cellio');
    ELSE
        sq := replace(sq,'@11g@',',0 phyread,null phywrite,0 oflin,0 oflout,null cellio');
    END IF;
    :awr$sqlstat := sq; 
END;
/
SET FEED BACK VERIFY BACK;