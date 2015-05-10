@@&&edb360_0g.tkprof.sql
DEF section_id = '7b';
DEF section_name = 'SQL Sample';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');

SPO &&edb360_main_report..html APP;
PRO <h2 title="Top SQL as per ASH">&&section_name.</h2>
SPO OFF;
SET TERM ON;
PRO Please wait ...
SET TERM OFF; 

COL call_sqld360_bitmask NEW_V call_sqld360_bitmask FOR A6;
SELECT SUBSTR(
CASE '&&diagnostics_pack.' WHEN 'Y' THEN '1' ELSE '0' END||
CASE '&&tuning_pack.' WHEN 'Y' THEN '1' ELSE '0' END||
'0'|| -- TCB
--LPAD(TRIM('&&history_days.'), 3, '0')
LPAD(TRIM('&&edb360_conf_days.'), 3, '0')
, 1, 6) call_sqld360_bitmask
FROM DUAL;

DEF files_prefix = '';

-- watchdog
COL edb360_bypass NEW_V edb360_bypass;
SELECT '--bypass--' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds
/

COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;
SET VER OFF FEED OFF SERVEROUT ON HEAD OFF PAGES 50000 LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 1000;
SPO 99930_&&common_edb360_prefix._top_sql_driver.sql;
DECLARE
  l_count NUMBER := 0;
  PROCEDURE put_line(p_line IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put_line;
  PROCEDURE update_log(p_module IN VARCHAR2) IS
  BEGIN
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
		put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
		put_line('-- update log');
		put_line('SPO &&edb360_log..txt APP;');
        put_line('SET HEAD OFF TERM ON;');
		put_line('PRO '||CHR(38)||chr(38)||'hh_mm_ss. '||p_module);
		put_line('SELECT ''Elapsed Seconds so far: ''||((DBMS_UTILITY.GET_TIME - :edb360_time0) / 100) FROM DUAL;');
        put_line('SET HEAD ON TERM OFF;');
		put_line('SPO OFF;');
  END update_log;
BEGIN
  put_line('-- deleting content of global temporary table "plan_table" as preparation to execute sqld360');
  put_line('-- this delete affects nothing');
  put_line('DELETE plan_table;');
  FOR i IN (WITH ranked_sql AS (
            SELECT /*+ &&sq_fact_hints. &&ds_hint. */
                   dbid,
                   sql_id,
                   MAX(user_id) user_id,
                   MAX(module) module,
                   ROUND(COUNT(*) / 360, 6) db_time_hrs,
                   ROUND(SUM(CASE session_state WHEN 'ON CPU' THEN 1 ELSE 0 END) / 360, 6) cpu_time_hrs,
                   ROUND(SUM(CASE WHEN session_state = 'WAITING' AND wait_class IN ('User I/O', 'System I/O') THEN 1 ELSE 0 END) / 360, 6) io_time_hrs,
                   ROW_NUMBER () OVER (ORDER BY COUNT(*) DESC) rank_num
              FROM dba_hist_active_sess_history
             WHERE sql_id IS NOT NULL
               AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
               AND dbid = &&edb360_dbid.
               AND '&&edb360_bypass.' IS NULL
             GROUP BY
                   dbid,
                   sql_id
            HAVING COUNT(*) > 6 -- >1min
            ),
            top_sql AS (
            SELECT /*+ &&sq_fact_hints. */
                   r.sql_id,
                   TRIM(TO_CHAR(ROUND(r.db_time_hrs, 2), '9990.00')) db_time_hrs,
                   TRIM(TO_CHAR(ROUND(r.cpu_time_hrs, 2), '9990.00')) cpu_time_hrs,
                   TRIM(TO_CHAR(ROUND(r.io_time_hrs, 2), '9990.00')) io_time_hrs,
                   r.rank_num,
                   NVL((SELECT a.name FROM audit_actions a WHERE a.action = h.command_type), TO_CHAR(h.command_type)) command_type,
                   NVL((SELECT u.username FROM dba_users u WHERE u.user_id = r.user_id), TO_CHAR(r.user_id)) username,
                   r.module,
                   --h.sql_text,
                   CASE 
                   WHEN h.sql_text IS NULL THEN 'unknown'
                   ELSE REPLACE(REPLACE(REPLACE(REPLACE(DBMS_LOB.SUBSTR(h.sql_text, 1000), CHR(10), ' '), '"', CHR(38)||'#34;'), '>', CHR(38)||'#62;'), '<', CHR(38)||'#60;')
                   END sql_text_1000
              FROM ranked_sql r,
                   dba_hist_sqltext h
             WHERE r.rank_num <= &&edb360_conf_top_sql.
               AND h.dbid(+) = r.dbid
               AND h.sql_id(+) = r.sql_id
            )
            SELECT * FROM top_sql ORDER BY rank_num, sql_id)
  LOOP
    l_count := l_count + 1;
    put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
    put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
    put_line('-- update log');
    put_line('SPO &&edb360_log..txt APP;');
    put_line('PRO');
    put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    put_line('PRO');
    put_line('PRO rank:'||i.rank_num||' sql_id:'||i.sql_id);
    put_line('SPO OFF;');
    put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt >> &&edb360_log3..txt');
    put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log3..txt');
    put_line('-- update main report');
    put_line('SPO &&edb360_main_report..html APP;');
    put_line('PRO <li title="user:'||i.username||' module:'||i.module);
    put_line('PRO '||i.sql_text_1000||'">');
    put_line('PRO rank:'||i.rank_num||' '||i.sql_id||' et:'||i.db_time_hrs||'h cpu:'||i.cpu_time_hrs||'h io:'||i.io_time_hrs||'h type:'||SUBSTR(i.command_type, 1, 6));
    put_line('SET HEAD OFF VER OFF FEED OFF ECHO OFF;');
    put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
    put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    put_line('SPO OFF;');
    IF i.rank_num <= &&edb360_conf_planx_top. THEN
      put_line('COL edb360_bypass NEW_V edb360_bypass;');
      put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
      update_log('PLANX');
      put_line('@@'||CHR(38)||CHR(38)||'edb360_bypass.sql/planx.sql &&diagnostics_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="planx_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..txt">planx(text)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. planx_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..txt >> &&edb360_log3..txt');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqlmon_top. AND '&&skip_10g.' IS NULL AND '&&skip_diagnostics.' IS NULL AND '&&skip_tuning.' IS NULL THEN
      put_line('COL edb360_bypass NEW_V edb360_bypass;');
      put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
      update_log('SQLMON');
      put_line('@@'||CHR(38)||CHR(38)||'edb360_bypass.sql/sqlmon.sql &&tuning_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="sqlmon_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..zip">sqlmon(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. sqlmon_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..zip >> &&edb360_log3..txt');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqlash_top. AND '&&skip_diagnostics.' IS NULL THEN
      put_line('COL edb360_bypass NEW_V edb360_bypass;');
      put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
      update_log('SQLASH');
      put_line('@@'||CHR(38)||CHR(38)||'edb360_bypass.sql/sqlash.sql &&diagnostics_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="sqlash_'||i.sql_id||'.zip">sqlash(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. sqlash_'||i.sql_id||'.zip >> &&edb360_log3..txt');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqlhc_top. THEN
      put_line('COL edb360_bypass NEW_V edb360_bypass;');
      put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
      update_log('SQLHC');
      put_line('@@'||CHR(38)||CHR(38)||'edb360_bypass.sql/sqlhc.sql &&license_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="'||CHR(38)||chr(38)||'files_prefix..zip">sqlhc(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||CHR(38)||chr(38)||'files_prefix..zip >> &&edb360_log3..txt');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqld360_top. THEN
      put_line('COL edb360_bypass NEW_V edb360_bypass;');
      put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
      update_log('SQLD360');
      put_line('-- prepares execution of sqld360');
      put_line('INSERT INTO plan_table (statement_id, operation, options) VALUES (''SQLD360_SQLID'', '''||i.sql_id||''', ''&&call_sqld360_bitmask.'');');
      put_line('DELETE plan_table WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL AND statement_id = ''SQLD360_SQLID'' AND operation = '''||i.sql_id||''';');
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="sqld360_&&database_name_short._'||i.sql_id||'_&&host_name_short._&&edb360_file_time..zip">sqld360(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    END IF;
    put_line('-- update main report');
    put_line('SPO &&edb360_main_report..html APP;');
    put_line('PRO </li>');
    put_line('SPO OFF;');
    put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
  END LOOP;
  IF l_count > 0 THEN
    put_line('UNDEF 1');
    put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. 99930_&&common_edb360_prefix._top_sql_driver.sql >> &&edb360_log3..txt');
    put_line('SPO &&edb360_log..txt APP;');
    put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    put_line('PRO -- plan_table before calling sqld360');
    put_line('SELECT operation||'' ''||options sql_and_flags FROM plan_table WHERE statement_id = ''SQLD360_SQLID'';');
    put_line('SPO OFF;');
    put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt >> &&edb360_log3..txt');
    put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log3..txt');
    put_line('-- eadam (ash) for top sql');
    put_line('COL edb360_bypass NEW_V edb360_bypass;');
    put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
    put_line('EXEC DBMS_APPLICATION_INFO.SET_MODULE(''&&edb360_prefix.'',''eadam'');');
    put_line('@@sql/'||CHR(38)||CHR(38)||'edb360_bypass.&&skip_diagnostics.&&edb360_7c.eadam.sql');
    put_line('-- sqld360');
    put_line('COL edb360_bypass NEW_V edb360_bypass;');
    put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
    put_line('EXEC DBMS_APPLICATION_INFO.SET_MODULE(''&&edb360_prefix.'',''sqld360'');');
    put_line('@@sql/'||CHR(38)||CHR(38)||'edb360_bypass.sqld360.sql');
  END IF;
END;
/
SPO OFF;
HOS zip &&edb360_main_filename._&&edb360_file_time. 99930_&&common_edb360_prefix._top_sql_driver.sql >> &&edb360_log3..txt

SET TERM ON;
PRO Please wait ...
SET TERM OFF; 

-- execute dynamic script with sqld360 and others
@99930_&&common_edb360_prefix._top_sql_driver.sql;

SET TERM ON;
PRO Please wait ...
SET TERM OFF; 

-- closing
SET VER OFF FEED OFF SERVEROUT ON HEAD OFF PAGES 50000 LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 1000;
SPO 99950_&&common_edb360_prefix._top_sql_driver.sql;
DECLARE
  l_count NUMBER := 0;
  PROCEDURE put_line(p_line IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put_line;
  PROCEDURE update_log(p_module IN VARCHAR2) IS
  BEGIN
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
		put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
		put_line('-- update log');
		put_line('SPO &&edb360_log..txt APP;');
		put_line('PRO '||CHR(38)||chr(38)||'hh_mm_ss. '||p_module);
		put_line('SPO OFF;');
  END update_log;
BEGIN
  put_line('SPO &&edb360_log..txt APP;');
  put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  put_line('PRO -- plan_table after calling sqld360');
  put_line('SELECT operation||'' ''||remarks FROM plan_table WHERE statement_id = ''SQLD360_SQLID'';');
  put_line('SPO OFF;');
  put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt >> &&edb360_log3..txt');
  put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log3..txt');
  FOR i IN (SELECT operation, remarks FROM plan_table WHERE statement_id = 'SQLD360_SQLID')
  LOOP
    l_count := l_count + 1;
    put_line('HOS mv '||i.remarks||' sqld360_&&database_name_short._'||i.operation||'_&&host_name_short._&&edb360_file_time..zip >> &&edb360_log3..txt');
    put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. sqld360_&&database_name_short._'||i.operation||'_&&host_name_short._&&edb360_file_time..zip >> &&edb360_log3..txt');
  END LOOP;
  IF l_count > 0 THEN
    put_line('-- just in case individual file "mv" failed');
    put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. sqld360_*.zip >> &&edb360_log3..txt');
    put_line('-- deleting content of global temporary table "plan_table" as cleanup after sqld360');
    put_line('-- this delete affects nothing');
    put_line('DELETE plan_table;');
  END IF;
END;
/
SPO OFF;
HOS zip &&edb360_main_filename._&&edb360_file_time. 99950_&&common_edb360_prefix._top_sql_driver.sql >> &&edb360_log3..txt

SET TERM ON;
PRO Please wait ...
SET TERM OFF; 

-- execute dynamic script to rename sqld360 files and copy them into main zip
@99950_&&common_edb360_prefix._top_sql_driver.sql;

SET TERM ON;
PRO Please wait ...
SET TERM OFF; 

-- closing
@@&&edb360_0g.tkprof.sql
SET SERVEROUT OFF HEAD ON PAGES &&def_max_rows.;
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 99930_&&common_edb360_prefix._top_sql_driver.sql 99950_&&common_edb360_prefix._top_sql_driver.sql sqld360_driver.sql >> &&edb360_log3..txt
SET HEA ON LIN 32767 NEWP NONE PAGES &&def_max_rows. LONG 32000 LONGC 2000 WRA ON TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 1000 NUM 20 SQLBL ON BLO . RECSEP OFF;
COL row_num FOR 9999999 HEA '#' PRI;


