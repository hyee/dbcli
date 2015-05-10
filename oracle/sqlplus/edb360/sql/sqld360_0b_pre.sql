--WHENEVER SQLERROR EXIT SQL.SQLCODE;
SET TERM ON; 
SET VER OFF; 
SET FEED OFF; 
SET ECHO OFF;
SET TIM OFF;
SET TIMI OFF;
CL COL;
COL row_num FOR 9999999 HEA '#' PRI;

-- version
DEF sqld360_vYYNN = 'v1511';
DEF sqld360_vrsn = '&&sqld360_vYYNN. (2015-04-26)';
DEF sqld360_prefix = 'sqld360';

-- get dbid
COL sqld360_dbid NEW_V sqld360_dbid;
SELECT TRIM(TO_CHAR(dbid)) sqld360_dbid FROM v$database;

-- parameters
PRO
PRO Parameter 1: 
PRO SQL_ID of the SQL to be extracted (required)
PRO
COL sqld360_sqlid new_V sqld360_sqlid FOR A15;
SELECT TRIM('&1.') sqld360_sqlid FROM DUAL;
--set a bind too
VAR sqld360_sqlid VARCHAR2(13);
BEGIN 
  :sqld360_sqlid := '&&sqld360_sqlid.';
END;
/


BEGIN  
  -- if standalone execution then need to insert metadata   
  IF '&&from_edb360.' = '' THEN
    -- no need to clean, it's a GTT
    -- column options set to 1 is safe here, if no diagnostics then ASH is not extracted at all anyway
    INSERT INTO plan_table (statement_id, timestamp, operation, options) VALUES ('SQLD360_SQLID',sysdate,'&&sqld360_sqlid.','1');
    INSERT INTO plan_table (statement_id, timestamp, operation) VALUES ('SQLD360_ASH_LOAD',sysdate, NULL);
  END IF;
END;
/  
  

PRO
PRO Parameter 2: 
PRO If your Database is licensed to use the Oracle Tuning pack please enter T.
PRO If you have a license for Diagnostics pack but not for Tuning pack, enter D.
PRO Be aware value N reduces the output content substantially. Avoid N if possible.
PRO
PRO Oracle Pack License? (Tuning, Diagnostics or None) [ T | D | N ] (required)
COL license_pack NEW_V license_pack FOR A1;
SELECT NVL(UPPER(SUBSTR(TRIM('&2.'), 1, 1)), '?') license_pack FROM DUAL;
BEGIN
  IF NOT '&&license_pack.' IN ('T', 'D', 'N') THEN
    RAISE_APPLICATION_ERROR(-20000, 'Invalid Oracle Pack License "&&license_pack.". Valid values are T, D and N.');
  END IF;
END;
/
PRO
SET TERM OFF;
COL diagnostics_pack NEW_V diagnostics_pack FOR A1;
SELECT CASE WHEN '&&license_pack.' IN ('T', 'D') THEN 'Y' ELSE 'N' END diagnostics_pack FROM DUAL;
COL skip_diagnostics NEW_V skip_diagnostics FOR A1;
SELECT CASE WHEN '&&license_pack.' IN ('T', 'D') THEN NULL ELSE 'Y' END skip_diagnostics FROM DUAL;
COL tuning_pack NEW_V tuning_pack FOR A1;
SELECT CASE WHEN '&&license_pack.' = 'T' THEN 'Y' ELSE 'N' END tuning_pack FROM DUAL;
COL skip_tuning NEW_V skip_tuning FOR A1;
SELECT CASE WHEN '&&license_pack.' = 'T' THEN NULL ELSE 'Y' END skip_tuning FROM DUAL;
SET TERM ON;
SELECT 'Be aware value "N" reduces output content substantially. Avoid "N" if possible.' warning FROM dual WHERE '&&license_pack.' = 'N';
BEGIN
  IF '&&license_pack.' = 'N' THEN
    DBMS_LOCK.SLEEP(10); -- sleep few seconds
  END IF;
END;
/

COL history_days NEW_V history_days;
-- range: takes at least 31 days and at most as many as actual history, with a default of 31. parameter restricts within that range. 
SELECT TO_CHAR(LEAST(CEIL(SYSDATE - CAST(MIN(begin_interval_time) AS DATE)),  TO_NUMBER(NVL('&&sqld360_fromedb360_days.', '&&sqld360_conf_days.')))) history_days FROM dba_hist_snapshot WHERE '&&diagnostics_pack.' = 'Y' AND dbid = &&sqld360_dbid.;
SELECT '0' history_days FROM DUAL WHERE NVL(TRIM('&&diagnostics_pack.'), 'N') = 'N';

DEF skip_script = 'sql/sqld360_0f_skip_script.sql ';

-- get instance number
COL connect_instance_number NEW_V connect_instance_number;
SELECT TO_CHAR(instance_number) connect_instance_number FROM v$instance;

-- get instance name 
COL connect_instance_name NEW_V connect_instance_name;
SELECT TO_CHAR(instance_name) connect_instance_name FROM v$instance;

-- get database name (up to 10, stop before first '.', no special characters)
COL database_name_short NEW_V database_name_short FOR A10;
SELECT LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'DB_NAME'), 1, 10)) database_name_short FROM DUAL;
SELECT SUBSTR('&&database_name_short.', 1, INSTR('&&database_name_short..', '.') - 1) database_name_short FROM DUAL;
SELECT TRANSLATE('&&database_name_short.',
'abcdefghijklmnopqrstuvwxyz0123456789-_ ''`~!@#$%&*()=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyz0123456789-_') database_name_short FROM DUAL;

-- get host name (up to 30, stop before first '.', no special characters)
COL host_name_short NEW_V host_name_short FOR A30;
SELECT LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST'), 1, 30)) host_name_short FROM DUAL;
SELECT SUBSTR('&&host_name_short.', 1, INSTR('&&host_name_short..', '.') - 1) host_name_short FROM DUAL;
SELECT TRANSLATE('&&host_name_short.',
'abcdefghijklmnopqrstuvwxyz0123456789-_ ''`~!@#$%&*()=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyz0123456789-_') host_name_short FROM DUAL;

-- get rdbms version
COL db_version NEW_V db_version;
SELECT version db_version FROM v$instance;
DEF skip_10g = '';
COL skip_10g NEW_V skip_10g;
SELECT '--' skip_10g FROM v$instance WHERE version LIKE '10%';
DEF skip_11r1 = '';
COL skip_11r1 NEW_V skip_11r1;
SELECT '--' skip_11r1 FROM v$instance WHERE version LIKE '11.1%';
DEF skip_11r201 = '';
COL skip_11r201 NEW_V skip_11r201;
SELECT '--' skip_11r201 FROM v$instance WHERE version LIKE '11.2.0.1%';

-- get average number of CPUs
COL avg_cpu_count NEW_V avg_cpu_count FOR A3;
SELECT ROUND(AVG(TO_NUMBER(value))) avg_cpu_count FROM gv$system_parameter2 WHERE name = 'cpu_count';

-- get total number of CPUs
COL sum_cpu_count NEW_V sum_cpu_count FOR A3;
SELECT SUM(TO_NUMBER(value)) sum_cpu_count FROM gv$system_parameter2 WHERE name = 'cpu_count';

-- determine if rac or single instance (null means rac)
COL is_single_instance NEW_V is_single_instance FOR A1;
SELECT CASE COUNT(*) WHEN 1 THEN 'Y' END is_single_instance FROM gv$instance;

-- timestamp on filename
COL sqld360_file_time NEW_V sqld360_file_time FOR A20;
SELECT TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MI') sqld360_file_time FROM DUAL;

-- snapshot ranges
SELECT '0' history_days FROM DUAL WHERE TRIM('&&history_days.') IS NULL;
COL tool_sysdate NEW_V tool_sysdate;
SELECT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') tool_sysdate FROM DUAL;
COL as_of_date NEW_V as_of_date;
SELECT ', as of '||TO_CHAR(SYSDATE, 'Dy Mon DD @HH12:MIAM') as_of_date FROM DUAL;
COL minimum_snap_id NEW_V minimum_snap_id;
SELECT NVL(TO_CHAR(MAX(snap_id)), '0') minimum_snap_id FROM dba_hist_snapshot WHERE '&&diagnostics_pack.' = 'Y' AND dbid = &&sqld360_dbid. AND begin_interval_time < SYSDATE - &&history_days.;
SELECT '-1' minimum_snap_id FROM DUAL WHERE TRIM('&&minimum_snap_id.') IS NULL;
COL maximum_snap_id NEW_V maximum_snap_id;
SELECT NVL(TO_CHAR(MAX(snap_id)), '&&minimum_snap_id.') maximum_snap_id FROM dba_hist_snapshot WHERE '&&diagnostics_pack.' = 'Y' AND dbid = &&sqld360_dbid.;
SELECT '-1' maximum_snap_id FROM DUAL WHERE TRIM('&&maximum_snap_id.') IS NULL;

-- ebs
DEF ebs_release = '';
DEF ebs_system_name = '';
COL ebs_release NEW_V ebs_release;
COL ebs_system_name NEW_V ebs_system_name;
SELECT release_name ebs_release, applications_system_name ebs_system_name FROM applsys.fnd_product_groups WHERE ROWNUM = 1;

-- siebel
DEF siebel_schema = '';
DEF siebel_app_ver = '';
COL siebel_schema NEW_V siebel_schema;
COL siebel_app_ver NEW_V siebel_app_ver;
SELECT owner siebel_schema FROM sys.dba_tab_columns WHERE table_name = 'S_REPOSITORY' AND column_name = 'ROW_ID' AND data_type = 'VARCHAR2' AND ROWNUM = 1;
SELECT app_ver siebel_app_ver FROM &&siebel_schema..s_app_ver WHERE ROWNUM = 1;

-- psft
DEF psft_schema = '';
DEF psft_tools_rel = '';
COL psft_schema NEW_V psft_schema;
COL psft_tools_rel NEW_V psft_tools_rel;
SELECT owner psft_schema FROM sys.dba_tab_columns WHERE table_name = 'PSSTATUS' AND column_name = 'TOOLSREL' AND data_type = 'VARCHAR2' AND ROWNUM = 1;
SELECT toolsrel psft_tools_rel FROM &&psft_schema..psstatus WHERE ROWNUM = 1;

-- local or remote exec (local will be --) 
COL sqld360_remote_exec NEW_V sqld360_remote_exec FOR A20;
SELECT '--' sqld360_remote_exec FROM dual;
-- this SQL errors out in 11.1.0.6 and < 10.2.0.5, this is expected, the value is used only >= 11.2
SELECT CASE WHEN a.port <> 0 AND a.machine <> b.host_name THEN NULL ELSE '--' END sqld360_remote_exec FROM v$session a, v$instance b WHERE sid = USERENV('SID');


-- udump mnd pid, oved here from 0c_post
-- get udump directory path
COL sqld360_udump_path NEW_V sqld360_udump_path FOR A500;
SELECT value||DECODE(INSTR(value, '/'), 0, '\', '/') sqld360_udump_path FROM v$parameter2 WHERE name = 'user_dump_dest';

-- get diag_trace path
COL sqld360_diagtrace_path NEW_V sqld360_diagtrace_path FOR A500;
SELECT value||DECODE(INSTR(value, '/'), 0, '\', '/') sqld360_diagtrace_path FROM v$diag_info WHERE name = 'Diag Trace';

-- get pid
COL sqld360_spid NEW_V sqld360_spid FOR A5;
SELECT TO_CHAR(spid) sqld360_spid FROM v$session s, v$process p WHERE s.sid = SYS_CONTEXT('USERENV', 'SID') AND p.addr = s.paddr;

-- get sqltxt
COL sqld360_sqltxt NEW_V sqld360_sqltxt
SELECT SUBSTR(sql_text,1,50) sqld360_sqltxt FROM v$sqltext_with_newlines WHERE sql_id = '&&sqld360_sqlid.' AND piece = 0 AND rownum = 1;
SELECT SUBSTR(sql_text,1,50) sqld360_sqltxt FROM dba_hist_sqltext WHERE sql_id = '&&sqld360_sqlid.' AND rownum = 1;

-- get sql full text
VAR sqld360_fullsql CLOB;
EXEC :sqld360_fullsql := NULL;

BEGIN
 -- if available from AWR then grab it from there
 BEGIN
   SELECT sql_text
     INTO :sqld360_fullsql
     FROM dba_hist_sqltext
    WHERE sql_id = '&&sqld360_sqlid.';
 EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
 END;

  IF :sqld360_fullsql IS NULL THEN
   SELECT sql_fulltext
     INTO :sqld360_fullsql
     FROM gv$sql
    WHERE sql_id = '&&sqld360_sqlid.'
	  AND sql_fulltext IS NOT NULL
	  AND ROWNUM = 1;
  END IF;

END;
/

-- get exact_matching_signature, force_matching_signature
COL exact_matching_signature NEW_V exact_matching_signature FOR 99999999999999999999999
COL force_matching_signature NEW_V force_matching_signature FOR 99999999999999999999999

-- this is to set a fake value in case SQL is not in memory and AWR
SELECT 0 exact_matching_signature, 0 force_matching_signature
  FROM DUAL
/

SELECT DBMS_SQLTUNE.SQLTEXT_TO_SIGNATURE(:sqld360_fullsql,0) exact_matching_signature,
       DBMS_SQLTUNE.SQLTEXT_TO_SIGNATURE(:sqld360_fullsql,1) force_matching_signature
  FROM dual
/

COL skip_force_match NEW_V skip_force_match
SELECT CASE WHEN '&&exact_matching_signature.' = '&&force_matching_signature.' THEN '--' END skip_force_match 
  FROM DUAL
/

-- inclusion config determine skip flags
COL sqld360_skip_html NEW_V sqld360_skip_html;
COL sqld360_skip_text NEW_V sqld360_skip_text;
COL sqld360_skip_csv  NEW_V sqld360_skip_csv;
COL sqld360_skip_line NEW_V sqld360_skip_line;
COL sqld360_skip_pie  NEW_V sqld360_skip_pie;
COL sqld360_skip_bar  NEW_V sqld360_skip_bar;
COL sqld360_skip_tree NEW_V sqld360_skip_tree;

SELECT CASE '&&sqld360_conf_incl_html.' WHEN 'N' THEN '--' END sqld360_skip_html FROM DUAL;
SELECT CASE '&&sqld360_conf_incl_text.' WHEN 'N' THEN '--' END sqld360_skip_text FROM DUAL;
SELECT CASE '&&sqld360_conf_incl_csv.'  WHEN 'N' THEN '--' END sqld360_skip_csv  FROM DUAL;
SELECT CASE '&&sqld360_conf_incl_line.' WHEN 'N' THEN '--' END sqld360_skip_line FROM DUAL;
SELECT CASE '&&sqld360_conf_incl_pie.'  WHEN 'N' THEN '--' END sqld360_skip_pie  FROM DUAL;
SELECT CASE '&&sqld360_conf_incl_bar.'  WHEN 'N' THEN '--' END sqld360_skip_bar  FROM DUAL;
SELECT CASE '&&sqld360_conf_incl_tree.' WHEN 'N' THEN '--' END sqld360_skip_tree FROM DUAL;

COL sqld360_skip_ashrpt NEW_V sqld360_skip_ashrpt;
SELECT CASE '&&sqld360_conf_incl_ashrpt.' WHEN 'N' THEN '--' END sqld360_skip_ashrpt FROM DUAL;

COL sqld360_skip_sqlmon NEW_V sqld360_skip_sqlmon;
SELECT CASE '&&sqld360_conf_incl_sqlmon.' WHEN 'N' THEN '--' END sqld360_skip_sqlmon FROM DUAL;

COL sqld360_skip_eadam NEW_V sqld360_skip_eadam;
SELECT CASE '&&sqld360_conf_incl_eadam.' WHEN 'N' THEN '--' END sqld360_skip_eadam FROM DUAL;

COL sqld360_skip_rawash NEW_V sqld360_skip_rawash;
SELECT CASE '&&sqld360_conf_incl_rawash.' WHEN 'N' THEN '--' END sqld360_skip_rawash FROM DUAL;

-- setup
DEF sql_trace_level = '1';
DEF main_table = '';
DEF title = '';
DEF title_no_spaces = '';
DEF title_suffix = '';
DEF common_sqld360_prefix = '&&sqld360_prefix._&&database_name_short._&&sqld360_sqlid.';
DEF sqld360_main_report = '00001_&&common_sqld360_prefix._index';
DEF sqld360_log = '00002_&&common_sqld360_prefix._log';
-- this is for eDB360 to pull the log in case the execution fails
UPDATE plan_table SET remarks = '&&sqld360_log..txt'  WHERE statement_id = 'SQLD360_SQLID' and operation = '&&sqld360_sqlid.';
DEF sqld360_tkprof = '00003_&&common_sqld360_prefix._tkprof';
DEF sqld360_main_filename = '&&common_sqld360_prefix._&&host_name_short.';
DEF sqld360_log2 = '00004_&&common_sqld360_prefix._log2';
DEF sqld360_tracefile_identifier = '&&common_sqld360_prefix.';
DEF sqld360_copyright = ' (c) 2015';
DEF top_level_hints = 'NO_MERGE';
DEF sq_fact_hints = 'MATERIALIZE NO_MERGE';
DEF ds_hint = 'DYNAMIC_SAMPLING(4)';
DEF def_max_rows = '10000';
DEF max_rows = '1e4';
DEF num_parts = '100';
--DEF translate_lowhigh = 'Y';
DEF default_dir = 'SQLD360_DIR'
DEF sqlmon_date_mask = 'YYYYMMDDHH24MISS';
DEF sqlmon_text = 'Y';
DEF sqlmon_active = 'Y';
DEF sqlmon_max_reports = '12';
DEF ash_date_mask = 'YYYYMMDDHH24MISS';
DEF ash_text = 'Y';
DEF ash_html = 'Y';
DEF ash_mem = 'Y';
DEF ash_awr = 'Y';
DEF ash_max_reports = '12';
--DEF skip_tcb = '';
--DEF skip_ash_rpt = '--';
DEF skip_html = '';
DEF skip_text = '';
DEF skip_csv = '';
DEF skip_lch = 'Y';
DEF skip_pch = 'Y';
DEF skip_bch = 'Y';
DEF skip_tch = 'Y';
DEF skip_all = '';
DEF abstract = '';
DEF abstract2 = '';
DEF foot = '';
DEF sql_text = '';
DEF chartype = '';
DEF stacked = '';
DEF haxis = '&&db_version. dbname:&&database_name_short. host:&&host_name_short. (avg cpu_count: &&avg_cpu_count.)';
DEF vaxis = '';
DEF vbaseline = '';
DEF tit_01 = '';
DEF tit_02 = '';
DEF tit_03 = '';
DEF tit_04 = '';
DEF tit_05 = '';
DEF tit_06 = '';
DEF tit_07 = '';
DEF tit_08 = '';
DEF tit_09 = '';
DEF tit_10 = '';
DEF tit_11 = '';
DEF tit_12 = '';
DEF tit_13 = '';
DEF tit_14 = '';
DEF tit_15 = '';
DEF exadata = '';
DEF max_col_number = '1';
DEF column_number = '1';
COL skip_html NEW_V skip_html;
COL skip_text NEW_V skip_text;
COL skip_csv NEW_V skip_csv;
COL skip_lch NEW_V skip_lch;
COL skip_pch NEW_V skip_pch;
COL skip_bch NEW_V skip_bch;
COL skip_all NEW_V skip_all;
COL dummy_01 NOPRI;
COL dummy_02 NOPRI;
COL dummy_03 NOPRI;
COL dummy_04 NOPRI;
COL dummy_05 NOPRI;
COL dummy_06 NOPRI;
COL dummy_07 NOPRI;
COL dummy_08 NOPRI;
COL dummy_09 NOPRI;
COL dummy_10 NOPRI;
COL dummy_11 NOPRI;
COL dummy_12 NOPRI;
COL dummy_13 NOPRI;
COL dummy_14 NOPRI;
COL dummy_15 NOPRI;
COL sqld360_time_stamp NEW_V sqld360_time_stamp FOR A20;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD/HH24:MI:SS') sqld360_time_stamp FROM DUAL;
COL hh_mm_ss NEW_V hh_mm_ss FOR A8;
COL title_no_spaces NEW_V title_no_spaces;
COL spool_filename NEW_V spool_filename;
COL one_spool_filename NEW_V one_spool_filename;
VAR row_count NUMBER;
-- next two are using to hold the reports SQL
VAR sql_text CLOB;
VAR sql_text_backup CLOB;
--VAR sql_text_backup2 CLOB;
VAR sql_text_display CLOB;
VAR file_seq NUMBER;
EXEC :file_seq := 5;
VAR get_time_t0 NUMBER;
VAR get_time_t1 NUMBER;
-- Exadata
ALTER SESSION SET "_serial_direct_read" = ALWAYS;
ALTER SESSION SET "_small_table_threshold" = 1001;
-- nls
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ".,";
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD/HH24:MI:SS';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD/HH24:MI:SS.FF';
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD/HH24:MI:SS.FF TZH:TZM';
-- adding to prevent slow access to ASH with non default NLS settings
ALTER SESSION SET NLS_SORT = 'BINARY';
ALTER SESSION SET NLS_COMP = 'BINARY';
-- to work around bug 12672969
ALTER SESSION SET "_optimizer_order_by_elimination_enabled"=false; 
-- to work around bug 19567916
ALTER SESSION SET "_optimizer_aggr_groupby_elim"=false; 
-- to work around Siebel
ALTER SESSION SET optimizer_index_cost_adj = 100;
ALTER SESSION SET optimizer_dynamic_sampling = 2;
ALTER SESSION SET "_always_semi_join" = CHOOSE;
ALTER SESSION SET "_and_pruning_enabled" = TRUE;
ALTER SESSION SET "_subquery_pruning_enabled" = TRUE;
-- tracing script in case it takes long to execute so we can diagnose it
ALTER SESSION SET MAX_DUMP_FILE_SIZE = '1G';
ALTER SESSION SET TRACEFILE_IDENTIFIER = "&&sqld360_tracefile_identifier.";
--ALTER SESSION SET STATISTICS_LEVEL = 'ALL';
ALTER SESSION SET EVENTS '10046 TRACE NAME CONTEXT FOREVER, LEVEL &&sql_trace_level.';
SET TERM OFF; 
SET HEA ON; 
SET LIN 32767; 
SET NEWP NONE; 
SET PAGES &&def_max_rows.; 
SET LONG 32000; 
SET LONGC 2000; 
SET WRA ON; 
SET TRIMS ON; 
SET TRIM ON; 
SET TI OFF; 
SET TIMI OFF; 
SET ARRAY 1000; 
SET NUM 20; 
SET SQLBL ON; 
SET BLO .; 
SET RECSEP OFF;

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- log header
SPO &&sqld360_log..txt;
PRO begin log
PRO
DEF;
SPO OFF;

-- main header
SPO &&sqld360_main_report..html;
@@sqld360_0d_html_header.sql
PRO </head>
PRO <body>
PRO <h1><a href="http://www.enkitec.com" target="_blank">Enkitec</a>: SQL 360-degree view <em>(<a href="http://www.enkitec.com/products/sqld360" target="_blank">SQLd360</a>)</em> &&sqld360_vYYNN.</h1>
PRO
PRO <pre>
PRO sqlid:&&sqld360_sqlid. dbname:&&database_name_short. version:&&db_version. host:&&host_name_short. license:&&license_pack. days:&&history_days. today:&&sqld360_time_stamp.
PRO </pre>
PRO
SPO OFF;

-- zip
HOS zip -jq &&sqld360_main_filename._&&sqld360_file_time. js/sorttable.js
HOS zip -jq &&sqld360_main_filename._&&sqld360_file_time. js/SQLd360_img.jpg

--WHENEVER SQLERROR CONTINUE;
