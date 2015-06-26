-- PLAN_TABLE / ASH columns mapping
-- statement_id     'SQLD360_ASH_DATA'
-- timestamp        sample_time
-- remarks,         sql_id
-- cardinality      snap_id 
-- search_columns   dbid
-- operation        sql_plan_operation  skipped in 10g
-- options          sql_plan_options  skipped in 10g
-- object_instance  current_obj#
-- object_node      nvl(event,'ON CPU')
-- position         instance_number
-- cost             PHV
-- other_tag        wait_class
-- id               sql_plan_line_id   skipped in 10g
-- partition_id     sql_exec_id
-- cpu_cost         session_id
-- io_cost          session_serial#
-- parent_id        sample_id
-- partition_start  seq#,p1text,p1,p2text,p2,p3text,p3,current_file#,current_block#, --current_row#, --tm_delta_time, 
--                  --tm_delta_cpu_time, --tm_delta_db_time
-- partition_stop   --in_parse, --in_hard_parse, --in_sql_execution, qc_instance_id, qc_session_id, --qc_session_serial#, 
--                  -- blocking_session_status, blocking_session, blocking_session_serial#, --blocking_inst_id (11gR1 also), 
--                  --px_flags (11gR201 also), --pga_allocated (11gR1 also), --temp_space_allocated (11gR1 also)
--                  --delta_time (11gR1 also), --delta_read_io_requests (11gR1 also), --delta_write_io_requests (11gR1 also), 
--                  --delta_read_io_bytesi (11gR1 also), --delta_write_io_bytes (11gR1 also), --delta_interconnect_io_bytes (11gR1 also) 

SET PAGES 50000

DEF max_rows = '100000';
DEF section_name = 'ASH Raw Data';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Raw Data';
DEF main_table = 'DBA_HIST_ACTIVE_SESS_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       statement_id     source,
       search_columns   dbid,
       cardinality      snap_id,
       position         instance_number,
       parent_id        sample_id,
       timestamp        sample_time,
       partition_id     sql_exec_id,
       cpu_cost         session_id,
       io_cost          session_serial#,
       remarks          sql_id,
       cost             plan_hash_value,
       id               sql_plan_line_id,
       operation        sql_plan_operation,  
       options          sql_plan_options,  
       object_node      cpu_or_event,
       other_tag        wait_class,
       TO_NUMBER(SUBSTR(partition_start,1,INSTR(partition_start,'','',1,1)-1)) seq#,
       SUBSTR(partition_start,INSTR(partition_start,'','',1,1)+1,INSTR(partition_start,'','',1,2)-INSTR(partition_start,'','',1,1)-1) p1text,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,2)+1,INSTR(partition_start,'','',1,3)-INSTR(partition_start,'','',1,2)-1)) p1,
       SUBSTR(partition_start,INSTR(partition_start,'','',1,3)+1,INSTR(partition_start,'','',1,4)-INSTR(partition_start,'','',1,3)-1) p2text,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,4)+1,INSTR(partition_start,'','',1,5)-INSTR(partition_start,'','',1,4)-1)) p2,
       SUBSTR(partition_start,INSTR(partition_start,'','',1,5)+1,INSTR(partition_start,'','',1,6)-INSTR(partition_start,'','',1,5)-1) p3text,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,6)+1,INSTR(partition_start,'','',1,7)-INSTR(partition_start,'','',1,6)-1)) p3,
       object_instance  current_obj#,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,7)+1,INSTR(partition_start,'','',1,8)-INSTR(partition_start,'','',1,7)-1)) current_file#,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,8)+1,INSTR(partition_start,'','',1,9)-INSTR(partition_start,'','',1,8)-1)) current_block#,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,9)+1,INSTR(partition_start,'','',1,10)-INSTR(partition_start,'','',1,9)-1)) current_row#,
       SUBSTR(partition_stop,1,INSTR(partition_stop,'','',1,1)-1) in_parse,
       SUBSTR(partition_stop,INSTR(partition_stop,'','',1,1)+1,INSTR(partition_stop,'','',1,2)-INSTR(partition_stop,'','',1,1)-1) in_hard_parse,
       SUBSTR(partition_stop,INSTR(partition_stop,'','',1,2)+1,INSTR(partition_stop,'','',1,3)-INSTR(partition_stop,'','',1,2)-1) in_sql_execution,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,3)+1,INSTR(partition_stop,'','',1,4)-INSTR(partition_stop,'','',1,3)-1)) qc_instance_id,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,4)+1,INSTR(partition_stop,'','',1,5)-INSTR(partition_stop,'','',1,4)-1)) qc_session_id,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,5)+1,INSTR(partition_stop,'','',1,6)-INSTR(partition_stop,'','',1,5)-1)) qc_session_serial#,
       SUBSTR(partition_stop,INSTR(partition_stop,'','',1,6)+1,INSTR(partition_stop,'','',1,7)-INSTR(partition_stop,'','',1,6)-1) blocking_session_status,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,7)+1,INSTR(partition_stop,'','',1,8)-INSTR(partition_stop,'','',1,7)-1)) blocking_session,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,8)+1,INSTR(partition_stop,'','',1,9)-INSTR(partition_stop,'','',1,8)-1)) blocking_session_serial#,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,9)+1,INSTR(partition_stop,'','',1,10)-INSTR(partition_stop,'','',1,9)-1)) blocking_inst_id,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,10)+1,INSTR(partition_stop,'','',1,11)-INSTR(partition_stop,'','',1,10)-1)) px_flags,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,11)+1,INSTR(partition_stop,'','',1,12)-INSTR(partition_stop,'','',1,11)-1)) pga_allocated,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,12)+1,INSTR(partition_stop,'','',1,13)-INSTR(partition_stop,'','',1,12)-1)) temp_space_allocated,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,10)+1,INSTR(partition_start,'','',1,11)-INSTR(partition_start,'','',1,10)-1)) tm_delta_time,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,11)+1,INSTR(partition_start,'','',1,12)-INSTR(partition_start,'','',1,11)-1)) tm_delta_cpu_time,
       TO_NUMBER(SUBSTR(partition_start,INSTR(partition_start,'','',1,12)+1)) tm_delta_db_time,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,13)+1,INSTR(partition_stop,'','',1,14)-INSTR(partition_stop,'','',1,13)-1)) delta_time,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,14)+1,INSTR(partition_stop,'','',1,15)-INSTR(partition_stop,'','',1,14)-1)) delta_read_io_requests,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,15)+1,INSTR(partition_stop,'','',1,16)-INSTR(partition_stop,'','',1,15)-1)) delta_write_io_requests,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,16)+1,INSTR(partition_stop,'','',1,17)-INSTR(partition_stop,'','',1,16)-1)) delta_read_io_bytes,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,17)+1,INSTR(partition_stop,'','',1,18)-INSTR(partition_stop,'','',1,17)-1)) delta_write_io_bytes,
       TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'','',1,18)+1)) delta_interconnect_io_bytes 
  FROM plan_table
 WHERE remarks = ''&&sqld360_sqlid.''
   AND statement_id LIKE ''SQLD360_ASH_DATA%''
 ORDER BY timestamp,position
';
END;
/
@@sqld360_9a_pre_one.sql
