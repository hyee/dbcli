-- add seq to one_spool_filename
EXEC :file_seq := :file_seq + 1;
SELECT LPAD(:file_seq, 5, '0')||'_&&spool_filename.' one_spool_filename FROM DUAL;

-- display
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SET TERM ON;
SPO &&edb360_log..txt APP;
PRO &&hh_mm_ss. &&section_id. "&&one_spool_filename..csv"
SPO OFF;
SET TERM OFF;

-- update main report
SPO &&edb360_main_report..html APP;
PRO <a href="&&one_spool_filename..csv">csv</a>
SPO OFF;

-- get time t0
EXEC :get_time_t0 := DBMS_UTILITY.get_time;

-- get sql
GET &&common_edb360_prefix._query.sql

-- header
SPO &&one_spool_filename..csv;

-- body
SET PAGES 50000;
SET COLSEP '<,>';
/
SET PAGES &&def_max_rows.;
SET COLSEP ' ';

-- get sql_id
--SPO &&edb360_log..txt APP;
COL edb360_prev_sql_id NEW_V edb360_prev_sql_id NOPRI;
COL edb360_prev_child_number NEW_V edb360_prev_child_number NOPRI;
SELECT prev_sql_id edb360_prev_sql_id, TO_CHAR(prev_child_number) edb360_prev_child_number FROM v$session WHERE sid = SYS_CONTEXT('USERENV', 'SID')
/
--SPO &&one_spool_filename..csv;

-- footer
SPO OFF;

-- get time t1
EXEC :get_time_t1 := DBMS_UTILITY.get_time;

-- update log2
SET HEA OFF;
SPO &&edb360_log2..txt APP;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')||' , '||
       TO_CHAR((:get_time_t1 - :get_time_t0)/100, '999999990.00')||' , rows:'||
       :row_count||' , &&section_id., &&main_table., &&edb360_prev_sql_id., &&edb360_prev_child_number., &&title_no_spaces., html , &&one_spool_filename..csv'
  FROM DUAL
/
SPO OFF;
SET HEA ON;

-- zip
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&one_spool_filename..csv >> &&edb360_log3..txt
