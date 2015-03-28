-- add seq to spool_filename
EXEC :file_seq := :file_seq + 1;
SELECT LPAD(:file_seq, 5, '0')||'_&&spool_filename.' one_spool_filename FROM DUAL;

-- display
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SET TERM ON;
SPO &&edb360_log..txt APP;
PRO &&hh_mm_ss. col:&&column_number.of&&max_col_number. "&&one_spool_filename..html"
SPO OFF;
SET TERM OFF;

-- update main report
SPO &&edb360_main_report..html APP;
PRO <a href="&&one_spool_filename..html">html</a>
SPO OFF;

-- get time t0
EXEC :get_time_t0 := DBMS_UTILITY.get_time;

-- get sql
GET &&common_edb360_prefix._query.sql

-- header
SPO &&one_spool_filename..html;
@@edb360_0d_html_header.sql
PRO <script src="sorttable.js"></script>
PRO
PRO <!-- &&one_spool_filename..html $ -->
PRO </head>
PRO <body>
PRO <h1>&&title.&&title_suffix. <em>(&&main_table.)</em></h1>
PRO
PRO <br>
PRO &&abstract.
PRO &&abstract2.
PRO

-- body
SET MARK HTML ON TABLE "class=sortable" SPOOL OFF;
/
SET MARK HTML OFF;

-- get sql_id
--SPO &&edb360_log..txt APP;
SELECT prev_sql_id edb360_prev_sql_id, TO_CHAR(prev_child_number) edb360_prev_child_number FROM v$session WHERE sid = SYS_CONTEXT('USERENV', 'SID')
/
--SPO &&one_spool_filename..html;

-- footer
PRO &&foot.
PRO #: click on a column heading to sort on it
PRO
PRO <pre>
SET LIN 80;
DESC &&main_table.
SET HEA OFF;
SET LIN 32767;
PRINT sql_text_display;
SET HEA ON;
PRO &&row_count. rows selected.
PRO </pre>

@@edb360_0e_html_footer.sql
SPO OFF;

-- get time t1
EXEC :get_time_t1 := DBMS_UTILITY.get_time;

-- update log2
SET HEA OFF;
SPO &&edb360_log2..txt APP;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')||' , '||
       TO_CHAR((:get_time_t1 - :get_time_t0)/100, '999999990.00')||' , rows:'||
       :row_count||' , &&section_id., &&main_table., &&edb360_prev_sql_id., &&edb360_prev_child_number., &&title_no_spaces., html , &&one_spool_filename..html'
  FROM DUAL
/
SPO OFF;
SET HEA ON;

-- zip
HOS zip -mq &&edb360_main_filename._&&edb360_file_time. &&one_spool_filename..html
