-- setup
SET VER OFF; 
SET FEED OFF; 
SET ECHO OFF;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD/HH24:MI:SS') sqld360_time_stamp FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SET HEA OFF;
SET TERM ON;

-- log
SPO &&sqld360_log..txt APP;
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
PRO &&hh_mm_ss.
PRO Exctrating ASH data

DECLARE
  data_already_loaded VARCHAR2(1);
BEGIN

  SELECT CASE WHEN count(*) > 0 THEN 'Y' ELSE 'N' END
    INTO data_already_loaded
    FROM plan_table
   WHERE statement_id = 'SQLD360_ASH_LOAD'
     AND operation = 'Loaded';
     
  -- it means this is the first execution and so the first SQL loads data for everybody
  IF data_already_loaded = 'N' THEN

    DELETE plan_table WHERE statement_id LIKE 'SQLD360_ASH_DATA%';
  
    -- data has two different tags depending where it comes from since they have different sampling frequency  
    INSERT INTO plan_table (statement_id,timestamp,remarks,                -- 'SQLD360_ASH_DATA', sample_time, sql_id
                            cardinality, search_columns,                   -- snap_id, dbid
                            &&skip_10g.operation,                          -- sql_plan_operation
                            &&skip_10g.options,                            -- sql_plan_options
                            object_instance, object_node, position, cost,  -- current_obj#, event, instance_number, PHV
                            other_tag,                                     -- wait_class
                            &&skip_10g.id,                                 -- sql_plan_line_id
                            &&skip_10g.partition_id,                       -- sql_exec_id
                            &&skip_10g.distribution,                       -- sql_exec_start
                            cpu_cost, io_cost,                             -- session_id, session_serial#
                            parent_id,                                     -- sample_id
                            partition_start,                               -- seq#,p1text,p1,p2text,p2,p3text,p3,current_file#,current_block#, --current_row#, --tm_delta_time, 
                                                                           -- --tm_delta_cpu_time, --tm_delta_db_time
                            partition_stop                                 -- --in_parse, --in_hard_parse, --in_sql_execution, qc_instance_id, qc_session_id, --qc_session_serial#, 
                                                                           -- blocking_session_status, blocking_session, blocking_session_serial#, --blocking_inst_id (11gR1 also), 
                                                                           -- --px_flags (11gR201 also), --pga_allocated (11gR1 also), --temp_space_allocated (11gR1 also)
                                                                           -- --delta_time (11gR1 also), --delta_read_io_requests (11gR1 also), --delta_write_io_requests (11gR1 also), 
                                                                           -- --delta_read_io_bytesi (11gR1 also), --delta_write_io_bytes (11gR1 also), --delta_interconnect_io_bytes (11gR1 also)     
                           )
     SELECT 'SQLD360_ASH_DATA_HIST', sample_time, sql_id, 
            snap_id, dbid,
            &&skip_10g.sql_plan_operation, 
            &&skip_10g.sql_plan_options, 
            current_obj#, nvl(event,'ON CPU'), instance_number, sql_plan_hash_value, 
            wait_class,
            &&skip_10g.sql_plan_line_id, 
            &&skip_10g.sql_exec_id,
            &&skip_10g.TO_CHAR(sql_exec_start,'YYYYMMDDHH24MISS'),
            session_id, session_serial#,
            sample_id,
            seq#||','||p1text||','||p1||','||p2text||','||p2||','||p3text||','||p3||','||current_file#||','||current_block#||
            ','||&&skip_10g.current_row#||
            ','||&&skip_10g.&&skip_11r1.tm_delta_time||
            ','||&&skip_10g.&&skip_11r1.tm_delta_cpu_time||
            ','&&skip_10g.&&skip_11r1.||tm_delta_db_time
            ,
            &&skip_10g.in_parse||
            ','||
            &&skip_10g.in_hard_parse||
            ','||
            &&skip_10g.in_sql_execution||
            ','||qc_instance_id||','||qc_session_id||','||
            &&skip_10g.qc_session_serial#||
            ','||blocking_session_status||','||blocking_session||','||blocking_session_serial#||','||
            &&skip_10g.&&skip_11r1.blocking_inst_id||
            ','||&&skip_10g.&&skip_11r1.&&skip_11r201.px_flags||
            ','||&&skip_10g.&&skip_11r1.pga_allocated||
            ','||&&skip_10g.&&skip_11r1.temp_space_allocated||
            ','||&&skip_10g.&&skip_11r1.delta_time||
            ','||&&skip_10g.&&skip_11r1.delta_read_io_requests||
            ','||&&skip_10g.&&skip_11r1.delta_write_io_requests||
            ','||&&skip_10g.&&skip_11r1.delta_read_io_bytes||
            ','||&&skip_10g.&&skip_11r1.delta_write_io_bytes||
            ','&&skip_10g.&&skip_11r1.||delta_interconnect_io_bytes
       FROM dba_hist_active_sess_history a,
            plan_table b
      WHERE a.sql_id = b.operation -- plan table has the SQL ID to load
        AND b.statement_id = 'SQLD360_SQLID' -- flag to identify the rows that stores SQL ID info
        AND a.sample_time > systimestamp-&&history_days.  -- extract only data of interest
        AND SUBSTR(b.options,1,1) = '1'  -- load data only for those SQL IDs that have diagnostics enabled
     UNION ALL
     SELECT 'SQLD360_ASH_DATA_MEM', sample_time, sql_id, 
            NULL, NULL,
            &&skip_10g.sql_plan_operation, 
            &&skip_10g.sql_plan_options,
            current_obj#, nvl(event,'ON CPU'), inst_id, sql_plan_hash_value, 
            wait_class,
            &&skip_10g.sql_plan_line_id, 
            &&skip_10g.sql_exec_id,
            &&skip_10g.TO_CHAR(sql_exec_start,'YYYYMMDDHH24MISS'),
            session_id, session_serial#,
            sample_id,
            seq#||','||p1text||','||p1||','||p2text||','||p2||','||p3text||','||p3||','||current_file#||','||current_block#||
            ','||&&skip_10g.current_row#||
            ','||&&skip_10g.&&skip_11r1.tm_delta_time||
            ','||&&skip_10g.&&skip_11r1.tm_delta_cpu_time||
            ','&&skip_10g.&&skip_11r1.||tm_delta_db_time
            ,
            &&skip_10g.in_parse||
            ','||
            &&skip_10g.in_hard_parse||
            ','||
            &&skip_10g.in_sql_execution||
            ','||qc_instance_id||','||qc_session_id||','||
            &&skip_10g.qc_session_serial#||
            ','||blocking_session_status||','||blocking_session||','||blocking_session_serial#||','||
            &&skip_10g.&&skip_11r1.blocking_inst_id||
            ','||&&skip_10g.&&skip_11r1.&&skip_11r201.px_flags||
            ','||&&skip_10g.&&skip_11r1.pga_allocated||
            ','||&&skip_10g.&&skip_11r1.temp_space_allocated||
            ','||&&skip_10g.&&skip_11r1.delta_time||
            ','||&&skip_10g.&&skip_11r1.delta_read_io_requests||
            ','||&&skip_10g.&&skip_11r1.delta_write_io_requests||
            ','||&&skip_10g.&&skip_11r1.delta_read_io_bytes||
            ','||&&skip_10g.&&skip_11r1.delta_write_io_bytes||
            ','&&skip_10g.&&skip_11r1.||delta_interconnect_io_bytes
       FROM gv$active_session_history a,
            plan_table b
      WHERE a.sql_id = b.operation -- plan table has the SQL ID to load
        AND b.statement_id = 'SQLD360_SQLID' -- flag to identify the rows that stores SQL ID info
        AND a.sample_time > systimestamp - &&history_days.  -- extract only data of interest
        AND SUBSTR(b.options,1,1) = '1'  -- load data only for those SQL IDs that have diagnostics enabled
     ;   
     
     INSERT INTO plan_table (statement_id, timestamp, operation) VALUES ('SQLD360_ASH_LOAD',sysdate, 'Loaded');

  END IF;
  
END;
/
  
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD/HH24:MI:SS') sqld360_time_stamp FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;  

PRO Done exctrating ASH data
PRO &&hh_mm_ss.
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
SPO OFF
