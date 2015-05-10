----------------------------------------------------------------------------------------
--
-- File name:   esp_collect_requirements_awr.sql
--
-- Purpose:     Collect Database Requirements (CPU, Memory, Disk and IO Perf)
--
-- Author:      Carlos Sierra, Rodrigo Righetti
--
-- Version:     v1504 (2015/04/02)
--
-- Usage:       Collects Requirements from AWR and ASH views on databases with the 
--				Oracle Diagnostics Pack license, it also collect from Statspack starting
--				9i databases up to 12c. 				 
--				 
--              The output of this script can be used to feed a Sizing and Provisioning
--              application.
--
-- Example:     # cd esp_collect
--              # sqlplus / as sysdba
--              SQL> START sql/esp_master.sql
--
--  Notes:      Developed and tested on 12.1.0.2, 11.2.0.3, 10.2.0.4, 9.2.0.1
--             
---------------------------------------------------------------------------------------
--
SET TERM OFF ECHO OFF FEED OFF VER OFF HEA OFF PAGES 0 COLSEP ', ' LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100 NUM 20 SQLBL ON BLO . RECSEP OFF;
-- get host name (up to 30, stop before first '.', no special characters)
COL esp_host_name_short NEW_V esp_host_name_short FOR A30;
SELECT LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST'), 1, 30)) esp_host_name_short FROM DUAL;
SELECT SUBSTR('&&esp_host_name_short.', 1, INSTR('&&esp_host_name_short..', '.') - 1) esp_host_name_short FROM DUAL;
SELECT TRANSLATE('&&esp_host_name_short.',
'abcdefghijklmnopqrstuvwxyz0123456789-_ ''`~!@#$%&*()=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyz0123456789-_') esp_host_name_short FROM DUAL;

DEF skip_on_10g = '';
COL skip_on_10g NEW_V skip_on_10g;
SELECT '--' skip_on_10g FROM v$instance WHERE version LIKE '10%';

--SPO  esp_requirements_&&esp_host_name_short..log APP;

ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ".,";
ALTER SESSION SET NLS_SORT = 'BINARY';
ALTER SESSION SET NLS_COMP = 'BINARY';

DEF ecr_sq_fact_hints = 'MATERIALIZE NO_MERGE';
DEF ecr_date_format = 'YYYY-MM-DD/HH24:MI:SS';

CL COL;
COL ecr_collection_key NEW_V ecr_collection_key;
SELECT 'get_collection_key', SUBSTR(name||ora_hash(dbid||name||instance_name||host_name||systimestamp), 1, 13) ecr_collection_key FROM v$instance, v$database;
COL ecr_dbid NEW_V ecr_dbid;
SELECT 'get_dbid', TO_CHAR(dbid) ecr_dbid FROM v$database;
COL ecr_instance_number NEW_V ecr_instance_number;
SELECT 'get_instance_number', TO_CHAR(instance_number) ecr_instance_number FROM v$instance;
COL ecr_min_snap_id NEW_V ecr_min_snap_id;
SELECT 'get_min_snap_id', TO_CHAR(MIN(snap_id)) ecr_min_snap_id FROM dba_hist_snapshot WHERE dbid = &&ecr_dbid.;
COL ecr_collection_host NEW_V ecr_collection_host;
SELECT 'get_collection_host', LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST')||'.', 1, INSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST')||'.', '.') - 1)) ecr_collection_host FROM DUAL;

DEF;
SELECT 'get_current_time', TO_CHAR(SYSDATE, '&&ecr_date_format.') current_time FROM DUAL
/
--SPO OFF;
SPO esp_requirements_&&esp_host_name_short..csv APP;

-- header
SELECT 'collection_host,collection_key,category,data_element,source,instance_number,inst_id,value' FROM DUAL
/

-- id
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'collector_version', 'v1419', 0, 0, '2014-11-28' FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'collection_date', 'sysdate', 0, 0, TO_CHAR(SYSDATE, '&&ecr_date_format.') FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'awr_retention_days', 'dba_hist_snapshot', 0, 0,  ROUND(CAST(MAX(end_interval_time) AS DATE) - CAST(MIN(begin_interval_time) AS DATE), 1) FROM dba_hist_snapshot WHERE dbid = &&ecr_dbid.
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'awr_retention_days', 'dba_hist_snapshot', instance_number, 0, ROUND(CAST(MAX(end_interval_time) AS DATE) - CAST(MIN(begin_interval_time) AS DATE), 1) FROM dba_hist_snapshot WHERE dbid = &&ecr_dbid. GROUP BY instance_number ORDER BY instance_number
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'user', 'user', 0, 0, USER FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'host', 'sys_context', 0, 0, LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'HOST')||'.', 1, INSTR(SYS_CONTEXT('USERENV', 'HOST')||'.', '.') - 1)) FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'server_host', 'sys_context', 0, 0, LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST')||'.', 1, INSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST')||'.', '.') - 1)) FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'dbid', 'v$database', 0, 0, '&&ecr_dbid.' FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'db_name', 'sys_context', 0, 0, SYS_CONTEXT('USERENV', 'DB_NAME') FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'db_unique_name', 'sys_context', 0, 0, SYS_CONTEXT('USERENV', 'DB_UNIQUE_NAME') FROM DUAL
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'platform_name', 'v$database', 0, 0, platform_name FROM v$database
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'host_name', 'gv$instance', instance_number, inst_id, LOWER(SUBSTR(host_name||'.', 1, INSTR(host_name||'.', '.') - 1)) FROM gv$instance ORDER BY inst_id
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'version', 'gv$instance', instance_number, inst_id, version FROM gv$instance ORDER BY inst_id
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'instance_name', 'gv$instance', instance_number, inst_id, instance_name FROM gv$instance ORDER BY inst_id
/
SELECT DISTINCT '&&ecr_collection_host.', '&&ecr_collection_key', 'id', 'instance_name', 'dba_hist_database_instance', instance_number, 0, instance_name FROM dba_hist_database_instance WHERE dbid = &&ecr_dbid. ORDER BY instance_number
/

-- cpu 
WITH 
cpu_per_inst_and_sample AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       snap_id,
       sample_id,
       COUNT(*) aas_on_cpu_and_resmgr,
       SUM(CASE session_state WHEN 'ON CPU' THEN 1 ELSE 0 END) aas_on_cpu,
       SUM(CASE event WHEN 'resmgr:cpu quantum' THEN 1 ELSE 0 END) aas_resmgr_cpu_quantum       
  FROM dba_hist_active_sess_history
 WHERE snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
   AND (session_state = 'ON CPU' OR event = 'resmgr:cpu quantum')
 GROUP BY
       instance_number,
       snap_id,
       sample_id
),
cpu_per_inst AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       MAX(aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_peak,
       MAX(aas_on_cpu) aas_on_cpu_peak,
       MAX(aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_peak,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_9999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_999,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_99,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_97,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_95,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_90,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_75,
       MEDIAN(aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_median,
       MEDIAN(aas_on_cpu) aas_on_cpu_median,
       MEDIAN(aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_median,
       ROUND(AVG(aas_on_cpu_and_resmgr), 1) aas_on_cpu_and_resmgr_avg,
       ROUND(AVG(aas_on_cpu), 1) aas_on_cpu_avg,
       ROUND(AVG(aas_resmgr_cpu_quantum), 1) aas_resmgr_cpu_quantum_avg
  FROM cpu_per_inst_and_sample
 GROUP BY
       instance_number
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_peak', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_peak FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_peak', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_peak FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_peak', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_peak FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_peak', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_peak) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_peak', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_peak) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_peak', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_peak) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_9999', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_9999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_9999', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_9999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_9999', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_9999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_9999', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_9999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_9999', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_9999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_9999', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_9999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_999', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_999', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_999', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_999', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_999', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_999', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_99', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_99 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_99', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_99 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_99', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_99 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_99', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_99) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_99', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_99) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_99', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_99) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_97', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_97 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_97', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_97 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_97', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_97 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_97', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_97) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_97', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_97) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_97', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_97) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_95', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_95 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_95', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_95 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_95', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_95 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_95', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_95) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_95', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_95) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_95', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_95) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_90', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_90 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_90', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_90 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_90', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_90 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_90', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_90) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_90', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_90) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_90', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_90) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_75', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_75 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_75', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_75 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_75', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_75 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_75', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_75) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_75', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_75) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_75', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_75) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_median', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_median FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_median', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_median FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_median', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_median FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_median', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_median) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_median', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_median) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_median', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_median) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_avg', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_and_resmgr_avg FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_avg', 'dba_hist_active_sess_history', instance_number, 0, aas_on_cpu_avg FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_avg', 'dba_hist_active_sess_history', instance_number, 0, aas_resmgr_cpu_quantum_avg FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_avg', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_and_resmgr_avg) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_avg', 'dba_hist_active_sess_history', -1, -1, SUM(aas_on_cpu_avg) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_avg', 'dba_hist_active_sess_history', -1, -1, SUM(aas_resmgr_cpu_quantum_avg) FROM cpu_per_inst
/
WITH 
cpu_per_inst_and_sample AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       inst_id,
       sample_id,
       COUNT(*) aas_on_cpu_and_resmgr,
       SUM(CASE session_state WHEN 'ON CPU' THEN 1 ELSE 0 END) aas_on_cpu,
       SUM(CASE event WHEN 'resmgr:cpu quantum' THEN 1 ELSE 0 END) aas_resmgr_cpu_quantum       
  FROM gv$active_session_history
 WHERE (session_state = 'ON CPU' OR event = 'resmgr:cpu quantum')
 GROUP BY
       inst_id,
       sample_id
),
cpu_per_inst AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       inst_id,
       MAX(aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_peak,
       MAX(aas_on_cpu) aas_on_cpu_peak,
       MAX(aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_peak,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_9999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_999,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_99,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_97,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_95,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_90,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_on_cpu) aas_on_cpu_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_75,
       MEDIAN(aas_on_cpu_and_resmgr) aas_on_cpu_and_resmgr_median,
       MEDIAN(aas_on_cpu) aas_on_cpu_median,
       MEDIAN(aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_median,
       ROUND(AVG(aas_on_cpu_and_resmgr), 1) aas_on_cpu_and_resmgr_avg,
       ROUND(AVG(aas_on_cpu), 1) aas_on_cpu_avg,
       ROUND(AVG(aas_resmgr_cpu_quantum), 1) aas_resmgr_cpu_quantum_avg
  FROM cpu_per_inst_and_sample
 GROUP BY
       inst_id
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_peak', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_peak FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_peak', 'gv$active_session_history', 0, inst_id, aas_on_cpu_peak FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_peak', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_peak FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_peak', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_peak) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_peak', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_peak) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_peak', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_peak) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_9999', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_9999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_9999', 'gv$active_session_history', 0, inst_id, aas_on_cpu_9999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_9999', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_9999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_9999', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_9999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_9999', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_9999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_9999', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_9999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_999', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_999', 'gv$active_session_history', 0, inst_id, aas_on_cpu_999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_999', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_999 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_999', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_999', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_999', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_999) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_99', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_99 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_99', 'gv$active_session_history', 0, inst_id, aas_on_cpu_99 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_99', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_99 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_99', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_99) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_99', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_99) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_99', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_99) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_97', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_97 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_97', 'gv$active_session_history', 0, inst_id, aas_on_cpu_97 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_97', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_97 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_97', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_97) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_97', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_97) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_97', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_97) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_95', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_95 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_95', 'gv$active_session_history', 0, inst_id, aas_on_cpu_95 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_95', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_95 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_95', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_95) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_95', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_95) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_95', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_95) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_90', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_90 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_90', 'gv$active_session_history', 0, inst_id, aas_on_cpu_90 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_90', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_90 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_90', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_90) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_90', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_90) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_90', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_90) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_75', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_75 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_75', 'gv$active_session_history', 0, inst_id, aas_on_cpu_75 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_75', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_75 FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_75', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_75) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_75', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_75) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_75', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_75) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_median', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_median FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_median', 'gv$active_session_history', 0, inst_id, aas_on_cpu_median FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_median', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_median FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_median', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_median) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_median', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_median) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_median', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_median) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_avg', 'gv$active_session_history', 0, inst_id, aas_on_cpu_and_resmgr_avg FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_avg', 'gv$active_session_history', 0, inst_id, aas_on_cpu_avg FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_avg', 'gv$active_session_history', 0, inst_id, aas_resmgr_cpu_quantum_avg FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_and_resmgr_avg', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_and_resmgr_avg) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_on_cpu_avg', 'gv$active_session_history', -1, -1, SUM(aas_on_cpu_avg) FROM cpu_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu', 'aas_resmgr_cpu_quantum_avg', 'gv$active_session_history', -1, -1, SUM(aas_resmgr_cpu_quantum_avg) FROM cpu_per_inst
/

-- mem
WITH
sga_per_inst_and_snap AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       snap_id,
       SUM(value) sga_alloc
  FROM dba_hist_sga
 WHERE snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
 GROUP BY
       instance_number,
       snap_id
),
sga_per_inst AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       MAX(sga_alloc) sga_alloc
  FROM sga_per_inst_and_snap
 GROUP BY
       instance_number
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'sga_alloc', 'dba_hist_sga', instance_number, 0, sga_alloc FROM sga_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'sga_alloc', 'dba_hist_sga', -1, -1, SUM(sga_alloc) FROM sga_per_inst
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'sga_alloc', 'gv$sgainfo', 0, inst_id, bytes FROM gv$sgainfo WHERE name = 'Maximum SGA Size' ORDER BY inst_id
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'sga_alloc', 'gv$sgainfo', -1, -1, SUM(bytes) FROM gv$sgainfo WHERE name = 'Maximum SGA Size'
/
WITH 
pga_per_inst AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       MAX(value) pga_alloc
  FROM dba_hist_pgastat
 WHERE snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
   AND name = 'maximum PGA allocated'
 GROUP BY
       instance_number
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'pga_alloc', 'dba_hist_pgastat', instance_number, 0, pga_alloc FROM pga_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'pga_alloc', 'dba_hist_pgastat', -1, -1, SUM(pga_alloc) FROM pga_per_inst
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'pga_alloc', 'gv$pgastat', 0, inst_id, value FROM gv$pgastat WHERE name = 'maximum PGA allocated' ORDER BY inst_id
/
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', 'pga_alloc', 'gv$pgastat', -1, -1, SUM(value) FROM gv$pgastat WHERE name = 'maximum PGA allocated'
/
WITH
par_per_inst AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       parameter_name,
       MAX(TO_NUMBER(value)) value
  FROM dba_hist_parameter
 WHERE snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
   AND parameter_name IN ('memory_target', 'memory_max_target', 'sga_target', 'sga_max_size', 'pga_aggregate_target', 'cpu_count')
 GROUP BY
       instance_number,
       parameter_name
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', parameter_name, 'dba_hist_parameter', instance_number, 0, value FROM par_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', parameter_name, 'dba_hist_parameter', -1, -1, SUM(value) FROM par_per_inst GROUP BY parameter_name 
 ORDER BY 3, 6 NULLS FIRST, 5
/
WITH
par_per_inst AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       inst_id,
       name parameter_name,
       MAX(TO_NUMBER(value)) value
  FROM gv$system_parameter
 WHERE name IN ('memory_target', 'memory_max_target', 'sga_target', 'sga_max_size', 'pga_aggregate_target', 'cpu_count')
 GROUP BY
       inst_id,
       name
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', parameter_name, 'gv$system_parameter', 0, inst_id, value FROM par_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem', parameter_name, 'gv$system_parameter', -1, -1, SUM(value) FROM par_per_inst GROUP BY parameter_name 
 ORDER BY 3, 5 NULLS FIRST, 6
/

-- db_size
WITH 
sizes AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       'datafile' file_type,
       'v$datafile' source,
       SUM(bytes) bytes
  FROM v$datafile
 UNION ALL
SELECT 'tempfile' file_type,
       'v$tempfile' source,
       SUM(bytes) bytes
  FROM v$tempfile
 UNION ALL
SELECT 'redo_log' file_type,
       'v$log' source,
       SUM(bytes) * MAX(members) bytes
  FROM v$log
 UNION ALL
SELECT 'controlfile' file_type,
       'v$controlfile' source,
       SUM(block_size * file_size_blks) bytes
  FROM v$controlfile
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'db_size', file_type, source, -1, -1, bytes FROM sizes
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'db_size', 'total', 'v$', -1, -1, SUM(bytes) FROM sizes
/

-- disk_perf
WITH
sysstat_io AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       snap_id,
       SUM(CASE WHEN stat_name = 'physical read total IO requests' THEN value ELSE 0 END) r_reqs,
       SUM(CASE WHEN stat_name IN ('physical write total IO requests', 'redo writes') THEN value ELSE 0 END) w_reqs,
       SUM(CASE WHEN stat_name = 'physical read total bytes' THEN value ELSE 0 END) r_bytes,
       SUM(CASE WHEN stat_name IN ('physical write total bytes', 'redo size') THEN value ELSE 0 END) w_bytes
  FROM dba_hist_sysstat
 WHERE snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
   AND stat_name IN ('physical read total IO requests', 'physical write total IO requests', 'redo writes', 'physical read total bytes', 'physical write total bytes', 'redo size')
 GROUP BY
       instance_number,
       snap_id
),
io_per_inst_and_snap_id AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       h1.instance_number,
       h1.snap_id,
       (h1.r_reqs - h0.r_reqs) r_reqs,
       (h1.w_reqs - h0.w_reqs) w_reqs,
       (h1.r_bytes - h0.r_bytes) r_bytes,
       (h1.w_bytes - h0.w_bytes) w_bytes,
       (CAST(s1.end_interval_time AS DATE) - CAST(s1.begin_interval_time AS DATE)) * 86400 elapsed_sec
  FROM sysstat_io h0,
       dba_hist_snapshot s0,
       sysstat_io h1,
       dba_hist_snapshot s1
 WHERE s0.snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND s0.dbid = &&ecr_dbid.
   AND s0.snap_id = h0.snap_id
   AND s0.instance_number = h0.instance_number
   AND h1.instance_number = h0.instance_number
   AND h1.snap_id = h0.snap_id + 1
   AND s1.snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND s1.dbid = &&ecr_dbid.
   AND s1.snap_id = h1.snap_id
   AND s1.instance_number = h1.instance_number
   AND s1.snap_id = s0.snap_id + 1
   AND s1.startup_time = s0.startup_time
),
io_per_snap_id AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       snap_id,
       SUM(r_reqs) r_reqs,
       SUM(w_reqs) w_reqs,
       SUM(r_bytes) r_bytes,
       SUM(w_bytes) w_bytes,
       AVG(elapsed_sec) elapsed_sec
  FROM io_per_inst_and_snap_id
 GROUP BY
       snap_id
),
io_per_inst AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       ROUND(100 * SUM(r_reqs) / (SUM(r_reqs) + SUM(w_reqs)), 1) r_reqs_perc,
       ROUND(100 * SUM(w_reqs) / (SUM(r_reqs) + SUM(w_reqs)), 1) w_reqs_perc,
       ROUND(MAX((r_reqs + w_reqs) / elapsed_sec)) rw_iops_peak,
       ROUND(MAX(r_reqs / elapsed_sec)) r_iops_peak,
       ROUND(MAX(w_reqs / elapsed_sec)) w_iops_peak,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_999,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_99,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_97,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_95,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_90,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_75,
       ROUND(MEDIAN((r_reqs + w_reqs) / elapsed_sec)) rw_iops_median,
       ROUND(MEDIAN(r_reqs / elapsed_sec)) r_iops_median,
       ROUND(MEDIAN(w_reqs / elapsed_sec)) w_iops_median,
       ROUND(AVG((r_reqs + w_reqs) / elapsed_sec)) rw_iops_avg,
       ROUND(AVG(r_reqs / elapsed_sec)) r_iops_avg,
       ROUND(AVG(w_reqs / elapsed_sec)) w_iops_avg,
       ROUND(100 * SUM(r_bytes) / (SUM(r_bytes) + SUM(w_bytes)), 1) r_bytes_perc,
       ROUND(100 * SUM(w_bytes) / (SUM(r_bytes) + SUM(w_bytes)), 1) w_bytes_perc,
       ROUND(MAX((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_peak,
       ROUND(MAX(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_peak,
       ROUND(MAX(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_peak,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_999,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_99,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_97,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_95,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_90,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_75,
       ROUND(MEDIAN((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_median,
       ROUND(MEDIAN(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_median,
       ROUND(MEDIAN(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_median,
       ROUND(AVG((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_avg,
       ROUND(AVG(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_avg,
       ROUND(AVG(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_avg
  FROM io_per_inst_and_snap_id
 WHERE elapsed_sec > 60 -- ignore snaps too close
 GROUP BY
       instance_number
),
io_per_cluster AS ( -- combined
SELECT /*+ &&ecr_sq_fact_hints. */
       ROUND(100 * SUM(r_reqs) / (SUM(r_reqs) + SUM(w_reqs)), 1) r_reqs_perc,
       ROUND(100 * SUM(w_reqs) / (SUM(r_reqs) + SUM(w_reqs)), 1) w_reqs_perc,
       ROUND(MAX((r_reqs + w_reqs) / elapsed_sec)) rw_iops_peak,
       ROUND(MAX(r_reqs / elapsed_sec)) r_iops_peak,
       ROUND(MAX(w_reqs / elapsed_sec)) w_iops_peak,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_999,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_99,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_97,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_95,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_90,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY (r_reqs + w_reqs) / elapsed_sec)) rw_iops_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY r_reqs / elapsed_sec)) r_iops_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY w_reqs / elapsed_sec)) w_iops_75,
       ROUND(MEDIAN((r_reqs + w_reqs) / elapsed_sec)) rw_iops_median,
       ROUND(MEDIAN(r_reqs / elapsed_sec)) r_iops_median,
       ROUND(MEDIAN(w_reqs / elapsed_sec)) w_iops_median,
       ROUND(AVG((r_reqs + w_reqs) / elapsed_sec)) rw_iops_avg,
       ROUND(AVG(r_reqs / elapsed_sec)) r_iops_avg,
       ROUND(AVG(w_reqs / elapsed_sec)) w_iops_avg,
       ROUND(100 * SUM(r_bytes) / (SUM(r_bytes) + SUM(w_bytes)), 1) r_bytes_perc,
       ROUND(100 * SUM(w_bytes) / (SUM(r_bytes) + SUM(w_bytes)), 1) w_bytes_perc,
       ROUND(MAX((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_peak,
       ROUND(MAX(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_peak,
       ROUND(MAX(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_peak,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_999,
       ROUND(PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_999,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_99,
       ROUND(PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_99,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_97,
       ROUND(PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_97,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_95,
       ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_95,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_90,
       ROUND(PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_90,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY (r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_75,
       ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_75,
       ROUND(MEDIAN((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_median,
       ROUND(MEDIAN(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_median,
       ROUND(MEDIAN(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_median,
       ROUND(AVG((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_avg,
       ROUND(AVG(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_avg,
       ROUND(AVG(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_avg
  FROM io_per_snap_id
 WHERE elapsed_sec > 60 -- ignore snaps too close
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_reqs_perc', 'dba_hist_sysstat', instance_number, 0, r_reqs_perc FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_reqs_perc', 'dba_hist_sysstat', instance_number, 0, w_reqs_perc FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_peak', 'dba_hist_sysstat', instance_number, 0, rw_iops_peak FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_peak', 'dba_hist_sysstat', instance_number, 0, r_iops_peak FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_peak', 'dba_hist_sysstat', instance_number, 0, w_iops_peak FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_999', 'dba_hist_sysstat', instance_number, 0, rw_iops_999 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_999', 'dba_hist_sysstat', instance_number, 0, r_iops_999 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_999', 'dba_hist_sysstat', instance_number, 0, w_iops_999 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_99', 'dba_hist_sysstat', instance_number, 0, rw_iops_99 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_99', 'dba_hist_sysstat', instance_number, 0, r_iops_99 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_99', 'dba_hist_sysstat', instance_number, 0, w_iops_99 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_97', 'dba_hist_sysstat', instance_number, 0, rw_iops_97 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_97', 'dba_hist_sysstat', instance_number, 0, r_iops_97 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_97', 'dba_hist_sysstat', instance_number, 0, w_iops_97 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_95', 'dba_hist_sysstat', instance_number, 0, rw_iops_95 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_95', 'dba_hist_sysstat', instance_number, 0, r_iops_95 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_95', 'dba_hist_sysstat', instance_number, 0, w_iops_95 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_90', 'dba_hist_sysstat', instance_number, 0, rw_iops_90 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_90', 'dba_hist_sysstat', instance_number, 0, r_iops_90 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_90', 'dba_hist_sysstat', instance_number, 0, w_iops_90 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_75', 'dba_hist_sysstat', instance_number, 0, rw_iops_75 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_75', 'dba_hist_sysstat', instance_number, 0, r_iops_75 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_75', 'dba_hist_sysstat', instance_number, 0, w_iops_75 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_median', 'dba_hist_sysstat', instance_number, 0, rw_iops_median FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_median', 'dba_hist_sysstat', instance_number, 0, r_iops_median FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_median', 'dba_hist_sysstat', instance_number, 0, w_iops_median FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_avg', 'dba_hist_sysstat', instance_number, 0, rw_iops_avg FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_avg', 'dba_hist_sysstat', instance_number, 0, r_iops_avg FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_avg', 'dba_hist_sysstat', instance_number, 0, w_iops_avg FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_bytes_perc', 'dba_hist_sysstat', instance_number, 0, r_bytes_perc FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_bytes_perc', 'dba_hist_sysstat', instance_number, 0, w_bytes_perc FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_peak', 'dba_hist_sysstat', instance_number, 0, rw_mbps_peak FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_peak', 'dba_hist_sysstat', instance_number, 0, r_mbps_peak FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_peak', 'dba_hist_sysstat', instance_number, 0, w_mbps_peak FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_999', 'dba_hist_sysstat', instance_number, 0, rw_mbps_999 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_999', 'dba_hist_sysstat', instance_number, 0, r_mbps_999 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_999', 'dba_hist_sysstat', instance_number, 0, w_mbps_999 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_99', 'dba_hist_sysstat', instance_number, 0, rw_mbps_99 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_99', 'dba_hist_sysstat', instance_number, 0, r_mbps_99 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_99', 'dba_hist_sysstat', instance_number, 0, w_mbps_99 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_97', 'dba_hist_sysstat', instance_number, 0, rw_mbps_97 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_97', 'dba_hist_sysstat', instance_number, 0, r_mbps_97 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_97', 'dba_hist_sysstat', instance_number, 0, w_mbps_97 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_95', 'dba_hist_sysstat', instance_number, 0, rw_mbps_95 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_95', 'dba_hist_sysstat', instance_number, 0, r_mbps_95 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_95', 'dba_hist_sysstat', instance_number, 0, w_mbps_95 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_90', 'dba_hist_sysstat', instance_number, 0, rw_mbps_90 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_90', 'dba_hist_sysstat', instance_number, 0, r_mbps_90 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_90', 'dba_hist_sysstat', instance_number, 0, w_mbps_90 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_75', 'dba_hist_sysstat', instance_number, 0, rw_mbps_75 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_75', 'dba_hist_sysstat', instance_number, 0, r_mbps_75 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_75', 'dba_hist_sysstat', instance_number, 0, w_mbps_75 FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_median', 'dba_hist_sysstat', instance_number, 0, rw_mbps_median FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_median', 'dba_hist_sysstat', instance_number, 0, r_mbps_median FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_median', 'dba_hist_sysstat', instance_number, 0, w_mbps_median FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_avg', 'dba_hist_sysstat', instance_number, 0, rw_mbps_avg FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_avg', 'dba_hist_sysstat', instance_number, 0, r_mbps_avg FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_avg', 'dba_hist_sysstat', instance_number, 0, w_mbps_avg FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_reqs_perc', 'dba_hist_sysstat', -1, -1, SUM(r_reqs_perc) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_reqs_perc', 'dba_hist_sysstat', -1, -1, SUM(w_reqs_perc) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_peak', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_peak) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_peak', 'dba_hist_sysstat', -1, -1, SUM(r_iops_peak) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_peak', 'dba_hist_sysstat', -1, -1, SUM(w_iops_peak) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_999', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_999) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_999', 'dba_hist_sysstat', -1, -1, SUM(r_iops_999) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_999', 'dba_hist_sysstat', -1, -1, SUM(w_iops_999) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_99', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_99) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_99', 'dba_hist_sysstat', -1, -1, SUM(r_iops_99) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_99', 'dba_hist_sysstat', -1, -1, SUM(w_iops_99) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_97', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_97) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_97', 'dba_hist_sysstat', -1, -1, SUM(r_iops_97) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_97', 'dba_hist_sysstat', -1, -1, SUM(w_iops_97) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_95', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_95) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_95', 'dba_hist_sysstat', -1, -1, SUM(r_iops_95) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_95', 'dba_hist_sysstat', -1, -1, SUM(w_iops_95) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_90', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_90) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_90', 'dba_hist_sysstat', -1, -1, SUM(r_iops_90) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_90', 'dba_hist_sysstat', -1, -1, SUM(w_iops_90) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_75', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_75) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_75', 'dba_hist_sysstat', -1, -1, SUM(r_iops_75) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_75', 'dba_hist_sysstat', -1, -1, SUM(w_iops_75) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_median', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_median) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_median', 'dba_hist_sysstat', -1, -1, SUM(r_iops_median) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_median', 'dba_hist_sysstat', -1, -1, SUM(w_iops_median) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_avg', 'dba_hist_sysstat', -1, -1, SUM(rw_iops_avg) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_avg', 'dba_hist_sysstat', -1, -1, SUM(r_iops_avg) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_avg', 'dba_hist_sysstat', -1, -1, SUM(w_iops_avg) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_bytes_perc', 'dba_hist_sysstat', -1, -1, SUM(r_bytes_perc) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_bytes_perc', 'dba_hist_sysstat', -1, -1, SUM(w_bytes_perc) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_peak', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_peak) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_peak', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_peak) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_peak', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_peak) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_999', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_999) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_999', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_999) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_999', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_999) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_99', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_99) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_99', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_99) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_99', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_99) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_97', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_97) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_97', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_97) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_97', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_97) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_95', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_95) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_95', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_95) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_95', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_95) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_90', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_90) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_90', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_90) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_90', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_90) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_75', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_75) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_75', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_75) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_75', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_75) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_median', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_median) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_median', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_median) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_median', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_median) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_avg', 'dba_hist_sysstat', -1, -1, SUM(rw_mbps_avg) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_avg', 'dba_hist_sysstat', -1, -1, SUM(r_mbps_avg) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_avg', 'dba_hist_sysstat', -1, -1, SUM(w_mbps_avg) FROM io_per_inst
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_reqs_perc', 'dba_hist_sysstat', -2, -2, r_reqs_perc FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_reqs_perc', 'dba_hist_sysstat', -2, -2, w_reqs_perc FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_peak', 'dba_hist_sysstat', -2, -2, rw_iops_peak FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_peak', 'dba_hist_sysstat', -2, -2, r_iops_peak FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_peak', 'dba_hist_sysstat', -2, -2, w_iops_peak FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_999', 'dba_hist_sysstat', -2, -2, rw_iops_999 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_999', 'dba_hist_sysstat', -2, -2, r_iops_999 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_999', 'dba_hist_sysstat', -2, -2, w_iops_999 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_99', 'dba_hist_sysstat', -2, -2, rw_iops_99 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_99', 'dba_hist_sysstat', -2, -2, r_iops_99 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_99', 'dba_hist_sysstat', -2, -2, w_iops_99 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_97', 'dba_hist_sysstat', -2, -2, rw_iops_97 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_97', 'dba_hist_sysstat', -2, -2, r_iops_97 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_97', 'dba_hist_sysstat', -2, -2, w_iops_97 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_95', 'dba_hist_sysstat', -2, -2, rw_iops_95 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_95', 'dba_hist_sysstat', -2, -2, r_iops_95 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_95', 'dba_hist_sysstat', -2, -2, w_iops_95 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_90', 'dba_hist_sysstat', -2, -2, rw_iops_90 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_90', 'dba_hist_sysstat', -2, -2, r_iops_90 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_90', 'dba_hist_sysstat', -2, -2, w_iops_90 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_75', 'dba_hist_sysstat', -2, -2, rw_iops_75 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_75', 'dba_hist_sysstat', -2, -2, r_iops_75 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_75', 'dba_hist_sysstat', -2, -2, w_iops_75 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_median', 'dba_hist_sysstat', -2, -2, rw_iops_median FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_median', 'dba_hist_sysstat', -2, -2, r_iops_median FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_median', 'dba_hist_sysstat', -2, -2, w_iops_median FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_iops_avg', 'dba_hist_sysstat', -2, -2, rw_iops_avg FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_iops_avg', 'dba_hist_sysstat', -2, -2, r_iops_avg FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_iops_avg', 'dba_hist_sysstat', -2, -2, w_iops_avg FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_bytes_perc', 'dba_hist_sysstat', -2, -2, r_bytes_perc FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_bytes_perc', 'dba_hist_sysstat', -2, -2, w_bytes_perc FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_peak', 'dba_hist_sysstat', -2, -2, rw_mbps_peak FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_peak', 'dba_hist_sysstat', -2, -2, r_mbps_peak FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_peak', 'dba_hist_sysstat', -2, -2, w_mbps_peak FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_999', 'dba_hist_sysstat', -2, -2, rw_mbps_999 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_999', 'dba_hist_sysstat', -2, -2, r_mbps_999 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_999', 'dba_hist_sysstat', -2, -2, w_mbps_999 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_99', 'dba_hist_sysstat', -2, -2, rw_mbps_99 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_99', 'dba_hist_sysstat', -2, -2, r_mbps_99 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_99', 'dba_hist_sysstat', -2, -2, w_mbps_99 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_97', 'dba_hist_sysstat', -2, -2, rw_mbps_97 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_97', 'dba_hist_sysstat', -2, -2, r_mbps_97 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_97', 'dba_hist_sysstat', -2, -2, w_mbps_97 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_95', 'dba_hist_sysstat', -2, -2, rw_mbps_95 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_95', 'dba_hist_sysstat', -2, -2, r_mbps_95 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_95', 'dba_hist_sysstat', -2, -2, w_mbps_95 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_90', 'dba_hist_sysstat', -2, -2, rw_mbps_90 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_90', 'dba_hist_sysstat', -2, -2, r_mbps_90 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_90', 'dba_hist_sysstat', -2, -2, w_mbps_90 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_75', 'dba_hist_sysstat', -2, -2, rw_mbps_75 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_75', 'dba_hist_sysstat', -2, -2, r_mbps_75 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_75', 'dba_hist_sysstat', -2, -2, w_mbps_75 FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_median', 'dba_hist_sysstat', -2, -2, rw_mbps_median FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_median', 'dba_hist_sysstat', -2, -2, r_mbps_median FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_median', 'dba_hist_sysstat', -2, -2, w_mbps_median FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'rw_mbps_avg', 'dba_hist_sysstat', -2, -2, rw_mbps_avg FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'r_mbps_avg', 'dba_hist_sysstat', -2, -2, r_mbps_avg FROM io_per_cluster
UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf', 'w_mbps_avg', 'dba_hist_sysstat', -2, -2, w_mbps_avg FROM io_per_cluster
/

-- rman
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'rman', status, TO_CHAR(end_time, '&&ecr_date_format.'), 0, 0, ROUND(output_bytes / POWER(2, 30), 3) value FROM v$rman_backup_job_details WHERE '&&skip_on_10g.' IS NULL ORDER BY end_time
/

-- os stats
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'osstat', stat_name, 'gv$osstat', 0, inst_id, value FROM gv$osstat ORDER BY inst_id, stat_name
/

-- cpu time series
WITH 
cpu_per_inst_and_sample AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       snap_id,
       sample_id,
       MIN(sample_time) sample_time,
       CASE session_state WHEN 'ON CPU' THEN 'ON CPU' ELSE 'resmgr:cpu quantum' END session_state,
       COUNT(*) active_sessions
  FROM dba_hist_active_sess_history
 WHERE snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
   AND (session_state = 'ON CPU' OR event = 'resmgr:cpu quantum')
 GROUP BY
       instance_number,
       snap_id,
       sample_id,
       session_state,
       event
),
cpu_per_inst_and_hour AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       session_state,
       instance_number,
       TO_CHAR(TRUNC(CAST(sample_time AS DATE), 'HH') + (1/24), '&&ecr_date_format.') end_time,
       MAX(active_sessions) active_sessions_max, -- 100% percentile or max or peak
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY active_sessions) active_sessions_99p, -- 99% percentile
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY active_sessions) active_sessions_97p, -- 97% percentile
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY active_sessions) active_sessions_95p, -- 95% percentile
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY active_sessions) active_sessions_90p, -- 90% percentile
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY active_sessions) active_sessions_75p, -- 75% percentile
       ROUND(MEDIAN(active_sessions), 1) active_sessions_med, -- 50% percentile or median
       ROUND(AVG(active_sessions), 1) active_sessions_avg -- average
  FROM cpu_per_inst_and_sample
 GROUP BY
       session_state,
       instance_number,
       TRUNC(CAST(sample_time AS DATE), 'HH')
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts', session_state, end_time, instance_number, 0 inst_id, active_sessions_max value FROM cpu_per_inst_and_hour
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts_99p', session_state, end_time, instance_number, 0 inst_id, active_sessions_99p value FROM cpu_per_inst_and_hour
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts_97p', session_state, end_time, instance_number, 0 inst_id, active_sessions_97p value FROM cpu_per_inst_and_hour
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts_95p', session_state, end_time, instance_number, 0 inst_id, active_sessions_95p value FROM cpu_per_inst_and_hour
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts_90p', session_state, end_time, instance_number, 0 inst_id, active_sessions_90p value FROM cpu_per_inst_and_hour
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts_75p', session_state, end_time, instance_number, 0 inst_id, active_sessions_75p value FROM cpu_per_inst_and_hour
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts_med', session_state, end_time, instance_number, 0 inst_id, active_sessions_med value FROM cpu_per_inst_and_hour
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'cpu_ts_avg', session_state, end_time, instance_number, 0 inst_id, active_sessions_avg value FROM cpu_per_inst_and_hour
 ORDER BY
       3, 4, 6, 5
/

-- mem time series
WITH
sga AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       h.instance_number,
       h.snap_id,
       TO_CHAR(TRUNC(CAST(s.end_interval_time AS DATE), 'HH') + (1/24), '&&ecr_date_format.') end_time,
       SUM(h.value) bytes
  FROM dba_hist_sga h,
       dba_hist_snapshot s
 WHERE h.snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND h.dbid = &&ecr_dbid.
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
 GROUP BY
       h.instance_number,
       h.snap_id,
       s.end_interval_time
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem_ts', 'sga', end_time, instance_number, 0 inst_id, ROUND(MAX(bytes) / POWER(2, 30), 3) value
  FROM sga
 GROUP BY
       instance_number,
       end_time
 ORDER BY
       3, 4, 6, 5
/
WITH
pga AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       h.instance_number,
       h.snap_id,
       TO_CHAR(TRUNC(CAST(s.end_interval_time AS DATE), 'HH') + (1/24), '&&ecr_date_format.') end_time,
       SUM(h.value) bytes
  FROM dba_hist_pgastat h,
       dba_hist_snapshot s
 WHERE h.snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND h.dbid = &&ecr_dbid.
   --AND h.name = 'maximum PGA allocated'
   AND h.name = 'total PGA allocated'
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
 GROUP BY
       h.instance_number,
       h.snap_id,
       s.end_interval_time
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'mem_ts', 'pga', end_time, instance_number, 0 inst_id, ROUND(MAX(bytes) / POWER(2, 30), 3) value
  FROM pga
 GROUP BY
       instance_number,
       end_time
 ORDER BY
       3, 4, 6, 5
/

-- disk_perf time series
WITH
sysstat_io AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       instance_number,
       snap_id,
       SUM(CASE WHEN stat_name = 'physical read total IO requests' THEN value ELSE 0 END) r_reqs,
       SUM(CASE WHEN stat_name IN ('physical write total IO requests', 'redo writes') THEN value ELSE 0 END) w_reqs,
       SUM(CASE WHEN stat_name = 'physical read total bytes' THEN value ELSE 0 END) r_bytes,
       SUM(CASE WHEN stat_name IN ('physical write total bytes', 'redo size') THEN value ELSE 0 END) w_bytes
  FROM dba_hist_sysstat
 WHERE snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
   AND stat_name IN ('physical read total IO requests', 'physical write total IO requests', 'redo writes', 'physical read total bytes', 'physical write total bytes', 'redo size')
 GROUP BY
       instance_number,
       snap_id
),
io_per_inst_and_snap_id AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       h1.instance_number,
       TO_CHAR(TRUNC(CAST(s1.end_interval_time AS DATE), 'HH') + (1/24), '&&ecr_date_format.') end_time,
       (h1.r_reqs - h0.r_reqs) r_reqs,
       (h1.w_reqs - h0.w_reqs) w_reqs,
       (h1.r_bytes - h0.r_bytes) r_bytes,
       (h1.w_bytes - h0.w_bytes) w_bytes,
       (CAST(s1.end_interval_time AS DATE) - CAST(s1.begin_interval_time AS DATE)) * 86400 elapsed_sec
  FROM sysstat_io h0,
       dba_hist_snapshot s0,
       sysstat_io h1,
       dba_hist_snapshot s1
 WHERE s0.snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND s0.dbid = &&ecr_dbid.
   AND s0.snap_id = h0.snap_id
   AND s0.instance_number = h0.instance_number
   AND h1.instance_number = h0.instance_number
   AND h1.snap_id = h0.snap_id + 1
   AND s1.snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND s1.dbid = &&ecr_dbid.
   AND s1.snap_id = h1.snap_id
   AND s1.instance_number = h1.instance_number
   AND s1.snap_id = s0.snap_id + 1
   AND s1.startup_time = s0.startup_time
   AND (CAST(s1.end_interval_time AS DATE) - CAST(s1.begin_interval_time AS DATE)) * 86400 > 60 -- ignore snaps too close
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf_ts', 'r_iops', end_time, instance_number, 0 inst_id, ROUND(MAX(r_reqs / elapsed_sec)) value
  FROM io_per_inst_and_snap_id
 GROUP BY
       instance_number,
       end_time
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf_ts', 'w_iops', end_time, instance_number, 0 inst_id, ROUND(MAX(w_reqs / elapsed_sec)) value
  FROM io_per_inst_and_snap_id
 GROUP BY
       instance_number,
       end_time
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf_ts', 'r_mbps', end_time, instance_number, 0 inst_id, ROUND(MAX(r_bytes / POWER(2, 20) / elapsed_sec), 3) value
  FROM io_per_inst_and_snap_id
 GROUP BY
       instance_number,
       end_time
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'disk_perf_ts', 'w_mbps', end_time, instance_number, 0 inst_id, ROUND(MAX(w_bytes / POWER(2, 20) / elapsed_sec), 3) value
  FROM io_per_inst_and_snap_id
 GROUP BY
       instance_number,
       end_time
 ORDER BY
       3, 4, 6, 5
/

-- db_size time series
WITH
ts_per_snap_id AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       us.snap_id,
       TO_CHAR(TRUNC(CAST(sn.end_interval_time AS DATE), 'HH') + (1/24), '&&ecr_date_format.') end_time,
       SUM(us.tablespace_size * ts.block_size) all_tablespaces_bytes,
       SUM(CASE ts.contents WHEN 'PERMANENT' THEN us.tablespace_size * ts.block_size ELSE 0 END) perm_tablespaces_bytes,
       SUM(CASE ts.contents WHEN 'UNDO'      THEN us.tablespace_size * ts.block_size ELSE 0 END) undo_tablespaces_bytes,
       SUM(CASE ts.contents WHEN 'TEMPORARY' THEN us.tablespace_size * ts.block_size ELSE 0 END) temp_tablespaces_bytes
  FROM dba_hist_tbspc_space_usage us,
       dba_hist_snapshot sn,
       v$tablespace vt,
       dba_tablespaces ts
 WHERE us.snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND us.dbid = &&ecr_dbid.
   AND sn.snap_id = us.snap_id
   AND sn.dbid = us.dbid
   AND sn.instance_number = &&ecr_instance_number.
   AND vt.ts# = us.tablespace_id
   AND ts.tablespace_name = vt.name
 GROUP BY
       us.snap_id,
       sn.end_interval_time
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'db_size_ts', 'perm', end_time, &&ecr_instance_number., 0 inst_id, ROUND(MAX(perm_tablespaces_bytes) / POWER(2, 30), 3) value
  FROM ts_per_snap_id
 GROUP BY
       end_time
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'db_size_ts', 'undo', end_time, &&ecr_instance_number., 0 inst_id, ROUND(MAX(undo_tablespaces_bytes) / POWER(2, 30), 3) value
  FROM ts_per_snap_id
 GROUP BY
       end_time
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'db_size_ts', 'temp', end_time, &&ecr_instance_number., 0 inst_id, ROUND(MAX(temp_tablespaces_bytes) / POWER(2, 30), 3) value
  FROM ts_per_snap_id
 GROUP BY
       end_time
 ORDER BY
       3, 4, 6, 5
/

-- os time series: load, num_cpus, num_cpu_cores and physical memory
WITH 
osstat_denorm AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       snap_id,
       instance_number,
       SUM(CASE stat_name WHEN 'LOAD'                  THEN value ELSE 0 END) load,
       SUM(CASE stat_name WHEN 'NUM_CPUS'              THEN value ELSE 0 END) num_cpus,
       SUM(CASE stat_name WHEN 'NUM_CPU_CORES'         THEN value ELSE 0 END) num_cpu_cores,
       SUM(CASE stat_name WHEN 'NUM_CPU_SOCKETS'       THEN value ELSE 0 END) num_cpu_sockets,
       SUM(CASE stat_name WHEN 'PHYSICAL_MEMORY_BYTES' THEN value ELSE 0 END) physical_memory_bytes
  FROM dba_hist_osstat
 WHERE stat_name IN ('LOAD', 'NUM_CPUS', 'NUM_CPU_CORES', 'NUM_CPU_SOCKETS', 'PHYSICAL_MEMORY_BYTES')
   AND snap_id >= TO_NUMBER(NVL('&&ecr_min_snap_id.','0'))
   AND dbid = &&ecr_dbid.
 GROUP BY
       snap_id,
       instance_number
),
osstat_denorm_2 AS (
SELECT /*+ &&ecr_sq_fact_hints. */
       h.instance_number,
       TO_CHAR(TRUNC(CAST(s.end_interval_time AS DATE), 'HH') + (1/24), '&&ecr_date_format.') end_time,
       ROUND(MAX(load), 2) load,
       MAX(num_cpus) num_cpus,
       MAX(num_cpu_cores) num_cpu_cores,
       MAX(num_cpu_sockets) num_cpu_sockets,
       MAX(physical_memory_bytes) physical_memory_bytes
  FROM osstat_denorm h,
       dba_hist_snapshot s
 WHERE s.snap_id = h.snap_id
   AND s.instance_number = h.instance_number
   AND (CAST(s.end_interval_time AS DATE) - CAST(s.begin_interval_time AS DATE)) * 86400 > 60 -- ignore snaps too close
 GROUP BY
       h.instance_number,
       TRUNC(CAST(s.end_interval_time AS DATE), 'HH')
)
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'os_ts', 'load', end_time, instance_number, 0 inst_id, load value
  FROM osstat_denorm_2
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'os_ts', 'num_cpus', end_time, instance_number, 0 inst_id, num_cpus value
  FROM osstat_denorm_2
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'os_ts', 'num_cpu_cores', end_time, instance_number, 0 inst_id, num_cpu_cores value
  FROM osstat_denorm_2
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'os_ts', 'num_cpu_sockets', end_time, instance_number, 0 inst_id, num_cpu_sockets value
  FROM osstat_denorm_2
 UNION ALL
SELECT '&&ecr_collection_host.', '&&ecr_collection_key', 'os_ts', 'physical_memory_gb', end_time, instance_number, 0 inst_id, ROUND(physical_memory_bytes / POWER(2, 30), 3) value
  FROM osstat_denorm_2
 ORDER BY
       3, 4, 6, 5
/

-- footer
SELECT 'collection_host,collection_key,category,data_element,source,instance_number,inst_id,value' FROM DUAL
/

SPO OFF;
--HOS cat /proc/cpuinfo | grep -i name | sort | uniq >> cpuinfo_model_name.txt
--HOS zip -qT esp_requirements_&&esp_host_name_short..zip esp_requirements_&&esp_host_name_short..csv esp_requirements_&&esp_host_name_short..log cpuinfo_model_name.txt res_requirements_&&esp_host_name_short..txt
SET TERM ON ECHO OFF FEED ON VER ON HEA ON PAGES 14 COLSEP ' ' LIN 80 TRIMS OFF TRIM ON TI OFF TIMI OFF ARRAY 15 NUM 10 SQLBL OFF BLO ON RECSEP WR;
