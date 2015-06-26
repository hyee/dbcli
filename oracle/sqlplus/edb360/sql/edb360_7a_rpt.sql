@@&&edb360_0g.tkprof.sql
DEF section_id = '7a';
DEF section_name = 'AWR/ADDM/ASH Reports';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SET VER OFF FEED OFF SERVEROUT ON HEAD OFF PAGES 50000 LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 1000;
SPO &&edb360_main_report..html APP;
PRO <h2 title="For max/min/med 'DB time' + 'background elapsed time' history (for each instance)">&&section_name.</h2>
SPO OFF;
SET TERM ON;
PRO Please wait ...
SET TERM OFF; 
-- watchdog
COL edb360_bypass NEW_V edb360_bypass;
SELECT '--bypass--' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds
/
COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;
SPO 99910_&&common_edb360_prefix._rpt_driver.sql;
PRO VAR inst_num VARCHAR2(1023);;
DECLARE
  l_standard_filename VARCHAR2(32767);
  l_spool_filename VARCHAR2(32767);
  l_one_spool_filename VARCHAR2(32767);
  l_instances NUMBER;
  l_begin_date VARCHAR2(14);
  l_end_date VARCHAR2(14);
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
        put_line('SET TERM ON;');
		put_line('PRO '||CHR(38)||CHR(38)||'hh_mm_ss. &&section_id. '||p_module);
		put_line('SELECT ''Elapsed Seconds so far: ''||((DBMS_UTILITY.GET_TIME - :edb360_time0) / 100) FROM DUAL;');
        put_line('SET TERM OFF;');
		put_line('SPO OFF;');
  END update_log;
BEGIN
  SELECT COUNT(*) INTO l_instances FROM gv$instance;
  
  -- all nodes
  IF l_instances > 1 AND '&&edb360_bypass.' IS NULL THEN
    FOR j IN (WITH
              expensive2 AS (
              SELECT /*+ &&sq_fact_hints. &&ds_hint. */
                     h.dbid, 
                     LAG(h.snap_id) OVER (PARTITION BY h.dbid, h.instance_number, h.stat_id ORDER BY h.snap_id) bid,
                     h.snap_id eid,
                     CAST(s.begin_interval_time AS DATE) begin_date,
                     CAST(s.end_interval_time AS DATE) end_date,
                     h.value - LAG(h.value) OVER (PARTITION BY h.dbid, h.instance_number, h.stat_id ORDER BY h.snap_id) value,
                     s.startup_time - LAG(s.startup_time) OVER (PARTITION BY h.dbid, h.instance_number, h.stat_id ORDER BY h.snap_id) startup_time_interval
                FROM dba_hist_sys_time_model h,
                     dba_hist_snapshot s
               WHERE h.stat_name IN ('DB time', 'background elapsed time')
                 AND h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
                 AND h.dbid = &&edb360_dbid.
                 AND s.snap_id = h.snap_id
                 AND s.dbid = h.dbid
                 AND s.instance_number = h.instance_number
                 AND s.end_interval_time - s.begin_interval_time > TO_DSINTERVAL('+00 00:01:00.000000') -- exclude snaps less than 1m appart
                 AND s.end_interval_time BETWEEN TO_TIMESTAMP('&&edb360_date_to.', 'YYYY-MM-DD') - TO_DSINTERVAL('+&&history_days. 00:00:00.000000') AND TO_TIMESTAMP('&&edb360_date_to.', 'YYYY-MM-DD') -- includes all options
              ),
              expensive AS (
              SELECT /*+ &&sq_fact_hints. */ dbid, bid, eid, begin_date, end_date, SUM(value) value
                FROM expensive2
               WHERE startup_time_interval = TO_DSINTERVAL('+00 00:00:00.000000') -- include only snaps from same startup
                 AND value > 0
               GROUP BY
                     dbid, bid, eid, begin_date, end_date
              ),
              max_&&hist_work_days.wd1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_&&hist_work_days.wd2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1)
              ),
              max_&&hist_work_days.wd3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd2)
              ),
              min_&&hist_work_days.wd AS (
              SELECT /*+ &&sq_fact_hints. */ MIN(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_&&history_days.d1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd2
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd3)
              ),
              max_&&history_days.d2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION 
                                   SELECT value FROM max_&&hist_work_days.wd2
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd3
                                   UNION
                                   SELECT value FROM max_&&history_days.d1)
              ),
              max_&&history_days.d3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION 
                                   SELECT value FROM max_&&hist_work_days.wd2
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd3
                                   UNION
                                   SELECT value FROM max_&&history_days.d1
                                   UNION
                                   SELECT value FROM max_&&history_days.d2)
              ),
              med_&&history_days.d AS (
              SELECT /*+ &&sq_fact_hints. */ PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
              ),
              max_5wd1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_5wd2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_5wd1)
              ),
              max_5wd3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2)
              ),
              min_5wd AS (
              SELECT /*+ &&sq_fact_hints. */ MIN(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_7d1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2
                                   UNION
                                   SELECT value FROM max_5wd3)
              ),
              max_7d2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2
                                   UNION
                                   SELECT value FROM max_5wd3
                                   UNION
                                   SELECT value FROM max_7d1)
              ),
              max_7d3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2
                                   UNION
                                   SELECT value FROM max_5wd3
                                   UNION
                                   SELECT value FROM max_7d1
                                   UNION
                                   SELECT value FROM max_7d2)
              ),
              med_7d AS (
              SELECT /*+ &&sq_fact_hints. */ PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
              )
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&hist_work_days.wd1' rep, 50 ob
                FROM expensive e,
                     max_&&hist_work_days.wd1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&hist_work_days.wd2' rep, 53 ob
                FROM expensive e,
                     max_&&hist_work_days.wd2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&hist_work_days.wd3' rep, 56 ob
                FROM expensive e,
                     max_&&hist_work_days.wd3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'min&&hist_work_days.wd' rep, 100 ob
                FROM expensive e,
                     min_&&hist_work_days.wd m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&history_days.d1' rep, 60 ob
                FROM expensive e,
                     max_&&history_days.d1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&history_days.d2' rep, 63 ob
                FROM expensive e,
                     max_&&history_days.d2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&history_days.d3' rep, 66 ob
                FROM expensive e,
                     max_&&history_days.d3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'med&&history_days.d' rep, 80 ob
                FROM expensive e,
                     med_&&history_days.d m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max5wd1' rep, 30 ob
                FROM expensive e,
                     max_5wd1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max5wd2' rep, 33 ob
                FROM expensive e,
                     max_5wd2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max5wd3' rep, 36 ob
                FROM expensive e,
                     max_5wd3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'min5wd' rep, 90 ob
                FROM expensive e,
                     min_5wd m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max7d1' rep, 40 ob
                FROM expensive e,
                     max_7d1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max7d2' rep, 43 ob
                FROM expensive e,
                     max_7d2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max7d3' rep, 46 ob
                FROM expensive e,
                     max_7d3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'med7d' rep, 70 ob
                FROM expensive e,
                     med_7d m
               WHERE m.value = e.value
               ORDER BY 7)
    LOOP
      l_begin_date := TO_CHAR(j.begin_date, 'YYYYMMDDHH24MISS');
      l_end_date := TO_CHAR(j.end_date, 'YYYYMMDDHH24MISS');
      
      -- main report
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <li>rac_'||j.bid||'_'||j.eid||'_'||j.rep||' <small><em>('||TO_CHAR(j.end_date,'DD-Mon-YY HH24:MI:SS')||')</em></small>');
      put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
      put_line('SPO OFF;');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');

      -- awr all modes
      IF '&&edb360_conf_incl_awr_rpt.' = 'Y' AND l_instances > 1 AND '&&db_version.' >= '11' THEN
        put_line('COL edb360_bypass NEW_V edb360_bypass;');
        put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
        l_standard_filename := 'awrrpt_rac_'||j.bid||'_'||j.eid||'_'||j.rep;
        l_spool_filename := '&&common_edb360_prefix._'||l_standard_filename;
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
        put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
        put_line('-- update log');
        put_line('SPO &&edb360_log..txt APP;');
        put_line('PRO');
        put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
        put_line('PRO');
        put_line('PRO '||CHR(38)||CHR(38)||'hh_mm_ss. '||l_spool_filename);
        put_line('SPO OFF;');
        put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt >> &&edb360_log3..txt');
        put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log3..txt');
        IF '&&edb360_skip_html.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.html');
          put_line('SPO '||l_one_spool_filename||'.html;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.awr_global_report_html('||j.dbid||',:inst_num,'||j.bid||','||j.eid||',8)) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.html">awr html</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.html >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
        IF '&&edb360_skip_text.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.txt');
          put_line('SPO '||l_one_spool_filename||'.txt;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.awr_global_report_text('||j.dbid||',:inst_num,'||j.bid||','||j.eid||',8)) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.txt">awr text</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.txt >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
      END IF;

      -- addm all nodes
      IF '&&edb360_conf_incl_addm_rpt.' = 'Y' AND l_instances > 1 THEN
        put_line('COL edb360_bypass NEW_V edb360_bypass;');
        put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
        put_line('VAR l_task_name VARCHAR2(30);');
        put_line('BEGIN');
        put_line('  :l_task_name := ''ADDM_''||TO_CHAR(SYSDATE, ''YYYYMMDD_HH24MISS'');');
        put_line('  DBMS_ADVISOR.CREATE_TASK(advisor_name => ''ADDM'', task_name =>  :l_task_name);');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''START_SNAPSHOT'', value => '||j.bid||');');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''END_SNAPSHOT'', value => '||j.eid||');');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''DB_ID'', value => '||j.dbid||');');
        put_line('  '||CHR(38)||CHR(38)||'edb360_bypass.DBMS_ADVISOR.EXECUTE_TASK(task_name => :l_task_name);');
        put_line('END;');
        put_line('/');
        put_line('PRINT l_task_name;');
        l_standard_filename := 'addmrpt_rac_'||j.bid||'_'||j.eid||'_'||j.rep;
        l_spool_filename := '&&common_edb360_prefix._'||l_standard_filename;
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
        put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
        put_line('-- update log');
        put_line('SPO &&edb360_log..txt APP;');
        put_line('PRO');
        put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
        put_line('PRO');
        put_line('PRO '||CHR(38)||CHR(38)||'hh_mm_ss. '||l_spool_filename);
        put_line('SPO OFF;');
        --IF '&&edb360_skip_text.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.txt');
          put_line('SPO '||l_one_spool_filename||'.txt;');
          put_line('SELECT DBMS_ADVISOR.get_task_report(:l_task_name) FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL FROM DUAL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.txt">addm text</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.txt >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        --END IF;
        put_line('EXEC DBMS_ADVISOR.DELETE_TASK(task_name => :l_task_name);');
      END IF;
      
      -- ash all nodes
      IF '&&edb360_conf_incl_ash_rpt.' = 'Y' AND l_instances > 1 AND '&&db_version.' >= '11' THEN
        put_line('COL edb360_bypass NEW_V edb360_bypass;');
        put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
        l_standard_filename := 'ashrpt_rac_'||j.bid||'_'||j.eid||'_'||j.rep;
        l_spool_filename := '&&common_edb360_prefix._'||l_standard_filename;
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
        put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
        put_line('-- update log');
        put_line('SPO &&edb360_log..txt APP;');
        put_line('PRO');
        put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
        put_line('PRO');
        put_line('PRO '||CHR(38)||CHR(38)||'hh_mm_ss. '||l_spool_filename);
        put_line('SPO OFF;');
        IF '&&edb360_skip_html.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.html');
          put_line('SPO '||l_one_spool_filename||'.html;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.ash_global_report_html('||j.dbid||',:inst_num,TO_DATE('''||l_begin_date||''',''YYYYMMDDHH24MISS''),TO_DATE('''||l_end_date||''',''YYYYMMDDHH24MISS''))) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.html">ash html</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.html >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
        IF '&&edb360_skip_text.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.txt');
          put_line('SPO '||l_one_spool_filename||'.txt;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.ash_global_report_text('||j.dbid||',:inst_num,TO_DATE('''||l_begin_date||''',''YYYYMMDDHH24MISS''),TO_DATE('''||l_end_date||''',''YYYYMMDDHH24MISS''))) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.txt">ash text</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.txt >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
      END IF;
              
      -- main report
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO </li>');
      put_line('SPO OFF;');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    END LOOP;
  END IF;

  -- each instance
  FOR i IN (SELECT instance_number
              FROM gv$instance
             WHERE '&&diagnostics_pack.' = 'Y'
               AND '&&edb360_bypass.' IS NULL
             ORDER BY
                   instance_number)
  LOOP
    FOR j IN (WITH
              expensive2 AS (
              SELECT /*+ &&sq_fact_hints. &&ds_hint. */
                     h.dbid, 
                     LAG(h.snap_id) OVER (PARTITION BY h.dbid, h.instance_number, h.stat_id ORDER BY h.snap_id) bid,
                     h.snap_id eid,
                     CAST(s.begin_interval_time AS DATE) begin_date,
                     CAST(s.end_interval_time AS DATE) end_date,
                     h.value - LAG(h.value) OVER (PARTITION BY h.dbid, h.instance_number, h.stat_id ORDER BY h.snap_id) value,
                     s.startup_time - LAG(s.startup_time) OVER (PARTITION BY h.dbid, h.instance_number, h.stat_id ORDER BY h.snap_id) startup_time_interval
                FROM dba_hist_sys_time_model h,
                     dba_hist_snapshot s
               WHERE h.instance_number = i.instance_number
                 AND h.stat_name IN ('DB time', 'background elapsed time')
                 AND h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
                 AND h.dbid = &&edb360_dbid.
                 AND s.snap_id = h.snap_id
                 AND s.dbid = h.dbid
                 AND s.instance_number = h.instance_number
                 AND s.end_interval_time - s.begin_interval_time > TO_DSINTERVAL('+00 00:01:00.000000') -- exclude snaps less than 1m appart
                 AND s.end_interval_time BETWEEN TO_TIMESTAMP('&&edb360_date_to.', 'YYYY-MM-DD') - TO_DSINTERVAL('+&&history_days. 00:00:00.000000') AND TO_TIMESTAMP('&&edb360_date_to.', 'YYYY-MM-DD') -- includes all options
              ),
              expensive AS (
              SELECT /*+ &&sq_fact_hints. */ dbid, bid, eid, begin_date, end_date, SUM(value) value
                FROM expensive2
               WHERE startup_time_interval = TO_DSINTERVAL('+00 00:00:00.000000') -- include only snaps from same startup
                 AND value > 0
               GROUP BY
                     dbid, bid, eid, begin_date, end_date
              ),
              max_&&hist_work_days.wd1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_&&hist_work_days.wd2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1)
              ),
              max_&&hist_work_days.wd3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd2)
              ),
              min_&&hist_work_days.wd AS (
              SELECT /*+ &&sq_fact_hints. */ MIN(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_&&history_days.d1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd2
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd3)
              ),
              max_&&history_days.d2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION 
                                   SELECT value FROM max_&&hist_work_days.wd2
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd3
                                   UNION
                                   SELECT value FROM max_&&history_days.d1)
              ),
              max_&&history_days.d3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_&&hist_work_days.wd1
                                   UNION 
                                   SELECT value FROM max_&&hist_work_days.wd2
                                   UNION
                                   SELECT value FROM max_&&hist_work_days.wd3
                                   UNION
                                   SELECT value FROM max_&&history_days.d1
                                   UNION
                                   SELECT value FROM max_&&history_days.d2)
              ),
              med_&&history_days.d AS (
              SELECT /*+ &&sq_fact_hints. */ PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - &&history_days. AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 -- avoids selecting same twice
              ),
              max_5wd1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_5wd2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_5wd1)
              ),
              max_5wd3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2)
              ),
              min_5wd AS (
              SELECT /*+ &&sq_fact_hints. */ MIN(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND TO_CHAR(end_date, 'D') BETWEEN '2' AND '6' /* between Monday and Friday */
                 AND TO_CHAR(end_date, 'HH24MM') BETWEEN '&&edb360_conf_work_time_from.' AND '&&edb360_conf_work_time_to.' 
              ),
              max_7d1 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2
                                   UNION
                                   SELECT value FROM max_5wd3)
              ),
              max_7d2 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2
                                   UNION
                                   SELECT value FROM max_5wd3
                                   UNION
                                   SELECT value FROM max_7d1)
              ),
              max_7d3 AS (
              SELECT /*+ &&sq_fact_hints. */ MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
                 AND value NOT IN (SELECT value FROM max_5wd1
                                   UNION
                                   SELECT value FROM max_5wd2
                                   UNION
                                   SELECT value FROM max_5wd3
                                   UNION
                                   SELECT value FROM max_7d1
                                   UNION
                                   SELECT value FROM max_7d2)
              ),
              med_7d AS (
              SELECT /*+ &&sq_fact_hints. */ PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 8 AND TO_DATE('&&edb360_date_to.', 'YYYY-MM-DD') - 1 -- avoids selecting same twice
              )
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&hist_work_days.wd1' rep, 50 ob
                FROM expensive e,
                     max_&&hist_work_days.wd1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&hist_work_days.wd2' rep, 53 ob
                FROM expensive e,
                     max_&&hist_work_days.wd2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&hist_work_days.wd3' rep, 56 ob
                FROM expensive e,
                     max_&&hist_work_days.wd3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'min&&hist_work_days.wd' rep, 100 ob
                FROM expensive e,
                     min_&&hist_work_days.wd m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&history_days.d1' rep, 60 ob
                FROM expensive e,
                     max_&&history_days.d1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&history_days.d2' rep, 63 ob
                FROM expensive e,
                     max_&&history_days.d2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max&&history_days.d3' rep, 66 ob
                FROM expensive e,
                     max_&&history_days.d3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'med&&history_days.d' rep, 80 ob
                FROM expensive e,
                     med_&&history_days.d m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max5wd1' rep, 30 ob
                FROM expensive e,
                     max_5wd1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max5wd2' rep, 33 ob
                FROM expensive e,
                     max_5wd2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max5wd3' rep, 36 ob
                FROM expensive e,
                     max_5wd3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'min5wd' rep, 90 ob
                FROM expensive e,
                     min_5wd m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max7d1' rep, 40 ob
                FROM expensive e,
                     max_7d1 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max7d2' rep, 43 ob
                FROM expensive e,
                     max_7d2 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'max7d3' rep, 46 ob
                FROM expensive e,
                     max_7d3 m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date, 'med7d' rep, 70 ob
                FROM expensive e,
                     med_7d m
               WHERE m.value = e.value
               ORDER BY 7)
    LOOP
      l_begin_date := TO_CHAR(j.begin_date, 'YYYYMMDDHH24MISS');
      l_end_date := TO_CHAR(j.end_date, 'YYYYMMDDHH24MISS');
      
      -- main report
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO <li>'||i.instance_number||'_'||j.bid||'_'||j.eid||'_'||j.rep||' <small><em>('||TO_CHAR(j.end_date,'DD-Mon-YY HH24:MI:SS')||')</em></small>');
      put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
      put_line('SPO OFF;');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');

      -- awr one node
      IF '&&edb360_conf_incl_awr_rpt.' = 'Y' THEN 
        put_line('COL edb360_bypass NEW_V edb360_bypass;');
        put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
        l_standard_filename := 'awrrpt_'||i.instance_number||'_'||j.bid||'_'||j.eid||'_'||j.rep;
        l_spool_filename := '&&common_edb360_prefix._'||l_standard_filename;
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
        put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
        put_line('-- update log');
        put_line('SPO &&edb360_log..txt APP;');
        put_line('PRO');
        put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
        put_line('PRO');
        put_line('PRO '||CHR(38)||CHR(38)||'hh_mm_ss. '||l_spool_filename);
        put_line('SPO OFF;');
        put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt >> &&edb360_log3..txt');
        put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log3..txt');
        IF '&&edb360_conf_incl_awr_rpt.' = 'Y' AND '&&edb360_skip_html.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.html');
          put_line('SPO '||l_one_spool_filename||'.html;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.awr_report_html('||j.dbid||','||i.instance_number||','||j.bid||','||j.eid||',8)) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.html">awr html</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.html >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
        IF '&&edb360_conf_incl_awr_rpt.' = 'Y' AND '&&edb360_skip_text.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.txt');
          put_line('SPO '||l_one_spool_filename||'.txt;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.awr_report_text('||j.dbid||','||i.instance_number||','||j.bid||','||j.eid||',8)) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.txt">awr text</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.txt >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
     END IF;

      -- addm one node
      IF '&&edb360_conf_incl_addm_rpt.' = 'Y' THEN 
        put_line('COL edb360_bypass NEW_V edb360_bypass;');
        put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
        put_line('VAR l_task_name VARCHAR2(30);');
        put_line('BEGIN');
        put_line('  :l_task_name := ''ADDM_''||TO_CHAR(SYSDATE, ''YYYYMMDD_HH24MISS'');');
        put_line('  DBMS_ADVISOR.CREATE_TASK(advisor_name => ''ADDM'', task_name =>  :l_task_name);');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''START_SNAPSHOT'', value => '||j.bid||');');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''END_SNAPSHOT'', value => '||j.eid||');');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''DB_ID'', value => '||j.dbid||');');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''INSTANCE'', value => '||i.instance_number||');');
        put_line('  '||CHR(38)||CHR(38)||'edb360_bypass.DBMS_ADVISOR.EXECUTE_TASK(task_name => :l_task_name);');
        put_line('END;');
        put_line('/');
        put_line('PRINT l_task_name;');
        l_standard_filename := 'addmrpt_'||i.instance_number||'_'||j.bid||'_'||j.eid||'_'||j.rep;
        l_spool_filename := '&&common_edb360_prefix._'||l_standard_filename;
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
        put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
        put_line('-- update log');
        put_line('SPO &&edb360_log..txt APP;');
        put_line('PRO');
        put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
        put_line('PRO');
        put_line('PRO '||CHR(38)||CHR(38)||'hh_mm_ss. '||l_spool_filename);
        put_line('SPO OFF;');
        put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt >> &&edb360_log3..txt');
        put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_log3..txt');
        --IF '&&edb360_skip_text.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.txt');
          put_line('SPO '||l_one_spool_filename||'.txt;');
          put_line('SELECT DBMS_ADVISOR.get_task_report(:l_task_name) FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.txt">addm text</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.txt >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        --END IF;
        put_line('EXEC DBMS_ADVISOR.DELETE_TASK(task_name => :l_task_name);');
      END IF;
  
      -- ash one node
      IF '&&edb360_conf_incl_ash_rpt.' = 'Y' THEN 
        put_line('COL edb360_bypass NEW_V edb360_bypass;');
        put_line('SELECT ''--bypass--'' edb360_bypass FROM DUAL WHERE (DBMS_UTILITY.GET_TIME - :edb360_time0) / 100  >  :edb360_max_seconds;');
        l_standard_filename := 'ashrpt_'||i.instance_number||'_'||j.bid||'_'||j.eid||'_'||j.rep;
        l_spool_filename := '&&common_edb360_prefix._'||l_standard_filename;
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
        put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
        put_line('-- update log');
        put_line('SPO &&edb360_log..txt APP;');
        put_line('PRO');
        put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
        put_line('PRO');
        put_line('PRO '||CHR(38)||CHR(38)||'hh_mm_ss. '||l_spool_filename);
        put_line('SPO OFF;');
        IF '&&edb360_skip_html.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.html');
          put_line('SPO '||l_one_spool_filename||'.html;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.ash_report_html('||j.dbid||','||i.instance_number||',TO_DATE('''||l_begin_date||''',''YYYYMMDDHH24MISS''),TO_DATE('''||l_end_date||''',''YYYYMMDDHH24MISS''))) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.html">ash html</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.html >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
        IF '&&edb360_skip_text.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 5, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.txt');
          put_line('SPO '||l_one_spool_filename||'.txt;');
          put_line('SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.ash_report_text('||j.dbid||','||i.instance_number||',TO_DATE('''||l_begin_date||''',''YYYYMMDDHH24MISS''),TO_DATE('''||l_end_date||''',''YYYYMMDDHH24MISS''))) WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NULL;');
          put_line('SELECT ''*** time limit exceeded ***'' FROM DUAL WHERE '''||CHR(38)||CHR(38)||'edb360_bypass.'' IS NOT NULL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&edb360_main_report..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.txt">ash text</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -m &&edb360_main_filename._&&edb360_file_time. '||l_one_spool_filename||'.txt >> &&edb360_log3..txt');
          put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
        END IF;
      END IF;

      -- main report
      put_line('-- update main report');
      put_line('SPO &&edb360_main_report..html APP;');
      put_line('PRO </li>');
      put_line('SPO OFF;');
      put_line('HOS zip &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt');
    END LOOP;
  END LOOP;
END;
/
SPO OFF;
SET TERM ON;
PRO Please wait ...
SET TERM OFF; 
@99910_&&common_edb360_prefix._rpt_driver.sql;
SET SERVEROUT OFF HEAD ON PAGES &&def_max_rows.;
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 99910_&&common_edb360_prefix._rpt_driver.sql >> &&edb360_log3..txt