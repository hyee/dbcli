SPO &&one_spool_filename..html APP;
PRO </head>
@sql/sqld360_0d_html_header.sql
PRO <body>
PRO <h1><a href="http://www.enkitec.com" target="_blank">Enkitec</a>: SQL 360-degree view <em>(<a href="http://www.enkitec.com/products/sqld360" target="_blank">SQLd360</a>)</em> &&sqld360_vYYNN. - Plans Details Page</h1>
PRO
PRO <pre>
PRO sqlid:&&sqld360_sqlid. dbname:&&database_name_short. version:&&db_version. host:&&host_name_short. license:&&license_pack. days:&&history_days. today:&&sqld360_time_stamp.
PRO </pre>
PRO

PRO <table><tr class="main">

SET SERVEROUT ON ECHO OFF FEEDBACK OFF TIMING OFF 

BEGIN
  FOR i IN (SELECT plan_hash_value
              FROM (SELECT plan_hash_value
                      FROM gv$sql
                     WHERE sql_id = '&&sqld360_sqlid.'
                    UNION
                    SELECT plan_hash_value
                      FROM dba_hist_sqlstat
                     WHERE sql_id = '&&sqld360_sqlid.'
                       AND '&&diagnostics_pack.' = 'Y'
                    UNION
                   SELECT cost plan_hash_value
                     FROM plan_table
                    WHERE statement_id LIKE 'SQLD360_ASH_DATA%'
                      AND '&&diagnostics_pack.' = 'Y'
                      AND remarks = '&&sqld360_sqlid.') 
             ORDER BY 1)
  LOOP
    DBMS_OUTPUT.PUT_LINE('<td class="c">PHV '||i.plan_hash_value||'</td>');
  END LOOP;
END;
/

PRO </tr><tr class="main">
SPO OFF

-- this is to trick sqld360_9a_pre
DEF sqld360_main_report_bck = &&sqld360_main_report.
DEF sqld360_main_report = &&one_spool_filename.

SPO sqld360_plans_analysis_&&sqld360_sqlid._driver.sql
SET SERVEROUT ON

DECLARE
  PROCEDURE put (p_line IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put;
BEGIN

-- this is intentional, showing all the tables including the ones with no histograms
-- so it's easier to spot the ones with no histograms too
  FOR i IN (SELECT plan_hash_value
              FROM (SELECT plan_hash_value
                      FROM gv$sql
                     WHERE sql_id = '&&sqld360_sqlid.'
                    UNION
                    SELECT plan_hash_value
                      FROM dba_hist_sqlstat
                     WHERE sql_id = '&&sqld360_sqlid.'
                       AND '&&diagnostics_pack.' = 'Y'
                    UNION
                    SELECT cost plan_hash_value
                      FROM plan_table
                     WHERE statement_id LIKE 'SQLD360_ASH_DATA%'
                       AND '&&diagnostics_pack.' = 'Y'
                       AND remarks = '&&sqld360_sqlid.') 
             ORDER BY 1) 
  LOOP
    put('SET PAGES 50000');
    put('SPO &&sqld360_main_report..html APP;');
    put('PRO <td>');
    put('SPO OFF');

    put('SPO &&one_spool_filename..html APP;');
    put('PRO <h2>Execution Plan</h2> ');
    put('SPO OFF');

    put('DEF title=''Plan Tree for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_SQL_PLAN''');
    put('DEF skip_html=''Y''');
    put('DEF skip_text=''Y''');
    put('DEF skip_csv=''Y''');
    put('DEF skip_tch=''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT id, parent_id, id2, id3');
    put('  FROM (SELECT ''''{v: ''''''''''''||id||'''''''''''',f: ''''''''''''||operation||'''' ''''||options||''''<br>''''||object_name||''''''''''''}'''' id, ');
    put('               parent_id, ''''Step ID: ''''||id id2, id id3');
    put('          FROM gv$sql_plan_statistics_all');
    put('         WHERE plan_hash_value =  '||i.plan_hash_value||'');
    put('           AND sql_id = ''''&&sqld360_sqlid.'''''); 
    put('        UNION ');
    put('        SELECT ''''{v: ''''''''''''||id||'''''''''''',f: ''''''''''''||operation||'''' ''''||options||''''<br>''''||object_name||''''''''''''}'''' id, ');
    put('               parent_id, ''''Step ID: ''''||id id2, id id3');
    put('          FROM dba_hist_sql_plan');
    put('         WHERE plan_hash_value =  '||i.plan_hash_value||'');
    put('           AND sql_id = ''''&&sqld360_sqlid.'''''); 
    put('           AND NOT EXISTS (SELECT 1 ');
    put('                             FROM gv$sql_plan_statistics_all ');
    put('                            WHERE plan_hash_value =  '||i.plan_hash_value||'');
    put('                              AND sql_id = ''''&&sqld360_sqlid.'''')');
    put('           AND ''''&&diagnostics_pack.'''' = ''''Y'''')');
    put(' ORDER BY id3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('SPO &&one_spool_filename..html APP;');
    put('PRO <h2>Elapsed Time</h2> ');
    put('SPO OFF');

    put('DEF title=''Avg et/exec for recent execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''V$ACTIVE_SESSION_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''Average Elapsed Time in secs''');
    put('DEF tit_01 = ''Average Elapsed Time''');
    put('DEF tit_02 = ''Average Time on CPU''');
    put('DEF tit_03 = ''Average DB Time''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT 0 snap_id,');
    put('       TO_CHAR(start_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(start_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       avg_et,');
    put('       avg_cpu_time,');
    put('       avg_db_time,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT start_time,');
    put('               AVG(et) avg_et,');
    put('               AVG(cpu_time) avg_cpu_time,');
    put('               AVG(db_time) avg_db_time');
    put('          FROM (SELECT TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI'''') start_time,');
    put('                       NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,3)+1,INSTR(partition_stop,'''','''',1,4)-INSTR(partition_stop,'''','''',1,3)-1)),position)||''''-''''||'); 
    put('                        NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,4)+1,INSTR(partition_stop,'''','''',1,5)-INSTR(partition_stop,'''','''',1,4)-1)),cpu_cost)||''''-''''||'); 
    put('                        NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,5)+1,INSTR(partition_stop,'''','''',1,6)-INSTR(partition_stop,'''','''',1,5)-1)),io_cost)||''''-''''||');
    put('                        NVL(partition_id,0)||''''-''''||NVL(distribution,''''x'''') uniq_exec,'); 
    put('                       1+86400*(MAX(timestamp)-MIN(timestamp)) et,'); 
    put('                       SUM(CASE WHEN object_node = ''''ON CPU'''' THEN 1 ELSE 0 END) cpu_time,'); 
    put('                       COUNT(*) db_time'); 
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_MEM''''');
    put('                   AND cost =  '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('                   AND partition_id IS NOT NULL');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI''''),');
    put('                          NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,3)+1,INSTR(partition_stop,'''','''',1,4)-INSTR(partition_stop,'''','''',1,3)-1)),position)||''''-''''||'); 
    put('                           NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,4)+1,INSTR(partition_stop,'''','''',1,5)-INSTR(partition_stop,'''','''',1,4)-1)),cpu_cost)||''''-''''||'); 
    put('                           NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,5)+1,INSTR(partition_stop,'''','''',1,6)-INSTR(partition_stop,'''','''',1,5)-1)),io_cost)||''''-''''||');
    put('                           NVL(partition_id,0)||''''-''''||NVL(distribution,''''x''''))');
    put('          GROUP BY start_time)');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Avg et/exec for historical execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''Average Elapsed Time in secs''');
    put('DEF tit_01 = ''Average Elapsed Time''');
    put('DEF tit_02 = ''Average Time on CPU''');
    put('DEF tit_03 = ''Average DB Time''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT b.snap_id snap_id,');
    put('       TO_CHAR(b.begin_interval_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(b.end_interval_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       NVL(avg_et,0) avg_et,');
    put('       NVL(avg_cpu_time,0) avg_cpu_time,');
    put('       NVL(avg_db_time,0) avg_db_time,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT snap_id,');
    put('               MAX(avg_et) avg_et,');
    put('               MAX(avg_cpu_time) avg_cpu_time,');
    put('               MAX(avg_db_time) avg_db_time');
    put('          FROM (SELECT start_time,');
    put('                       MIN(start_snap_id) snap_id,');
    put('                       AVG(et) avg_et,');
    put('                       AVG(cpu_time) avg_cpu_time,');
    put('                       AVG(db_time) avg_db_time');
    put('                  FROM (SELECT TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI'''') start_time,');
    put('                               NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,3)+1,INSTR(partition_stop,'''','''',1,4)-INSTR(partition_stop,'''','''',1,3)-1)),position)||''''-''''||'); 
    put('                                NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,4)+1,INSTR(partition_stop,'''','''',1,5)-INSTR(partition_stop,'''','''',1,4)-1)),cpu_cost)||''''-''''||'); 
    put('                                NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,5)+1,INSTR(partition_stop,'''','''',1,6)-INSTR(partition_stop,'''','''',1,5)-1)),io_cost)||''''-''''||');
    put('                                NVL(partition_id,0)||''''-''''||NVL(distribution,''''x'''') uniq_exec,'); 
    put('                               MIN(cardinality) start_snap_id,');
    put('                               10+86400*(MAX(timestamp)-MIN(timestamp)) et, ');
    put('                               SUM(CASE WHEN object_node = ''''ON CPU'''' THEN 10 ELSE 0 END) cpu_time,'); 
    put('                               SUM(10) db_time'); 
    put('                          FROM plan_table');
    put('                         WHERE statement_id = ''''SQLD360_ASH_DATA_HIST''''');
    put('                           AND partition_id IS NOT NULL');
    put('                           AND cost = '||i.plan_hash_value||'');
    put('                           AND remarks = ''''&&sqld360_sqlid.''''');
    put('                           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                         GROUP BY TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI''''), ');
    put('                                  NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,3)+1,INSTR(partition_stop,'''','''',1,4)-INSTR(partition_stop,'''','''',1,3)-1)),position)||''''-''''||'); 
    put('                                   NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,4)+1,INSTR(partition_stop,'''','''',1,5)-INSTR(partition_stop,'''','''',1,4)-1)),cpu_cost)||''''-''''||'); 
    put('                                   NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,5)+1,INSTR(partition_stop,'''','''',1,6)-INSTR(partition_stop,'''','''',1,5)-1)),io_cost)||''''-''''||');
    put('                                   NVL(partition_id,0)||''''-''''||NVL(distribution,''''x''''))');
    put('                 GROUP BY start_time)');
    put('         GROUP BY snap_id) ash,');
    put('      dba_hist_snapshot b');
    put(' WHERE ash.snap_id(+) = b.snap_id');
    put('   AND b.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('SPO &&one_spool_filename..html APP;');
    put('PRO <h2>Resource Consumption</h2> ');
    put('SPO OFF');

    put('DEF title=''Peak PGA and TEMP usage for recent execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''V$ACTIVE_SESSION_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''Bytes''');
    put('DEF tit_01 = ''PGA Usage''');
    put('DEF tit_02 = ''TEMP Usage''');
    put('DEF tit_03 = ''''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT 0 snap_id,');
    put('       TO_CHAR(end_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(end_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       pga_allocated_min,');
    put('       temp_space_allocated_min,');
    put('       0 dummy_03,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT TRUNC(end_time,''''mi'''') end_time,');
    put('               MAX(pga_allocated) pga_allocated_min,');
    put('               MAX(temp_space_allocated) temp_space_allocated_min');
    put('          FROM (SELECT timestamp end_time,');
    put('                       SUM(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,11)+1,INSTR(partition_stop,'''','''',1,12)-INSTR(partition_stop,'''','''',1,11)-1))) pga_allocated,'); 
    put('                       SUM(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,12)+1,INSTR(partition_stop,'''','''',1,13)-INSTR(partition_stop,'''','''',1,12)-1))) temp_space_allocated'); 
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_MEM''''');
    put('                   AND cost =  '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('                   AND partition_id IS NOT NULL');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY timestamp)');
    put('          GROUP BY TRUNC(end_time,''''mi''''))');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Peak PGA and TEMP usage for historical execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''Bytes''');
    put('DEF tit_01 = ''PGA Usage''');
    put('DEF tit_02 = ''TEMP Usage''');
    put('DEF tit_03 = ''''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT b.snap_id snap_id,');
    put('       TO_CHAR(b.begin_interval_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(b.end_interval_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       NVL(pga_allocated_hour,0) pga_allocated_hour,');
    put('       NVL(temp_space_allocated_hour,0) temp_space_allocated_hour,');
    put('       0 dummy_03,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT snap_id,');
    put('               MAX(pga_allocated) pga_allocated_hour,');
    put('               MAX(temp_space_allocated) temp_space_allocated_hour');
    put('          FROM (SELECT cardinality snap_id,');
    put('                       timestamp end_time,'); 
    put('                       SUM(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,11)+1,INSTR(partition_stop,'''','''',1,12)-INSTR(partition_stop,'''','''',1,11)-1))) pga_allocated,');
    put('                       SUM(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,12)+1,INSTR(partition_stop,'''','''',1,13)-INSTR(partition_stop,'''','''',1,12)-1))) temp_space_allocated');
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_HIST''''');
    put('                   AND cost = '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.''''');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY cardinality, timestamp)');
    put('         GROUP BY snap_id) ash,');
    put('      dba_hist_snapshot b');
    put(' WHERE ash.snap_id(+) = b.snap_id');
    put('   AND b.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

-- the result in case of PX might be a little misleading because some slaves could be not sampled
-- for few secs and then show up with a delta_time > 1 sec so the metrics should be split "backwards" in time
-- but that would be too expensive to compute and likely to provide little benefit
-- there should be no issue for serial execs

    put('DEF title=''Peak Read and Write I/O requests for recent execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''V$ACTIVE_SESSION_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''Number of I/O requests''');
    put('DEF tit_01 = ''Read I/O Request''');
    put('DEF tit_02 = ''Write I/O Request''');
    put('DEF tit_03 = ''''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT 0 snap_id,');
    put('       TO_CHAR(end_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(end_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       read_io_requests_min,');
    put('       write_io_requests_min,');
    put('       0 dummy_03,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT TRUNC(end_time,''''mi'''') end_time,');
    put('               MAX(read_io_requests) read_io_requests_min,');
    put('               MAX(write_io_requests) write_io_requests_min');
    put('          FROM (SELECT timestamp end_time,');
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,14)+1,INSTR(partition_stop,'''','''',1,15)-INSTR(partition_stop,'''','''',1,14)-1)),0)/ ');
    put('                           NVL(NULLIF(ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6),0),1)) read_io_requests,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,15)+1,INSTR(partition_stop,'''','''',1,16)-INSTR(partition_stop,'''','''',1,15)-1)),0)/ ');
    put('                           NVL(NULLIF(ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6),0),1)) write_io_requests'); 
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_MEM''''');
    put('                   AND cost =  '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('                   AND partition_id IS NOT NULL');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY timestamp)');
    put('          GROUP BY TRUNC(end_time,''''mi''''))');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Peak Read and Write I/O requests for historical execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''Number of I/O requests''');
    put('DEF tit_01 = ''Read I/O Request''');
    put('DEF tit_02 = ''Write I/O Request''');
    put('DEF tit_03 = ''''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT b.snap_id snap_id,');
    put('       TO_CHAR(b.begin_interval_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(b.end_interval_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       NVL(read_io_requests_hour,0) read_io_requests_hour,');
    put('       NVL(write_io_requests_hour,0) write_io_requests_hour,');
    put('       0 dummy_03,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT snap_id,');
    put('               MAX(read_io_requests) read_io_requests_hour,');
    put('               MAX(write_io_requests) write_io_requests_hour');
    put('          FROM (SELECT cardinality snap_id,');
    put('                       timestamp end_time,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,14)+1,INSTR(partition_stop,'''','''',1,15)-INSTR(partition_stop,'''','''',1,14)-1)),0)/ ');
    put('                               ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6)) read_io_requests,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,15)+1,INSTR(partition_stop,'''','''',1,16)-INSTR(partition_stop,'''','''',1,15)-1)),0)/ ');
    put('                               ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6)) write_io_requests'); 
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_HIST''''');
    put('                   AND cost = '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.''''');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY cardinality, timestamp)');
    put('         GROUP BY snap_id) ash,');
    put('      dba_hist_snapshot b');
    put(' WHERE ash.snap_id(+) = b.snap_id');
    put('   AND b.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Peak Read, Write and Interconnect I/O bytes for recent execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''V$ACTIVE_SESSION_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''I/O bytes''');
    put('DEF tit_01 = ''Read I/O Bytes''');
    put('DEF tit_02 = ''Write I/O Bytes''');
    put('DEF tit_03 = ''Interconnect I/O Bytes''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT 0 snap_id,');
    put('       TO_CHAR(end_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(end_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       read_io_bytes_min,');
    put('       write_io_bytes_min,');
    put('       interconnect_io_bytes_min,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT TRUNC(end_time,''''mi'''') end_time,');
    put('               MAX(read_io_bytes) read_io_bytes_min,');
    put('               MAX(write_io_bytes) write_io_bytes_min,');
    put('               MAX(interconnect_io_bytes) interconnect_io_bytes_min');
    put('          FROM (SELECT timestamp end_time,');
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,16)+1,INSTR(partition_stop,'''','''',1,17)-INSTR(partition_stop,'''','''',1,16)-1)),0)/ ');
    put('                           NVL(NULLIF(ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6),0),1)) read_io_bytes,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,17)+1,INSTR(partition_stop,'''','''',1,18)-INSTR(partition_stop,'''','''',1,17)-1)),0)/ ');
    put('                           NVL(NULLIF(ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6),0),1)) write_io_bytes,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,18)+1)),0)/ ');
    put('                           NVL(NULLIF(ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6),0),1)) interconnect_io_bytes'); 
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_MEM''''');
    put('                   AND cost =  '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('                   AND partition_id IS NOT NULL');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY timestamp)');
    put('          GROUP BY TRUNC(end_time,''''mi''''))');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Peak Read, Write and Interconnect I/O bytes for historical execs for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF vaxis = ''I/O bytes''');
    put('DEF tit_01 = ''Read I/O Bytes''');
    put('DEF tit_02 = ''Write I/O Bytes''');
    put('DEF tit_03 = ''Interconnect I/O Bytes''');
    put('DEF tit_04 = ''''');
    put('DEF tit_05 = ''''');
    put('DEF tit_06 = ''''');
    put('DEF tit_07 = ''''');
    put('DEF tit_08 = ''''');
    put('DEF tit_09 = ''''');
    put('DEF tit_10 = ''''');
    put('DEF tit_11 = ''''');
    put('DEF tit_12 = ''''');
    put('DEF tit_13 = ''''');
    put('DEF tit_14 = ''''');
    put('DEF tit_15 = ''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT b.snap_id snap_id,');
    put('       TO_CHAR(b.begin_interval_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(b.end_interval_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       NVL(read_io_bytes_hour,0) read_io_requests_hour,');
    put('       NVL(write_io_bytes_hour,0) write_io_bytes_hour,');
    put('       NVL(interconnect_io_bytes_hour,0) interconnect_io_bytes_hour,');
    put('       0 dummy_04,');
    put('       0 dummy_05,');
    put('       0 dummy_06,');
    put('       0 dummy_07,');
    put('       0 dummy_08,');
    put('       0 dummy_09,');
    put('       0 dummy_10,');
    put('       0 dummy_11,');
    put('       0 dummy_12,');
    put('       0 dummy_13,');
    put('       0 dummy_14,');
    put('       0 dummy_15');
    put('  FROM (SELECT snap_id,');
    put('               MAX(read_io_bytes) read_io_bytes_hour,');
    put('               MAX(write_io_bytes) write_io_bytes_hour,');
    put('               MAX(interconnect_io_bytes) interconnect_io_bytes_hour');
    put('          FROM (SELECT cardinality snap_id,');
    put('                       timestamp end_time,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,16)+1,INSTR(partition_stop,'''','''',1,17)-INSTR(partition_stop,'''','''',1,16)-1)),0)/ ');
    put('                               ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6)) read_io_bytes,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,17)+1,INSTR(partition_stop,'''','''',1,18)-INSTR(partition_stop,'''','''',1,17)-1)),0)/ ');
    put('                               ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6)) write_io_bytes,'); 
    put('                       SUM(NVL(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,18)+1)),0)/ ');
    put('                               ROUND(TO_NUMBER(SUBSTR(partition_stop,INSTR(partition_stop,'''','''',1,13)+1,INSTR(partition_stop,'''','''',1,14)-INSTR(partition_stop,'''','''',1,13)-1))/1e6)) interconnect_io_bytes'); 
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_HIST''''');
    put('                   AND cost = '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.''''');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY cardinality, timestamp)');
    put('         GROUP BY snap_id) ash,');
    put('      dba_hist_snapshot b');
    put(' WHERE ash.snap_id(+) = b.snap_id');
    put('   AND b.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('SPO &&one_spool_filename..html APP;');
    put('PRO <h2>Top N</h2> ');
    put('SPO OFF');

    put('DEF title=''Top 15 Wait events for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_pch=''''');
    put('DEF slices = ''15''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT cpu_or_event,');
    put('       num_samples,');
    put('       TRUNC(100*RATIO_TO_REPORT(num_samples) OVER (),2) percent,');
    put('       NULL dummy_01');
    put('  FROM (SELECT object_node cpu_or_event,');
    put('               count(*) num_samples');
    put('          FROM plan_table');
    put('         WHERE cost =  '||i.plan_hash_value||'');
    put('           AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('         GROUP BY object_node'); 
    put('         ORDER BY 2 DESC)');
    put(' WHERE rownum <= 15');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Top 15 Objects accessed by PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_pch=''''');
    put('DEF slices = ''15''');
    put('BEGIN');
    put(' :sql_text := ''');
--    put('SELECT obj#,');
--    put('       num_samples,');
--    put('       TRUNC(100*RATIO_TO_REPORT(num_samples) OVER (),2) percent,');
--    put('       NULL dummy_01');
--    put('  FROM (SELECT NVL2(b.owner,b.owner||''''.''''||b.object_name,a.object_instance) obj#,');
--    put('               count(*) num_samples');
--    put('          FROM plan_table a,');
--    put('               dba_objects b');
--    put('         WHERE a.cost =  '||i.plan_hash_value||'');
--    put('           AND a.remarks = ''''&&sqld360_sqlid.'''''); 
--    put('           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
--    put('           AND a.object_instance = b.data_object_id(+)');
--    put('           AND a.other_tag IN (''''Application'''',''''Cluster'''', ''''Concurrency'''', ''''User I/O'''', ''''System I/O'''')');
--    put('         GROUP BY NVL2(b.owner,b.owner||''''.''''||b.object_name,a.object_instance)'); 
--    put('         ORDER BY 2 DESC)');
--    put(' WHERE rownum <= 15');

--    put('SELECT object_name,');
--    put('       num_samples,');
--    put('       TRUNC(100*RATIO_TO_REPORT(num_samples) OVER (),2) percent,');
--    put('       NULL dummy_01');
--    put('  FROM (SELECT CASE WHEN data.object_name_sofar IS NOT NULL AND data.object_name_sofar <> ''''.'''' THEN data.object_name_sofar');
--    put('                    ELSE CASE WHEN o.owner||''''.''''||o.object_name <> ''''.'''' THEN o.owner||''''.''''||o.object_name'); 
--    put('                              ELSE TO_CHAR(data.obj#) ');
--    put('                         END ');
--    put('               END object_name,');
--    put('               data.num_samples');
--    put('          FROM (SELECT a.object_instance obj#,');
--    put('                       b.owner||''''.''''||b.object_name object_name_sofar,');
--    put('                       count(*) num_samples');
--    put('                  FROM plan_table a,');
--    put('                       dba_objects b');
--    put('                 WHERE a.cost =  '||i.plan_hash_value||'');
--    put('                   AND a.remarks = ''''&&sqld360_sqlid.'''''); 
--    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
--    put('                   AND a.object_instance = b.object_id(+)');
--    put('                   AND a.other_tag IN (''''Application'''',''''Cluster'''', ''''Concurrency'''', ''''User I/O'''', ''''System I/O'''')');
--    put('                 GROUP BY b.owner||''''.''''||b.object_name,a.object_instance) data,');
--    put('                dba_objects o');
--    put('         WHERE data.obj# = o.data_object_id(+)');
--    put('         ORDER BY 2 DESC)');
--    put(' WHERE rownum <= 15');

    put('SELECT data.obj#||');
    put('       NVL(');
    put('       (SELECT TRIM(''''.'''' FROM '''' ''''||o.owner||''''.''''||o.object_name||''''.''''||o.subobject_name) FROM dba_objects o WHERE o.object_id = data.obj# AND ROWNUM = 1),'); 
    put('       (SELECT TRIM(''''.'''' FROM '''' ''''||o.owner||''''.''''||o.object_name||''''.''''||o.subobject_name) FROM dba_objects o WHERE o.data_object_id = data.obj# AND ROWNUM = 1)'); 
    put('       ) data_object,');
    put('       num_samples,');
    put('       TRUNC(100*RATIO_TO_REPORT(num_samples) OVER (),2) percent,');
    put('       NULL dummy_01');
    put('  FROM (SELECT a.object_instance obj#,');
    put('               count(*) num_samples');
    put('          FROM plan_table a');
    put('         WHERE a.cost =  '||i.plan_hash_value||'');
    put('           AND a.remarks = ''''&&sqld360_sqlid.'''''); 
    put('           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('           AND a.other_tag IN (''''Application'''',''''Cluster'''', ''''Concurrency'''', ''''User I/O'''', ''''System I/O'''')');
    put('         GROUP BY a.object_instance'); 
    put('         ORDER BY 2 DESC) data');
    put(' WHERE rownum <= 15');

    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Top 15 Plan Steps for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_pch=''''');
    put('DEF slices = ''15''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT operation,');
    put('       num_samples,');
    put('       TRUNC(100*RATIO_TO_REPORT(num_samples) OVER (),2) percent,');
    put('       NULL dummy_01');
    put('  FROM (SELECT id||'''' - ''''||operation operation,');
    put('               count(*) num_samples');
    put('          FROM plan_table');
    put('         WHERE cost =  '||i.plan_hash_value||'');
    put('           AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('         GROUP BY id||'''' - ''''||operation'); 
    put('         ORDER BY 2 DESC)');
    put(' WHERE rownum <= 15');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Top 15 Step/Event for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_pch=''''');
    put('DEF slices = ''15''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT step_event,');
    put('       num_samples,');
    put('       TRUNC(100*RATIO_TO_REPORT(num_samples) OVER (),2) percent,');
    put('       NULL dummy_01');
    put('  FROM (SELECT id||'''' - ''''||operation||'''' / ''''||object_node step_event,');
    put('               count(*) num_samples');
    put('          FROM plan_table');
    put('         WHERE cost =  '||i.plan_hash_value||'');
    put('           AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('         GROUP BY id||'''' - ''''||operation||'''' / ''''||object_node'); 
    put('         ORDER BY 2 DESC)');
    put(' WHERE rownum <= 15');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

    put('----------------------------');

    put('DEF title=''Top 15 Wait events over recent time for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''GV$ACTIVE_SESSION_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''AreaChart''');
    put('DEF stacked = ''isStacked: true,''');
    put('DEF abstract = ''AAS (stacked) per top 15 wait events over time''');
    put('DEF vaxis = ''Average Active Sessions - AAS (stacked)''');

    -- this looks confusing but it actually has a reason :-)
    -- tit_n is used to show / hide the column in the chart (in case of nulls)
    -- evt_n is used as filter value (populated dynamically)
    -- eN  is used to show / hide the column in the resultset (in case of nulls)

    put('COL evt_01 NEW_V evt_01'); 
    put('COL evt_02 NEW_V evt_02'); 
    put('COL evt_03 NEW_V evt_03'); 
    put('COL evt_04 NEW_V evt_04'); 
    put('COL evt_05 NEW_V evt_05'); 
    put('COL evt_06 NEW_V evt_06'); 
    put('COL evt_07 NEW_V evt_07'); 
    put('COL evt_08 NEW_V evt_08'); 
    put('COL evt_09 NEW_V evt_09'); 
    put('COL evt_10 NEW_V evt_10'); 
    put('COL evt_11 NEW_V evt_11'); 
    put('COL evt_12 NEW_V evt_12'); 
    put('COL evt_13 NEW_V evt_13'); 
    put('COL evt_14 NEW_V evt_14'); 
    put('COL evt_15 NEW_V evt_15');
    put('COL tit_01 NEW_V tit_01'); 
    put('COL tit_02 NEW_V tit_02'); 
    put('COL tit_03 NEW_V tit_03'); 
    put('COL tit_04 NEW_V tit_04'); 
    put('COL tit_05 NEW_V tit_05'); 
    put('COL tit_06 NEW_V tit_06'); 
    put('COL tit_07 NEW_V tit_07'); 
    put('COL tit_08 NEW_V tit_08'); 
    put('COL tit_09 NEW_V tit_09'); 
    put('COL tit_10 NEW_V tit_10'); 
    put('COL tit_11 NEW_V tit_11'); 
    put('COL tit_12 NEW_V tit_12'); 
    put('COL tit_13 NEW_V tit_13'); 
    put('COL tit_14 NEW_V tit_14'); 
    put('COL tit_15 NEW_V tit_15'); 

    put('SELECT MAX(CASE WHEN ranking = 1  THEN cpu_or_event ELSE '''' END) evt_01,');
    put('       MAX(CASE WHEN ranking = 2  THEN cpu_or_event ELSE '''' END) evt_02,');              
    put('       MAX(CASE WHEN ranking = 3  THEN cpu_or_event ELSE '''' END) evt_03,'); 
    put('       MAX(CASE WHEN ranking = 4  THEN cpu_or_event ELSE '''' END) evt_04,'); 
    put('       MAX(CASE WHEN ranking = 5  THEN cpu_or_event ELSE '''' END) evt_05,'); 
    put('       MAX(CASE WHEN ranking = 6  THEN cpu_or_event ELSE '''' END) evt_06,'); 
    put('       MAX(CASE WHEN ranking = 7  THEN cpu_or_event ELSE '''' END) evt_07,'); 
    put('       MAX(CASE WHEN ranking = 8  THEN cpu_or_event ELSE '''' END) evt_08,'); 
    put('       MAX(CASE WHEN ranking = 9  THEN cpu_or_event ELSE '''' END) evt_09,'); 
    put('       MAX(CASE WHEN ranking = 10 THEN cpu_or_event ELSE '''' END) evt_10,');
    put('       MAX(CASE WHEN ranking = 11 THEN cpu_or_event ELSE '''' END) evt_11,');
    put('       MAX(CASE WHEN ranking = 12 THEN cpu_or_event ELSE '''' END) evt_12,');
    put('       MAX(CASE WHEN ranking = 13 THEN cpu_or_event ELSE '''' END) evt_13,');
    put('       MAX(CASE WHEN ranking = 14 THEN cpu_or_event ELSE '''' END) evt_14,');
    put('       MAX(CASE WHEN ranking = 15 THEN cpu_or_event ELSE '''' END) evt_15 ');
    put('  FROM (SELECT 1 fake, object_node cpu_or_event,');
    put('               ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) ranking');
    put('          FROM plan_table'); 
    put('         WHERE statement_id = ''SQLD360_ASH_DATA_MEM''');
    put('           AND cost = '||i.plan_hash_value);
    put('           AND remarks = ''&&sqld360_sqlid.''');
    put('         GROUP BY object_node) ash,');
    put('       (SELECT 1 fake FROM dual) b'); -- this is in case there is no row in ASH
    put(' WHERE ash.fake(+) = b.fake');
    put('   AND ranking <= 15');
    put('/');

    put('SET DEF @');

    put('SELECT SUBSTR(''@evt_01.'',1,27) tit_01,'); 
    put('       SUBSTR(''@evt_02.'',1,27) tit_02,');
    put('       SUBSTR(''@evt_03.'',1,27) tit_03,');
    put('       SUBSTR(''@evt_04.'',1,27) tit_04,');
    put('       SUBSTR(''@evt_05.'',1,27) tit_05,');
    put('       SUBSTR(''@evt_06.'',1,27) tit_06,');
    put('       SUBSTR(''@evt_07.'',1,27) tit_07,');
    put('       SUBSTR(''@evt_08.'',1,27) tit_08,');
    put('       SUBSTR(''@evt_09.'',1,27) tit_09,');
    put('       SUBSTR(''@evt_10.'',1,27) tit_10,'); 
    put('       SUBSTR(''@evt_11.'',1,27) tit_11,');
    put('       SUBSTR(''@evt_12.'',1,27) tit_12,');
    put('       SUBSTR(''@evt_13.'',1,27) tit_13,');
    put('       SUBSTR(''@evt_14.'',1,27) tit_14,');
    put('       SUBSTR(''@evt_15.'',1,27) tit_15');
    put('  FROM DUAL');
    put('/');

    put('COL e01 NOPRI');
    put('COL e02 NOPRI');
    put('COL e03 NOPRI');
    put('COL e04 NOPRI');
    put('COL e05 NOPRI');
    put('COL e06 NOPRI');
    put('COL e07 NOPRI');
    put('COL e08 NOPRI');
    put('COL e09 NOPRI');
    put('COL e10 NOPRI');
    put('COL e11 NOPRI');
    put('COL e12 NOPRI');
    put('COL e13 NOPRI');
    put('COL e14 NOPRI');
    put('COL e15 NOPRI');

    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT 0 snap_id,');
    put('       TO_CHAR(sample_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(sample_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       NVL(aas_01,0) "e01@tit_01." ,');
    put('       NVL(aas_02,0) "e02@tit_02." ,');
    put('       NVL(aas_03,0) "e03@tit_03." ,');
    put('       NVL(aas_04,0) "e04@tit_04." ,');
    put('       NVL(aas_05,0) "e05@tit_05." ,');
    put('       NVL(aas_06,0) "e06@tit_06." ,');
    put('       NVL(aas_07,0) "e07@tit_07." ,');
    put('       NVL(aas_08,0) "e08@tit_08." ,');
    put('       NVL(aas_09,0) "e09@tit_09." ,');
    put('       NVL(aas_10,0) "e10@tit_10." ,');
    put('       NVL(aas_11,0) "e11@tit_11." ,');
    put('       NVL(aas_12,0) "e12@tit_12." ,');
    put('       NVL(aas_13,0) "e13@tit_13." ,');
    put('       NVL(aas_14,0) "e14@tit_14." ,');
    put('       NVL(aas_15,0) "e15@tit_15." ');
    put('  FROM (SELECT sample_time,');
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_01.'''' THEN aas ELSE NULL END) aas_01,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_02.'''' THEN aas ELSE NULL END) aas_02,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_03.'''' THEN aas ELSE NULL END) aas_03,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_04.'''' THEN aas ELSE NULL END) aas_04,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_05.'''' THEN aas ELSE NULL END) aas_05,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_06.'''' THEN aas ELSE NULL END) aas_06,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_07.'''' THEN aas ELSE NULL END) aas_07,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_08.'''' THEN aas ELSE NULL END) aas_08,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_09.'''' THEN aas ELSE NULL END) aas_09,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_10.'''' THEN aas ELSE NULL END) aas_10,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_11.'''' THEN aas ELSE NULL END) aas_11,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_12.'''' THEN aas ELSE NULL END) aas_12,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_13.'''' THEN aas ELSE NULL END) aas_13,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_14.'''' THEN aas ELSE NULL END) aas_14,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_15.'''' THEN aas ELSE NULL END) aas_15'); 
    put('          FROM (SELECT TRUNC(sample_time, ''''mi'''') sample_time,');
    put('                       cpu_or_event,');
    put('                       ROUND(SUM(num_sess)/60,3) aas');
    put('                  FROM (SELECT timestamp sample_time,');
    put('                               object_node cpu_or_event,'); 
    put('                               count(*) num_sess');
    put('                          FROM plan_table');
    put('                         WHERE statement_id = ''''SQLD360_ASH_DATA_MEM''''');
    put('                           AND remarks = ''''&&sqld360_sqlid.''''');
    put('                           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                           AND cost = '||i.plan_hash_value);
    put('                           AND object_node IN (''''@evt_01.'''',''''@evt_02.'''',''''@evt_03.'''',''''@evt_04.'''',''''@evt_05.'''',''''@evt_06.'''',');
    put('                                               ''''@evt_07.'''',''''@evt_08.'''',''''@evt_09.'''',''''@evt_10.'''',''''@evt_11.'''',''''@evt_12.'''',');
    put('                                               ''''@evt_13.'''',''''@evt_14.'''',''''@evt_15.'''')');
    put('                         GROUP BY timestamp, object_node)');
    put('                 GROUP BY TRUNC(sample_time, ''''mi''''), cpu_or_event)');
    put('         GROUP BY sample_time)');
    put(' ORDER BY 3 ');
    put(''';');
    put('END;');
    put('/ ');

    put('SET DEF &');
    put('@sql/sqld360_9a_pre_one.sql');

    put('COL evt01_ PRI');
    put('COL evt02_ PRI');
    put('COL evt03_ PRI');
    put('COL evt04_ PRI');
    put('COL evt05_ PRI');
    put('COL evt06_ PRI');
    put('COL evt07_ PRI');
    put('COL evt08_ PRI');
    put('COL evt09_ PRI');
    put('COL evt10_ PRI');
    put('COL evt11_ PRI');
    put('COL evt12_ PRI');
    put('COL evt13_ PRI');
    put('COL evt14_ PRI');
    put('COL evt15_ PRI');

    put('----------------------------');

    put('DEF title=''Top 15 Wait events over historical time for PHV '||i.plan_hash_value||'''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
    put('DEF skip_lch=''''');
    put('DEF chartype = ''AreaChart''');
    put('DEF stacked = ''isStacked: true,''');
    put('DEF abstract = ''AAS (stacked) per top 15 wait events over time''');
    put('DEF vaxis = ''Average Active Sessions - AAS (stacked)''');

    -- this looks confusing but it actually has a reason :-)
    -- tit_n is used to show / hide the column in the chart (in case of nulls)
    -- evt_n is used as filter value (populated dynamically)
    -- eN  is used to hosw / hide the column in the resultset (in case of nulls)

    put('COL evt_01 NEW_V evt_01'); 
    put('COL evt_02 NEW_V evt_02'); 
    put('COL evt_03 NEW_V evt_03'); 
    put('COL evt_04 NEW_V evt_04'); 
    put('COL evt_05 NEW_V evt_05'); 
    put('COL evt_06 NEW_V evt_06'); 
    put('COL evt_07 NEW_V evt_07'); 
    put('COL evt_08 NEW_V evt_08'); 
    put('COL evt_09 NEW_V evt_09'); 
    put('COL evt_10 NEW_V evt_10'); 
    put('COL evt_11 NEW_V evt_11'); 
    put('COL evt_12 NEW_V evt_12'); 
    put('COL evt_13 NEW_V evt_13'); 
    put('COL evt_14 NEW_V evt_14'); 
    put('COL evt_15 NEW_V evt_15');
    put('COL tit_01 NEW_V tit_01'); 
    put('COL tit_02 NEW_V tit_02'); 
    put('COL tit_03 NEW_V tit_03'); 
    put('COL tit_04 NEW_V tit_04'); 
    put('COL tit_05 NEW_V tit_05'); 
    put('COL tit_06 NEW_V tit_06'); 
    put('COL tit_07 NEW_V tit_07'); 
    put('COL tit_08 NEW_V tit_08'); 
    put('COL tit_09 NEW_V tit_09'); 
    put('COL tit_10 NEW_V tit_10'); 
    put('COL tit_11 NEW_V tit_11'); 
    put('COL tit_12 NEW_V tit_12'); 
    put('COL tit_13 NEW_V tit_13'); 
    put('COL tit_14 NEW_V tit_14'); 
    put('COL tit_15 NEW_V tit_15'); 

    put('SELECT MAX(CASE WHEN ranking = 1  THEN cpu_or_event ELSE '''' END) evt_01,');
    put('       MAX(CASE WHEN ranking = 2  THEN cpu_or_event ELSE '''' END) evt_02,');              
    put('       MAX(CASE WHEN ranking = 3  THEN cpu_or_event ELSE '''' END) evt_03,'); 
    put('       MAX(CASE WHEN ranking = 4  THEN cpu_or_event ELSE '''' END) evt_04,'); 
    put('       MAX(CASE WHEN ranking = 5  THEN cpu_or_event ELSE '''' END) evt_05,'); 
    put('       MAX(CASE WHEN ranking = 6  THEN cpu_or_event ELSE '''' END) evt_06,'); 
    put('       MAX(CASE WHEN ranking = 7  THEN cpu_or_event ELSE '''' END) evt_07,'); 
    put('       MAX(CASE WHEN ranking = 8  THEN cpu_or_event ELSE '''' END) evt_08,'); 
    put('       MAX(CASE WHEN ranking = 9  THEN cpu_or_event ELSE '''' END) evt_09,'); 
    put('       MAX(CASE WHEN ranking = 10 THEN cpu_or_event ELSE '''' END) evt_10,');
    put('       MAX(CASE WHEN ranking = 11 THEN cpu_or_event ELSE '''' END) evt_11,');
    put('       MAX(CASE WHEN ranking = 12 THEN cpu_or_event ELSE '''' END) evt_12,');
    put('       MAX(CASE WHEN ranking = 13 THEN cpu_or_event ELSE '''' END) evt_13,');
    put('       MAX(CASE WHEN ranking = 14 THEN cpu_or_event ELSE '''' END) evt_14,');
    put('       MAX(CASE WHEN ranking = 15 THEN cpu_or_event ELSE '''' END) evt_15 ');
    put('  FROM (SELECT 1 fake, object_node cpu_or_event,');
    put('               ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) ranking');
    put('          FROM plan_table'); 
    put('         WHERE statement_id = ''SQLD360_ASH_DATA_HIST''');
    put('           AND cost = '||i.plan_hash_value);
    put('           AND remarks = ''&&sqld360_sqlid.''');
    put('         GROUP BY object_node) ash,');
    put('       (SELECT 1 fake FROM dual) b'); -- this is in case there is no row in ASH
    put(' WHERE ash.fake(+) = b.fake');
    put('   AND ranking <= 15');
    put('/');

    put('SET DEF @');

    put('SELECT SUBSTR(''@evt_01.'',1,27) tit_01,'); 
    put('       SUBSTR(''@evt_02.'',1,27) tit_02,');
    put('       SUBSTR(''@evt_03.'',1,27) tit_03,');
    put('       SUBSTR(''@evt_04.'',1,27) tit_04,');
    put('       SUBSTR(''@evt_05.'',1,27) tit_05,');
    put('       SUBSTR(''@evt_06.'',1,27) tit_06,');
    put('       SUBSTR(''@evt_07.'',1,27) tit_07,');
    put('       SUBSTR(''@evt_08.'',1,27) tit_08,');
    put('       SUBSTR(''@evt_09.'',1,27) tit_09,');
    put('       SUBSTR(''@evt_10.'',1,27) tit_10,'); 
    put('       SUBSTR(''@evt_11.'',1,27) tit_11,');
    put('       SUBSTR(''@evt_12.'',1,27) tit_12,');
    put('       SUBSTR(''@evt_13.'',1,27) tit_13,');
    put('       SUBSTR(''@evt_14.'',1,27) tit_14,');
    put('       SUBSTR(''@evt_15.'',1,27) tit_15');
    put('  FROM DUAL');
    put('/');

    put('COL e01 NOPRI');
    put('COL e02 NOPRI');
    put('COL e03 NOPRI');
    put('COL e04 NOPRI');
    put('COL e05 NOPRI');
    put('COL e06 NOPRI');
    put('COL e07 NOPRI');
    put('COL e08 NOPRI');
    put('COL e09 NOPRI');
    put('COL e10 NOPRI');
    put('COL e11 NOPRI');
    put('COL e12 NOPRI');
    put('COL e13 NOPRI');
    put('COL e14 NOPRI');
    put('COL e15 NOPRI');

    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT 0 snap_id,');
    put('       TO_CHAR(sample_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(sample_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       NVL(aas_01,0) "e01@tit_01." ,');
    put('       NVL(aas_02,0) "e02@tit_02." ,');
    put('       NVL(aas_03,0) "e03@tit_03." ,');
    put('       NVL(aas_04,0) "e04@tit_04." ,');
    put('       NVL(aas_05,0) "e05@tit_05." ,');
    put('       NVL(aas_06,0) "e06@tit_06." ,');
    put('       NVL(aas_07,0) "e07@tit_07." ,');
    put('       NVL(aas_08,0) "e08@tit_08." ,');
    put('       NVL(aas_09,0) "e09@tit_09." ,');
    put('       NVL(aas_10,0) "e10@tit_10." ,');
    put('       NVL(aas_11,0) "e11@tit_11." ,');
    put('       NVL(aas_12,0) "e12@tit_12." ,');
    put('       NVL(aas_13,0) "e13@tit_13." ,');
    put('       NVL(aas_14,0) "e14@tit_14." ,');
    put('       NVL(aas_15,0) "e15@tit_15." ');
    put('  FROM (SELECT sample_time,');
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_01.'''' THEN aas ELSE NULL END) aas_01,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_02.'''' THEN aas ELSE NULL END) aas_02,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_03.'''' THEN aas ELSE NULL END) aas_03,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_04.'''' THEN aas ELSE NULL END) aas_04,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_05.'''' THEN aas ELSE NULL END) aas_05,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_06.'''' THEN aas ELSE NULL END) aas_06,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_07.'''' THEN aas ELSE NULL END) aas_07,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_08.'''' THEN aas ELSE NULL END) aas_08,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_09.'''' THEN aas ELSE NULL END) aas_09,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_10.'''' THEN aas ELSE NULL END) aas_10,'); 
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_11.'''' THEN aas ELSE NULL END) aas_11,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_12.'''' THEN aas ELSE NULL END) aas_12,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_13.'''' THEN aas ELSE NULL END) aas_13,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_14.'''' THEN aas ELSE NULL END) aas_14,');  
    put('               MAX(CASE WHEN cpu_or_event  = ''''@evt_15.'''' THEN aas ELSE NULL END) aas_15'); 
    put('          FROM (SELECT TRUNC(sample_time, ''''hh24'''') sample_time,');
    put('                       cpu_or_event,');
    put('                       ROUND(SUM(num_sess)*10/3600,3) aas');  -- *10 because the best we can do is assume the session spent the whole 10 secs on that event
    put('                  FROM (SELECT timestamp sample_time,');
    put('                               object_node cpu_or_event,'); 
    put('                               count(*) num_sess');
    put('                          FROM plan_table');
    put('                         WHERE statement_id = ''''SQLD360_ASH_DATA_HIST''''');
    put('                           AND remarks = ''''&&sqld360_sqlid.''''');
    put('                           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                           AND cost = '||i.plan_hash_value);
    put('                           AND object_node IN (''''@evt_01.'''',''''@evt_02.'''',''''@evt_03.'''',''''@evt_04.'''',''''@evt_05.'''',''''@evt_06.'''',');
    put('                                               ''''@evt_07.'''',''''@evt_08.'''',''''@evt_09.'''',''''@evt_10.'''',''''@evt_11.'''',''''@evt_12.'''',');
    put('                                               ''''@evt_13.'''',''''@evt_14.'''',''''@evt_15.'''')');
    put('                         GROUP BY timestamp, object_node)');
    put('                 GROUP BY TRUNC(sample_time, ''''hh24''''), cpu_or_event)');
    put('         GROUP BY sample_time)');
    put(' ORDER BY 3 ');
    put(''';');
    put('END;');
    put('/ ');

    put('SET DEF &');
    put('@sql/sqld360_9a_pre_one.sql');

    put('COL evt01_ PRI');
    put('COL evt02_ PRI');
    put('COL evt03_ PRI');
    put('COL evt04_ PRI');
    put('COL evt05_ PRI');
    put('COL evt06_ PRI');
    put('COL evt07_ PRI');
    put('COL evt08_ PRI');
    put('COL evt09_ PRI');
    put('COL evt10_ PRI');
    put('COL evt11_ PRI');
    put('COL evt12_ PRI');
    put('COL evt13_ PRI');
    put('COL evt14_ PRI');
    put('COL evt15_ PRI');

    put('----------------------------');

    put('SPO &&sqld360_main_report..html APP;');
    put('PRO </td>');
  END LOOP;
END;
/
SPO &&sqld360_main_report..html APP;
@sqld360_plans_analysis_&&sqld360_sqlid._driver.sql

SPO &&sqld360_main_report..html APP;
PRO </tr></table>
@@sqld360_0e_html_footer.sql
SPO OFF
SET PAGES 50000

HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html
HOS zip -jmq 99999_sqld360_&&sqld360_sqlid._drivers sqld360_plans_analysis_&&sqld360_sqlid._driver.sql

DEF sqld360_main_report = &&sqld360_main_report_bck.
