@@&&edb360_0g.tkprof.sql
DEF section_id = '7b';
DEF section_name = 'SQL Sample';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');

SPO &&edb360_main_report..html APP;
PRO <h2 title="Top SQL as per ASH">&&section_name.</h2>
SPO OFF;

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

COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;
SET VER OFF FEED OFF SERVEROUT ON HEAD OFF PAGES 50000 LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100;
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
		put_line('PRO '||CHR(38)||chr(38)||'hh_mm_ss. '||p_module);
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
                   ROUND(COUNT(*) / 360, 6) db_time_hrs,
                   ROUND(SUM(CASE session_state WHEN 'ON CPU' THEN 1 ELSE 0 END) / 360, 6) cpu_time_hrs,
                   ROW_NUMBER () OVER (ORDER BY COUNT(*) DESC) rank_num
              FROM dba_hist_active_sess_history
             WHERE sql_id IS NOT NULL
               AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
               AND dbid = &&edb360_dbid.
             GROUP BY
                   dbid,
                   sql_id
            HAVING COUNT(*) > 6 -- >1min
            ),
            top_sql AS (
            SELECT /*+ &&sq_fact_hints. */
                   r.sql_id,
                   TO_CHAR(ROUND(r.db_time_hrs, 2), '9990.00') db_time_hrs,
                   TO_CHAR(ROUND(r.cpu_time_hrs, 2), '9990.00') cpu_time_hrs,
                   r.rank_num,
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
             ORDER BY
                   r.sql_id
            )
            SELECT * FROM top_sql ORDER BY sql_id)
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
    put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt');
    put_line('-- update main report');
    put_line('SPO &&edb360_main_report..html APP;');
    put_line('PRO <li title="'||i.sql_text_1000||'">'||i.sql_id||' rank:'||i.rank_num||' et:'||i.db_time_hrs||'h cpu:'||i.cpu_time_hrs||'h');
    put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html');
    put_line('SPO OFF;');
    IF i.rank_num <= &&edb360_conf_planx_top. THEN
      update_log('PLANX');
      put_line('@@sql/planx.sql &&diagnostics_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="planx_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..txt">planx(text)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -mq &&edb360_main_filename._&&edb360_file_time. planx_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..txt');
      put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqlmon_top. AND '&&skip_10g.' IS NULL AND '&&skip_diagnostics.' IS NULL AND '&&skip_tuning.' IS NULL THEN
      update_log('SQLMON');
      put_line('@@sql/sqlmon.sql &&tuning_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="sqlmon_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..zip">sqlmon(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -mq &&edb360_main_filename._&&edb360_file_time. sqlmon_'||i.sql_id||'_'||CHR(38)||chr(38)||'current_time..zip');
      put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqlash_top. AND '&&skip_diagnostics.' IS NULL THEN
      update_log('SQLASH');
      put_line('@@sql/sqlash.sql &&diagnostics_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="sqlash_'||i.sql_id||'.zip">sqlash(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -mq &&edb360_main_filename._&&edb360_file_time. sqlash_'||i.sql_id||'.zip');
      put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqlhc_top. THEN
      update_log('SQLHC');
      put_line('@@sql/sqlhc.sql &&license_pack. '||i.sql_id);
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="'||CHR(38)||chr(38)||'files_prefix..zip">sqlhc(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -mq &&edb360_main_filename._&&edb360_file_time. '||CHR(38)||chr(38)||'files_prefix..zip');
      put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html');
    END IF;
    IF i.rank_num <= &&edb360_conf_sqld360_top. THEN
      update_log('SQLD360');
      put_line('-- prepares execution of sqld360');
      put_line('INSERT INTO plan_table (statement_id, operation, options) VALUES (''SQLD360_SQLID'', '''||i.sql_id||''', ''&&call_sqld360_bitmask.'');');
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <a href="sqld360_&&database_name_short._'||i.sql_id||'_&&host_name_short._&&edb360_file_time..zip">sqld360(zip)</a>');
      put_line('SPO OFF;');
      put_line('-- zip');
      put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html');
    END IF;
    put_line('-- update main report');
    put_line('SPO &&edb360_main_report..html APP;');
    put_line('PRO </li>');
    put_line('SPO OFF;');
    put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html');
  END LOOP;
  IF l_count > 0 THEN
    put_line('UNDEF 1');
    put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. 99930_&&common_edb360_prefix._top_sql_driver.sql;');
    put_line('SPO &&edb360_log..txt APP;');
    put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    put_line('PRO -- plan_table before calling sqld360');
    put_line('SELECT operation||'' ''||options sql_and_flags FROM plan_table WHERE statement_id = ''SQLD360_SQLID'';');
    put_line('SPO OFF;');
    put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt');
    put_line('-- eadam (ash) for top sql');
    put_line('EXEC DBMS_APPLICATION_INFO.SET_MODULE(''&&edb360_prefix.'',''eadam'');');
    put_line('@@sql/&&skip_diagnostics.&&edb360_7c.eadam.sql');
    put_line('-- sqld360');
    put_line('EXEC DBMS_APPLICATION_INFO.SET_MODULE(''&&edb360_prefix.'',''sqld360'');');
    put_line('@@sql/sqld360.sql');
  END IF;
END;
/
SPO OFF;
HOS zip -q &&edb360_main_filename._&&edb360_file_time. 99930_&&common_edb360_prefix._top_sql_driver.sql;

-- execute dynamic script with sqld360 and others
@99930_&&common_edb360_prefix._top_sql_driver.sql;

-- closing
SET VER OFF FEED OFF SERVEROUT ON HEAD OFF PAGES 50000 LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100;
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
  put_line('HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt');
  FOR i IN (SELECT operation, remarks FROM plan_table WHERE statement_id = 'SQLD360_SQLID')
  LOOP
    l_count := l_count + 1;
    put_line('HOS mv '||i.remarks||' sqld360_&&database_name_short._'||i.operation||'_&&host_name_short._&&edb360_file_time..zip');
    put_line('HOS zip -mq &&edb360_main_filename._&&edb360_file_time. sqld360_&&database_name_short._'||i.operation||'_&&host_name_short._&&edb360_file_time..zip');
  END LOOP;
  IF l_count > 0 THEN
    put_line('-- just in case individual file "mv" failed');
    put_line('HOS zip -mq &&edb360_main_filename._&&edb360_file_time. sqld360_*.zip');
    put_line('-- deleting content of global temporary table "plan_table" as cleanup after sqld360');
    put_line('-- this delete affects nothing');
    put_line('DELETE plan_table;');
  END IF;
END;
/
SPO OFF;
HOS zip -q &&edb360_main_filename._&&edb360_file_time. 99950_&&common_edb360_prefix._top_sql_driver.sql;

-- execute dynamic script to rename sqld360 files and copy them into main zip
@99950_&&common_edb360_prefix._top_sql_driver.sql;

-- closing
@@&&edb360_0g.tkprof.sql
SET SERVEROUT OFF HEAD ON PAGES &&def_max_rows.;
HOS zip -mq &&edb360_main_filename._&&edb360_file_time. 99930_&&common_edb360_prefix._top_sql_driver.sql 99950_&&common_edb360_prefix._top_sql_driver.sql sqld360_driver.sql
SET HEA ON LIN 32767 NEWP NONE PAGES &&def_max_rows. LONG 32000 LONGC 2000 WRA ON TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100 NUM 20 SQLBL ON BLO . RECSEP OFF;
CL COL;
COL row_num FOR 9999999 HEA '#' PRI;


