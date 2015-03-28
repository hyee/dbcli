DEF section_name = 'Plans';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Plans from Memory';
DEF main_table = 'GV$SQL_PLAN_STATISTICS_ALL';

@@sqld360_0s_pre_nondef


SPO &&one_spool_filename..txt;
PRO &&title.&&title_suffix. (&&main_table.) 
PRO &&abstract.
PRO &&abstract2.

COL inst_child FOR A21;
BREAK ON inst_child SKIP 2;
SET PAGES 0;

WITH v AS (
SELECT /*+ MATERIALIZE */
       DISTINCT sql_id, inst_id, child_number
  FROM gv$sql
 WHERE sql_id = '&&sqld360_sqlid.'
   AND loaded_versions > 0
 ORDER BY 1, 2, 3 )
SELECT /*+ ORDERED USE_NL(t) */
       RPAD('Inst: '||v.inst_id, 9)||' '||RPAD('Child: '||v.child_number, 11) inst_child, 
       t.plan_table_output
  FROM v, TABLE(DBMS_XPLAN.DISPLAY('gv$sql_plan_statistics_all', NULL, 'ADVANCED ALLSTATS LAST', 
       'inst_id = '||v.inst_id||' AND sql_id = '''||v.sql_id||''' AND child_number = '||v.child_number)) t
/

SET TERM ON
-- get current time
SPO &&sqld360_log..txt APP;
COL current_time NEW_V current_time FOR A15;
SELECT 'Completed: ' x, TO_CHAR(SYSDATE, 'HH24:MI:SS') current_time FROM DUAL;
SET TERM OFF

HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log..txt

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <li title="&&main_table.">&&title.
PRO <a href="&&one_spool_filename..txt">text</a>
SPO OFF;
HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&one_spool_filename..txt
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html

--HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log2..txt

-- update main report
SPO &&sqld360_main_report..html APP;
PRO </li>
SPO OFF;
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html


-----------------------------------
-----------------------------------

DEF title = 'Plans from History';
DEF main_table = 'DBA_HIST_SQL_PLAN';

@@sqld360_0s_pre_nondef


SPO &&one_spool_filename..txt;
PRO &&title.&&title_suffix. (&&main_table.) 
PRO &&abstract.
PRO &&abstract2.

COL inst_child FOR A21;
BREAK ON inst_child SKIP 2;
SET PAGES 0;

WITH v AS (
SELECT /*+ MATERIALIZE */ 
       DISTINCT sql_id, plan_hash_value, dbid
  FROM dba_hist_sql_plan 
 WHERE '&&diagnostics_pack.' = 'Y'
   AND dbid = '&&sqld360_dbid.' 
   AND sql_id = '&&sqld360_sqlid.'
 ORDER BY 1, 2, 3 )
SELECT /*+ ORDERED USE_NL(t) */ t.plan_table_output
  FROM v, TABLE(DBMS_XPLAN.DISPLAY_AWR(v.sql_id, v.plan_hash_value, v.dbid, 'ADVANCED')) t;


SET TERM ON
-- get current time
SPO &&sqld360_log..txt APP;
COL current_time NEW_V current_time FOR A15;
SELECT 'Completed: ' x, TO_CHAR(SYSDATE, 'HH24:MI:SS') current_time FROM DUAL;
SET TERM OFF

HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log..txt
SET PAGES 50000

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <li title="&&main_table.">&&title.
PRO <a href="&&one_spool_filename..txt">text</a>
SPO OFF;
HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&one_spool_filename..txt
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html

--HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log2..txt

-- update main report
SPO &&sqld360_main_report..html APP;
PRO </li>
SPO OFF;
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html


-----------------------------------
-----------------------------------

DEF title = 'Plans from Baseline';
DEF main_table = 'DBA_SQL_PLAN_BASELINES';

@@sqld360_0s_pre_nondef


SPO &&one_spool_filename..txt;
PRO &&title.&&title_suffix. (&&main_table.) 
PRO &&abstract.
PRO &&abstract2.

COL inst_child FOR A21;
BREAK ON inst_child SKIP 2;
SET PAGES 0;

WITH v AS (
SELECT /*+ MATERIALIZE */ 
       DISTINCT sql_handle
  FROM dba_sql_plan_baselines 
 WHERE signature = '&&exact_matching_signature.')
SELECT /*+ ORDERED USE_NL(t) */ t.plan_table_output
  FROM v, TABLE(DBMS_XPLAN.DISPLAY_SQL_PLAN_BASELINE(v.sql_handle, NULL, 'ADVANCED')) t;


SET TERM ON
-- get current time
SPO &&sqld360_log..txt APP;
COL current_time NEW_V current_time FOR A15;
SELECT 'Completed: ' x, TO_CHAR(SYSDATE, 'HH24:MI:SS') current_time FROM DUAL;
SET TERM OFF

HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log..txt
SET PAGES 50000

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <li title="&&main_table.">&&title.
PRO <a href="&&one_spool_filename..txt">text</a>
SPO OFF;
HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&one_spool_filename..txt
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html

--HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log2..txt

-- update main report
SPO &&sqld360_main_report..html APP;
PRO </li>
SPO OFF;
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html


--------------------------------------
--------------------------------------

COL num_plans NEW_V num_plans
SELECT TRIM(TO_CHAR(COUNT(plan_hash_value))) num_plans
  FROM (SELECT plan_hash_value
	      FROM gv$sql
         WHERE sql_id = '&&sqld360_sqlid.'
		UNION
		SELECT plan_hash_value
		  FROM dba_hist_sqlstat
		 WHERE sql_id = '&&sqld360_sqlid.'
           AND '&&diagnostics_pack.' = 'Y')
/	

DEF title= 'Plan Analysis'
DEF main_table = 'GV$SQL_PLAN'	

--this one initiated a new file name, need it in the next anchor
@@sqld360_0s_pre_nondef
SET TERM OFF ECHO OFF 
-- need to fix the file name for the partitions
SPO &&sqld360_main_report..html APP;
PRO <li>Plans Analysis <small><em>(&&num_plans.)</em></small> 
PRO <a href="&&one_spool_filename..html">page</a>
PRO </li>
SPO OFF;
@@sqld360_2f_plans_analysis.sql
