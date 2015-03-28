SPO &&one_spool_filename..html APP;
PRO </head>
@sql/sqld360_0d_html_header.sql
PRO <body>
PRO <h1><a href="http://www.enkitec.com" target="_blank">Enkitec</a>: SQL 360-degree view <em>(<a href="http://www.enkitec.com/products/sqld360" target="_blank">SQLd360</a>)</em> &&sqld360_vYYNN. - Plans Analysis Page</h1>
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
                       AND '&&diagnostics_pack.' = 'Y') 
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
                       AND '&&diagnostics_pack.' = 'Y') 
			 ORDER BY 1) 
  LOOP	
    put('SET PAGES 50000');
    put('SPO &&sqld360_main_report..html APP;');	
    put('PRO <td>');
    put('SPO OFF');

    put('DEF title=''Plan Tree''');
    put('DEF main_table = ''DBA_HIST_SQL_PLAN''');
    put('DEF skip_html=''Y''');
    put('DEF skip_text=''Y''');
    put('DEF skip_csv=''Y''');
	put('DEF skip_och=''''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT id, parent_id, id2, id3');
    put('  FROM (SELECT ''''{v: ''''''''''''||id||'''''''''''',f: ''''''''''''||operation||'''' ''''||options||''''<br>''''||object_name||''''''''''''}'''' id, ');
    put('               parent_id, ''''Step ID: ''''||id id2, id id3');
    put('		   FROM gv$sql_plan_statistics_all');
    put('         WHERE plan_hash_value =  '||i.plan_hash_value||'');
    put('           AND sql_id = ''''&&sqld360_sqlid.'''''); 
    put('        UNION ');
    put('        SELECT ''''{v: ''''''''''''||id||'''''''''''',f: ''''''''''''||operation||'''' ''''||options||''''<br>''''||object_name||''''''''''''}'''' id, ');
    put('               parent_id, ''''Step ID: ''''||id id2, id id3');
    put('		   FROM dba_hist_sql_plan');
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

    put('DEF title=''Avg et/exec for recent execs''');
    put('DEF main_table = ''V$ACTIVE_SESSION_HISTORY''');
	put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF tit_01 = ''Average Elapsed Time''');
    put('DEF tit_02 = ''Average Time on CPU''');
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
    put('       TO_CHAR(start_time, ''''YYYY-MM-DD HH24:MI'''') begin_time,'); 
    put('       TO_CHAR(start_time, ''''YYYY-MM-DD HH24:MI'''') end_time,');
    put('       avg_et,');
    put('       avg_cpu_time,');
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
    put('  FROM (SELECT start_time,');
    put('               AVG(et) avg_et,');
    put('               AVG(cpu_time) avg_cpu_time');
    put('          FROM (SELECT TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI'''') start_time,');
    put('                       cpu_cost||''''-''''||io_cost||''''-''''||partition_id||''''-''''||distribution uniq_exec,'); 
    put('                       COUNT(*) et,'); 
    put('                       SUM(CASE WHEN object_node = ''''ON CPU'''' THEN 1 ELSE 0 END) cpu_time'); 
    put('                  FROM plan_table');
    put('                 WHERE statement_id = ''''SQLD360_ASH_DATA_MEM''''');
    put('                   AND cost =  '||i.plan_hash_value||'');
    put('                   AND remarks = ''''&&sqld360_sqlid.'''''); 
    put('                   AND partition_id IS NOT NULL');
    put('                   AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                 GROUP BY TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI''''), cpu_cost||''''-''''||io_cost||''''-''''||partition_id||''''-''''||distribution)');
    put('          GROUP BY start_time)');
    put(' ORDER BY 3');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');

	put('----------------------------');

    put('DEF title=''Avg et/exec for historical execs''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
	put('DEF skip_lch=''''');
    put('DEF chartype = ''LineChart''');
    put('DEF stacked = ''''');
    put('DEF tit_01 = ''Average Elapsed Time''');
    put('DEF tit_02 = ''Average Time on CPU''');
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
    put('       NVL(avg_et,0) avg_et,');
    put('       NVL(avg_cpu_time,0) avg_cpu_time,');
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
    put('               MAX(avg_et) avg_et,');
    put('               MAX(avg_cpu_time) avg_cpu_time');
    put('          FROM (SELECT start_time,');
    put('                       MIN(start_snap_id) snap_id,');
    put('                       AVG(et) avg_et,');
    put('                       AVG(cpu_time) avg_cpu_time');
    put('                  FROM (SELECT TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI'''') start_time,');
    put('                               cpu_cost||''''-''''||io_cost||''''-''''||partition_id||''''-''''||distribution uniq_exec,'); 
    put('                               MIN(cardinality) start_snap_id,');
    put('                               SUM(10) et, ');
    put('                               SUM(CASE WHEN object_node = ''''ON CPU'''' THEN 10 ELSE 0 END) cpu_time'); 
    put('                          FROM plan_table');
    put('                         WHERE statement_id = ''''SQLD360_ASH_DATA_HIST''''');
    put('                           AND partition_id IS NOT NULL');
    put('                           AND cost = '||i.plan_hash_value||'');
    put('                           AND remarks = ''''&&sqld360_sqlid.''''');
    put('                           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('                         GROUP BY TO_DATE(SUBSTR(distribution,1,12),''''YYYYMMDDHH24MI''''), cpu_cost||''''-''''||io_cost||''''-''''||partition_id||''''-''''||distribution)');
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

    put('DEF title=''Top 15 Wait events''');
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
    put('	            count(*) num_samples');
    put('		   FROM plan_table');
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

    put('DEF title=''Top 15 Objects accessed''');
    put('DEF main_table = ''DBA_HIST_ACTIVE_SESS_HISTORY''');
	put('DEF skip_pch=''''');
    put('DEF slices = ''15''');
    put('BEGIN');
    put(' :sql_text := ''');
    put('SELECT obj#,');
    put('       num_samples,');
    put('       TRUNC(100*RATIO_TO_REPORT(num_samples) OVER (),2) percent,');
    put('       NULL dummy_01');	
    put('  FROM (SELECT NVL2(b.owner,b.owner||''''.''''||b.object_name,a.object_instance) obj#,');
    put('	            count(*) num_samples');
    put('		   FROM plan_table a,');
    put('		        dba_objects b');
    put('         WHERE a.cost =  '||i.plan_hash_value||'');
    put('           AND a.remarks = ''''&&sqld360_sqlid.'''''); 
    put('           AND ''''&&diagnostics_pack.'''' = ''''Y''''');
    put('           AND a.object_instance = b.data_object_id(+)');
    put('           AND a.other_tag IN (''''Application'''',''''Cluster'''', ''''Concurrency'''', ''''User I/O'''')');
    put('         GROUP BY NVL2(b.owner,b.owner||''''.''''||b.object_name,a.object_instance)'); 
    put('         ORDER BY 2 DESC)');
    put(' WHERE rownum <= 15');
    put(''';');
    put('END;');
    put('/ ');
    put('@sql/sqld360_9a_pre_one.sql');		

	put('----------------------------');

    put('DEF title=''Top 15 Plan Steps''');
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
    put('	            count(*) num_samples');
    put('		   FROM plan_table');
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
