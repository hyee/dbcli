----------------------------------------------------------------------------------------
--
-- File name:   resources_requirements.sql
--
-- Purpose:     Collect Database Requirements (CPU, Memory, Disk and IO Perf)
--
-- Author:      Carlos Sierra
--
-- Version:     v1503 (2015/02/08)
--
-- Usage:       Collects Requirements from AWR and ASH views, thus it should only be
--              executed on systems with the Oracle Diagnostics Pack license.
--              The output of this script can be used for Sizing and Provisioning.
--
-- Example:     # sqlplus / as sysdba
--              SQL> START resources_requirements.sql
--
--  Notes:      Developed and tested on 11.2.0.3
--             
---------------------------------------------------------------------------------------
--
SET TERM OFF ECHO OFF FEED OFF VER OFF HEA ON PAGES 100 COLSEP ' ' LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100 NUM 10 SQLBL ON BLO . RECSEP OFF;

-- get host name (up to 30, stop before first '.', no special characters)
COL rr_host_name_short NEW_V rr_host_name_short FOR A30;
SELECT LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST'), 1, 30)) rr_host_name_short FROM DUAL;
SELECT SUBSTR('&&rr_host_name_short.', 1, INSTR('&&rr_host_name_short..', '.') - 1) rr_host_name_short FROM DUAL;
SELECT TRANSLATE('&&rr_host_name_short.',
'abcdefghijklmnopqrstuvwxyz0123456789-_ ''`~!@#$%&*()=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyz0123456789-_') rr_host_name_short FROM DUAL;

ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ".,";
ALTER SESSION SET NLS_SORT = 'BINARY';
ALTER SESSION SET NLS_COMP = 'BINARY';

CL COL;
SPO res_requirements_&&rr_host_name_short..txt APP;

/*****************************************************************************************/

COL startup_time FOR A26;
COL short_host_name FOR A30;

PRO Database/Instance
PRO ~~~~~~~~~~~~~~~~~
SELECT dbid,				
       instance_number,	
       startup_time,		
       version,			
       db_name,			
       instance_name,
       TRANSLATE(LOWER(SUBSTR(SUBSTR(host_name, 1, INSTR(host_name, '.') - 1), 1, 30)),
'abcdefghijklmnopqrstuvwxyz0123456789-_ ''`~!@#$%&*()=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyz0123456789-_')
       short_host_name,			
       platform_name	
  FROM dba_hist_database_instance
 ORDER BY
       dbid,				
       instance_number,	
       startup_time
/

/*****************************************************************************************/
PRO
COL order_by NOPRI;
COL metric FOR A16 HEA "Metric";
COL instance_number FOR 9999 HEA "Inst|Num";
COL on_cpu FOR 999990.0 HEA "Active|Sessions|ON CPU";
COL on_cpu_and_resmgr FOR 9999990.0 HEA "Active|Sessions|ON CPU|or RESMGR";
COL resmgr_cpu_quantum FOR 999999990.0 HEA "Active|Sessions|ON RESMGR|CPU quantum";
COL begin_interval_time FOR A18 HEA "Begin Interval";
COL end_interval_time FOR A18 HEA "End Interval";
COL snap_shots FOR 99999 HEA "Snap|Shots";
COL days FOR 990.0 HEA "Days|Hist";
COL avg_snaps_per_day FOR 990.0 HEA "Avg|Snaps|per|Day";
COL min_sample_time FOR A18 HEA "Begin Interval";
COL max_sample_time FOR A18 HEA "End Interval";
COL samples FOR 9999999 HEA "Samples";
COL hours FOR 9990.0 HEA "Hours|Hist";
PRO
PRO CPU from ASH MEM
PRO ~~~~~~~~~~~~~~~~
WITH 
cpu_per_inst_and_sample AS (
SELECT inst_id,
       sample_id,
       COUNT(*) aas_on_cpu_and_resmgr,
       SUM(CASE session_state WHEN 'ON CPU' THEN 1 ELSE 0 END) aas_on_cpu,
       SUM(CASE event WHEN 'resmgr:cpu quantum' THEN 1 ELSE 0 END) aas_resmgr_cpu_quantum,
       MIN(sample_time) min_sample_time,
       MAX(sample_time) max_sample_time           
  FROM gv$active_session_history
 WHERE (session_state = 'ON CPU' OR event = 'resmgr:cpu quantum')
 GROUP BY
       inst_id,
       sample_id
),
cpu_per_inst AS (
SELECT inst_id,
       MIN(min_sample_time)                                                   min_sample_time,
       MAX(max_sample_time)                                                   max_sample_time,
       COUNT(DISTINCT sample_id)                                              samples,        
       MAX(aas_on_cpu_and_resmgr)                                             aas_on_cpu_and_resmgr_max,
       MAX(aas_on_cpu)                                                        aas_on_cpu_max,
       MAX(aas_resmgr_cpu_quantum)                                            aas_resmgr_cpu_quantum_max,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_9999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)   aas_on_cpu_and_resmgr_999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_on_cpu)              aas_on_cpu_999,
       PERCENTILE_DISC(0.999) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum)  aas_resmgr_cpu_quantum_999,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)    aas_on_cpu_and_resmgr_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_on_cpu)               aas_on_cpu_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum)   aas_resmgr_cpu_quantum_99,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)    aas_on_cpu_and_resmgr_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_on_cpu)               aas_on_cpu_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum)   aas_resmgr_cpu_quantum_97,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)    aas_on_cpu_and_resmgr_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_on_cpu)               aas_on_cpu_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum)   aas_resmgr_cpu_quantum_95,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)    aas_on_cpu_and_resmgr_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_on_cpu)               aas_on_cpu_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum)   aas_resmgr_cpu_quantum_90,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)    aas_on_cpu_and_resmgr_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_on_cpu)               aas_on_cpu_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum)   aas_resmgr_cpu_quantum_75,
       MEDIAN(aas_on_cpu_and_resmgr)                                          aas_on_cpu_and_resmgr_med,
       MEDIAN(aas_on_cpu)                                                     aas_on_cpu_med,
       MEDIAN(aas_resmgr_cpu_quantum)                                         aas_resmgr_cpu_quantum_med,
       ROUND(AVG(aas_on_cpu_and_resmgr), 1)                                   aas_on_cpu_and_resmgr_avg,
       ROUND(AVG(aas_on_cpu), 1)                                              aas_on_cpu_avg,
       ROUND(AVG(aas_resmgr_cpu_quantum), 1)                                  aas_resmgr_cpu_quantum_avg
  FROM cpu_per_inst_and_sample
 GROUP BY
       inst_id
),
cpu_per_inst_and_perc AS (
SELECT 01 order_by, 'Maximum or peak' metric, inst_id, aas_on_cpu_max  on_cpu, aas_on_cpu_and_resmgr_max  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_max  resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 02 order_by, '99.99th percntl' metric, inst_id, aas_on_cpu_9999 on_cpu, aas_on_cpu_and_resmgr_9999 on_cpu_and_resmgr, aas_resmgr_cpu_quantum_9999 resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 03 order_by, '99.9th percentl' metric, inst_id, aas_on_cpu_999  on_cpu, aas_on_cpu_and_resmgr_999  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_999  resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 04 order_by, '99th percentile' metric, inst_id, aas_on_cpu_99   on_cpu, aas_on_cpu_and_resmgr_99   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_99   resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 05 order_by, '97th percentile' metric, inst_id, aas_on_cpu_97   on_cpu, aas_on_cpu_and_resmgr_97   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_97   resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 06 order_by, '95th percentile' metric, inst_id, aas_on_cpu_95   on_cpu, aas_on_cpu_and_resmgr_95   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_95   resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 07 order_by, '90th percentile' metric, inst_id, aas_on_cpu_90   on_cpu, aas_on_cpu_and_resmgr_90   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_90   resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 08 order_by, '75th percentile' metric, inst_id, aas_on_cpu_75   on_cpu, aas_on_cpu_and_resmgr_75   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_75   resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 09 order_by, 'Median'          metric, inst_id, aas_on_cpu_med  on_cpu, aas_on_cpu_and_resmgr_med  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_med  resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
UNION ALL
SELECT 10 order_by, 'Average'         metric, inst_id, aas_on_cpu_avg  on_cpu, aas_on_cpu_and_resmgr_avg  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_avg  resmgr_cpu_quantum, min_sample_time, max_sample_time, samples FROM cpu_per_inst
),
cpu_per_db_and_perc AS (
SELECT order_by,
       metric,
       TO_NUMBER(NULL) inst_id,
       SUM(on_cpu) on_cpu,
       SUM(on_cpu_and_resmgr) on_cpu_and_resmgr,
       SUM(resmgr_cpu_quantum) resmgr_cpu_quantum,
       MIN(min_sample_time) min_sample_time,
       MAX(max_sample_time) max_sample_time,
       SUM(samples) samples
  FROM cpu_per_inst_and_perc
 GROUP BY
       order_by,
       metric
)
SELECT order_by,
       metric,
       inst_id,
       on_cpu,
       on_cpu_and_resmgr,
       resmgr_cpu_quantum,
       TO_CHAR(CAST(min_sample_time AS DATE), 'YYYY-MM-DD HH24:MI') min_sample_time,
       TO_CHAR(CAST(max_sample_time AS DATE), 'YYYY-MM-DD HH24:MI') max_sample_time,
       samples,
       ROUND((CAST(max_sample_time AS DATE) - CAST(min_sample_time AS DATE)) * 24, 1) hours
  FROM cpu_per_inst_and_perc
 UNION ALL
SELECT order_by,
       metric,
       inst_id,
       on_cpu,
       on_cpu_and_resmgr,
       resmgr_cpu_quantum,
       TO_CHAR(CAST(min_sample_time AS DATE), 'YYYY-MM-DD HH24:MI') min_sample_time,
       TO_CHAR(CAST(max_sample_time AS DATE), 'YYYY-MM-DD HH24:MI') max_sample_time,
       samples,
       ROUND((CAST(max_sample_time AS DATE) - CAST(min_sample_time AS DATE)) * 24, 1) hours
  FROM cpu_per_db_and_perc
 ORDER BY
       order_by,
       inst_id NULLS LAST
/
PRO
PRO
PRO CPU from ASH AWR
PRO ~~~~~~~~~~~~~~~~
WITH 
cpu_per_inst_and_sample AS (
SELECT h.snap_id,
       h.dbid,
       h.instance_number,
       h.sample_id,
       COUNT(*) aas_on_cpu_and_resmgr,
       SUM(CASE h.session_state WHEN 'ON CPU' THEN 1 ELSE 0 END) aas_on_cpu,
       SUM(CASE h.event WHEN 'resmgr:cpu quantum' THEN 1 ELSE 0 END) aas_resmgr_cpu_quantum,
       MIN(s.begin_interval_time) begin_interval_time,
       MAX(s.end_interval_time) end_interval_time      
  FROM dba_hist_active_sess_history h,
       dba_hist_snapshot s
 WHERE (h.session_state = 'ON CPU' OR h.event = 'resmgr:cpu quantum')
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
 GROUP BY
       h.snap_id,
       h.dbid,
       h.instance_number,
       h.sample_id
),
cpu_per_db_and_inst AS (
SELECT dbid,
       instance_number,
       MIN(begin_interval_time)                                               begin_interval_time,
       MAX(end_interval_time)                                                 end_interval_time,
       COUNT(DISTINCT snap_id)                                                snap_shots,        
       MAX(aas_on_cpu_and_resmgr)                                             aas_on_cpu_and_resmgr_max,
       MAX(aas_on_cpu)                                                        aas_on_cpu_max,
       MAX(aas_resmgr_cpu_quantum)                                            aas_resmgr_cpu_quantum_max,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_9999,
       PERCENTILE_DISC(0.9999) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_9999,
       PERCENTILE_DISC(0.9990) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_999,
       PERCENTILE_DISC(0.9990) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_999,
       PERCENTILE_DISC(0.9990) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_999,
       PERCENTILE_DISC(0.9900) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_99,
       PERCENTILE_DISC(0.9900) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_99,
       PERCENTILE_DISC(0.9900) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_99,
       PERCENTILE_DISC(0.9700) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_97,
       PERCENTILE_DISC(0.9700) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_97,
       PERCENTILE_DISC(0.9700) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_97,
       PERCENTILE_DISC(0.9500) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_95,
       PERCENTILE_DISC(0.9500) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_95,
       PERCENTILE_DISC(0.9500) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_95,
       PERCENTILE_DISC(0.9000) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_90,
       PERCENTILE_DISC(0.9000) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_90,
       PERCENTILE_DISC(0.9000) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_90,
       PERCENTILE_DISC(0.7500) WITHIN GROUP (ORDER BY aas_on_cpu_and_resmgr)  aas_on_cpu_and_resmgr_75,
       PERCENTILE_DISC(0.7500) WITHIN GROUP (ORDER BY aas_on_cpu)             aas_on_cpu_75,
       PERCENTILE_DISC(0.7500) WITHIN GROUP (ORDER BY aas_resmgr_cpu_quantum) aas_resmgr_cpu_quantum_75,
       MEDIAN(aas_on_cpu_and_resmgr)                                          aas_on_cpu_and_resmgr_med,
       MEDIAN(aas_on_cpu)                                                     aas_on_cpu_med,
       MEDIAN(aas_resmgr_cpu_quantum)                                         aas_resmgr_cpu_quantum_med,
       ROUND(AVG(aas_on_cpu_and_resmgr), 1)                                   aas_on_cpu_and_resmgr_avg,
       ROUND(AVG(aas_on_cpu), 1)                                              aas_on_cpu_avg,
       ROUND(AVG(aas_resmgr_cpu_quantum), 1)                                  aas_resmgr_cpu_quantum_avg
  FROM cpu_per_inst_and_sample
 GROUP BY
       dbid,
       instance_number
),
cpu_per_inst_and_perc AS (
SELECT dbid, 01 order_by, 'Maximum or peak' metric, instance_number, aas_on_cpu_max  on_cpu, aas_on_cpu_and_resmgr_max  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_max  resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 02 order_by, '99.99th percntl' metric, instance_number, aas_on_cpu_9999 on_cpu, aas_on_cpu_and_resmgr_9999 on_cpu_and_resmgr, aas_resmgr_cpu_quantum_9999 resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 03 order_by, '99.9th percentl' metric, instance_number, aas_on_cpu_999  on_cpu, aas_on_cpu_and_resmgr_999  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_999  resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 04 order_by, '99th percentile' metric, instance_number, aas_on_cpu_99   on_cpu, aas_on_cpu_and_resmgr_99   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_99   resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 05 order_by, '97th percentile' metric, instance_number, aas_on_cpu_97   on_cpu, aas_on_cpu_and_resmgr_97   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_97   resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 06 order_by, '95th percentile' metric, instance_number, aas_on_cpu_95   on_cpu, aas_on_cpu_and_resmgr_95   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_95   resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 07 order_by, '90th percentile' metric, instance_number, aas_on_cpu_90   on_cpu, aas_on_cpu_and_resmgr_90   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_90   resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 08 order_by, '75th percentile' metric, instance_number, aas_on_cpu_75   on_cpu, aas_on_cpu_and_resmgr_75   on_cpu_and_resmgr, aas_resmgr_cpu_quantum_75   resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 09 order_by, 'Median'          metric, instance_number, aas_on_cpu_med  on_cpu, aas_on_cpu_and_resmgr_med  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_med  resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
UNION ALL
SELECT dbid, 10 order_by, 'Average'         metric, instance_number, aas_on_cpu_avg  on_cpu, aas_on_cpu_and_resmgr_avg  on_cpu_and_resmgr, aas_resmgr_cpu_quantum_avg  resmgr_cpu_quantum, begin_interval_time, end_interval_time, snap_shots FROM cpu_per_db_and_inst
),
cpu_per_db_and_perc AS (
SELECT dbid,
       order_by,
       metric,
       TO_NUMBER(NULL) instance_number,
       SUM(on_cpu) on_cpu,
       SUM(on_cpu_and_resmgr) on_cpu_and_resmgr,
       SUM(resmgr_cpu_quantum) resmgr_cpu_quantum,
       MIN(begin_interval_time) begin_interval_time,
       MAX(end_interval_time) end_interval_time,
       SUM(snap_shots) snap_shots
  FROM cpu_per_inst_and_perc
 GROUP BY
       dbid,
       order_by,
       metric
)
SELECT dbid,
       order_by,
       metric,
       instance_number,
       on_cpu,
       on_cpu_and_resmgr,
       resmgr_cpu_quantum,
       TO_CHAR(CAST(begin_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') begin_interval_time,
       TO_CHAR(CAST(end_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') end_interval_time,
       snap_shots,
       ROUND(CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE), 1) days,
       ROUND(snap_shots / (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)), 1) avg_snaps_per_day
  FROM cpu_per_inst_and_perc
 UNION ALL
SELECT dbid,
       order_by,
       metric,
       instance_number,
       on_cpu,
       on_cpu_and_resmgr,
       resmgr_cpu_quantum,
       TO_CHAR(CAST(begin_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') begin_interval_time,
       TO_CHAR(CAST(end_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') end_interval_time,
       snap_shots,
       ROUND(CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE), 1) days,
       ROUND(snap_shots / (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)), 1) avg_snaps_per_day
  FROM cpu_per_db_and_perc
 ORDER BY
       dbid,
       order_by,
       instance_number NULLS LAST
/

/*****************************************************************************************/
PRO
COL mem_gb FOR 99990.0 HEA "Mem GB";
COL sga_gb FOR 99990.0 HEA "SGA GB";
COL pga_gb FOR 99990.0 HEA "PGA GB";
PRO
PRO Memory from AWR
PRO ~~~~~~~~~~~~~~~
WITH mem_per_inst_and_snap AS (
SELECT s.snap_id,
       s.dbid,
       s.instance_number,
       SUM(g.value) sga_bytes,
       MAX(p.value) pga_bytes,
       SUM(g.value) + MAX(p.value) mem_bytes,
       MIN(s.begin_interval_time) begin_interval_time,
       MAX(s.end_interval_time) end_interval_time      
  FROM dba_hist_snapshot s,
       dba_hist_sga g,
       dba_hist_pgastat p
 WHERE g.snap_id = s.snap_id
   AND g.dbid = s.dbid
   AND g.instance_number = s.instance_number
   AND p.snap_id = s.snap_id
   AND p.dbid = s.dbid
   AND p.instance_number = s.instance_number
   AND p.name = 'total PGA allocated'
 GROUP BY
       s.snap_id,
       s.dbid,
       s.instance_number
),
mem_per_db_and_inst AS (
SELECT dbid,
       instance_number,
       MIN(begin_interval_time)                                begin_interval_time,
       MAX(end_interval_time)                                  end_interval_time,
       COUNT(DISTINCT snap_id)                                 snap_shots,        
       MAX(mem_bytes)                                          mem_bytes_max,
       MAX(sga_bytes)                                          sga_bytes_max,
       MAX(pga_bytes)                                          pga_bytes_max,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY mem_bytes) mem_bytes_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY sga_bytes) sga_bytes_99,
       PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY pga_bytes) pga_bytes_99,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY mem_bytes) mem_bytes_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY sga_bytes) sga_bytes_97,
       PERCENTILE_DISC(0.97) WITHIN GROUP (ORDER BY pga_bytes) pga_bytes_97,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY mem_bytes) mem_bytes_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY sga_bytes) sga_bytes_95,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY pga_bytes) pga_bytes_95,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY mem_bytes) mem_bytes_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY sga_bytes) sga_bytes_90,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY pga_bytes) pga_bytes_90,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY mem_bytes) mem_bytes_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY sga_bytes) sga_bytes_75,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY pga_bytes) pga_bytes_75,
       MEDIAN(mem_bytes)                                       mem_bytes_med,
       MEDIAN(sga_bytes)                                       sga_bytes_med,
       MEDIAN(pga_bytes)                                       pga_bytes_med,
       ROUND(AVG(mem_bytes), 1)                                mem_bytes_avg,
       ROUND(AVG(sga_bytes), 1)                                sga_bytes_avg,
       ROUND(AVG(pga_bytes), 1)                                pga_bytes_avg
  FROM mem_per_inst_and_snap
 GROUP BY
       dbid,
       instance_number
),
mem_per_inst_and_perc AS (
SELECT dbid, 01 order_by, 'Maximum or peak' metric, instance_number, mem_bytes_max mem_bytes, sga_bytes_max sga_bytes, pga_bytes_max pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
 UNION ALL
SELECT dbid, 02 order_by, '99th percentile' metric, instance_number, mem_bytes_99  mem_bytes, sga_bytes_99  sga_bytes, pga_bytes_99  pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
 UNION ALL
SELECT dbid, 03 order_by, '97th percentile' metric, instance_number, mem_bytes_97  mem_bytes, sga_bytes_97  sga_bytes, pga_bytes_97  pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
 UNION ALL
SELECT dbid, 04 order_by, '95th percentile' metric, instance_number, mem_bytes_95  mem_bytes, sga_bytes_95  sga_bytes, pga_bytes_95  pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
 UNION ALL
SELECT dbid, 05 order_by, '90th percentile' metric, instance_number, mem_bytes_90  mem_bytes, sga_bytes_90  sga_bytes, pga_bytes_90  pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
 UNION ALL
SELECT dbid, 06 order_by, '75th percentile' metric, instance_number, mem_bytes_75  mem_bytes, sga_bytes_75  sga_bytes, pga_bytes_75  pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
 UNION ALL
SELECT dbid, 07 order_by, 'Median'          metric, instance_number, mem_bytes_med mem_bytes, sga_bytes_med sga_bytes, pga_bytes_med pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
 UNION ALL
SELECT dbid, 08 order_by, 'Average'         metric, instance_number, mem_bytes_avg mem_bytes, sga_bytes_avg sga_bytes, pga_bytes_avg pga_bytes, begin_interval_time, end_interval_time, snap_shots FROM mem_per_db_and_inst
),
mem_per_db_and_perc AS (
SELECT dbid,
       order_by,
       metric,
       TO_NUMBER(NULL) instance_number,
       SUM(mem_bytes) mem_bytes,
       SUM(sga_bytes) sga_bytes,
       SUM(pga_bytes) pga_bytes,
       MIN(begin_interval_time) begin_interval_time,
       MAX(end_interval_time) end_interval_time,
       SUM(snap_shots) snap_shots
  FROM mem_per_inst_and_perc
 GROUP BY
       dbid,
       order_by,
       metric
)
SELECT dbid,
       order_by,
       metric,
       instance_number,
       ROUND(mem_bytes / POWER(2, 30), 1) mem_gb,
       ROUND(sga_bytes / POWER(2, 30), 1) sga_gb,
       ROUND(pga_bytes / POWER(2, 30), 1) pga_gb,
       TO_CHAR(CAST(begin_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') begin_interval_time,
       TO_CHAR(CAST(end_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') end_interval_time,
       snap_shots,
       ROUND(CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE), 1) days,
       ROUND(snap_shots / (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)), 1) avg_snaps_per_day
  FROM mem_per_inst_and_perc
 UNION ALL
SELECT dbid,
       order_by,
       metric,
       instance_number,
       ROUND(mem_bytes / POWER(2, 30), 1) mem_gb,
       ROUND(sga_bytes / POWER(2, 30), 1) sga_gb,
       ROUND(pga_bytes / POWER(2, 30), 1) pga_gb,
       TO_CHAR(CAST(begin_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') begin_interval_time,
       TO_CHAR(CAST(end_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') end_interval_time,
       snap_shots,
       ROUND(CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE), 1) days,
       ROUND(snap_shots / (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)), 1) avg_snaps_per_day
  FROM mem_per_db_and_perc
 ORDER BY
       dbid,
       order_by,
       instance_number NULLS LAST
/

/*****************************************************************************************/
PRO
COL file_type FOR A10 HEA "File Type";
COL disk_tb FOR 999,990.0 HEA "Disk TB";
COL display FOR A10 HEA "Disk Space";
PRO
PRO Disk Space
PRO ~~~~~~~~~~
WITH 
sizes AS (
SELECT 'Data' file_type,
       SUM(bytes) bytes
  FROM v$datafile
 UNION ALL
SELECT 'Temp' file_type,
       SUM(bytes) bytes
  FROM v$tempfile
 UNION ALL
SELECT 'Log' file_type,
       SUM(bytes) * MAX(members) bytes
  FROM v$log
 UNION ALL
SELECT 'Control' file_type,
       SUM(block_size * file_size_blks) bytes
  FROM v$controlfile
),
dbsize AS (
SELECT 'Total' file_type,
       SUM(bytes) bytes
  FROM sizes
)
SELECT s.file_type,
       ROUND(s.bytes/POWER(2,40),1) disk_tb,
       CASE 
       WHEN s.bytes > POWER(2,50) THEN ROUND(s.bytes/POWER(2,50),1)||' PB'
       WHEN s.bytes > POWER(2,40) THEN ROUND(s.bytes/POWER(2,40),1)||' TB'
       WHEN s.bytes > POWER(2,30) THEN ROUND(s.bytes/POWER(2,30),1)||' GB'
       WHEN s.bytes > POWER(2,20) THEN ROUND(s.bytes/POWER(2,20),1)||' MB'
       WHEN s.bytes > POWER(2,10) THEN ROUND(s.bytes/POWER(2,10),1)||' KB'
       WHEN s.bytes > 0 THEN s.bytes||' B' END display
  FROM sizes s
 UNION ALL
SELECT s.file_type,
       ROUND(s.bytes/POWER(2,40),1) disk_tb,
       CASE 
       WHEN s.bytes > POWER(2,50) THEN ROUND(s.bytes/POWER(2,50),1)||' PB'
       WHEN s.bytes > POWER(2,40) THEN ROUND(s.bytes/POWER(2,40),1)||' TB'
       WHEN s.bytes > POWER(2,30) THEN ROUND(s.bytes/POWER(2,30),1)||' GB'
       WHEN s.bytes > POWER(2,20) THEN ROUND(s.bytes/POWER(2,20),1)||' MB'
       WHEN s.bytes > POWER(2,10) THEN ROUND(s.bytes/POWER(2,10),1)||' KB'
       WHEN s.bytes > 0 THEN s.bytes||' B' END display
  FROM dbsize s
/

/*****************************************************************************************/
PRO
PRO
PRO IO Throughput
PRO ~~~~~~~~~~~~~
WITH
sysstat_io AS (
SELECT h.snap_id,
       h.dbid,
       h.instance_number,
       SUM(CASE WHEN h.stat_name = 'physical read total IO requests' THEN value ELSE 0 END) r_reqs,
       SUM(CASE WHEN h.stat_name IN ('physical write total IO requests', 'redo writes') THEN value ELSE 0 END) w_reqs,
       SUM(CASE WHEN h.stat_name = 'physical read total bytes' THEN value ELSE 0 END) r_bytes,
       SUM(CASE WHEN h.stat_name IN ('physical write total bytes', 'redo size') THEN value ELSE 0 END) w_bytes
  FROM dba_hist_sysstat h
 WHERE h.stat_name IN ('physical read total IO requests', 'physical write total IO requests', 'redo writes', 'physical read total bytes', 'physical write total bytes', 'redo size')
 GROUP BY
       h.snap_id,
       h.dbid,
       h.instance_number
),
io_per_inst_and_snap_id AS (
SELECT h1.dbid,
       h1.instance_number,
       h1.snap_id,
       (h1.r_reqs - h0.r_reqs) r_reqs,
       (h1.w_reqs - h0.w_reqs) w_reqs,
       (h1.r_bytes - h0.r_bytes) r_bytes,
       (h1.w_bytes - h0.w_bytes) w_bytes,
       (CAST(s1.end_interval_time AS DATE) - CAST(s1.begin_interval_time AS DATE)) * 86400 elapsed_sec,
       CAST(s1.begin_interval_time AS DATE) begin_interval_time,
       CAST(s1.end_interval_time AS DATE) end_interval_time        
  FROM sysstat_io h0,
       dba_hist_snapshot s0,
       sysstat_io h1,
       dba_hist_snapshot s1
 WHERE s0.snap_id = h0.snap_id
   AND s0.dbid = h0.dbid
   AND s0.instance_number = h0.instance_number
   AND h1.snap_id = h0.snap_id + 1
   AND h1.dbid = h0.dbid
   AND h1.instance_number = h0.instance_number
   AND s1.snap_id = h1.snap_id
   AND s1.dbid = h1.dbid
   AND s1.instance_number = h1.instance_number
   AND s1.snap_id = s0.snap_id + 1
   AND s1.dbid = s0.dbid
   AND s1.instance_number = s0.instance_number
   AND s1.startup_time = s0.startup_time
),
io_per_snap_id AS (
SELECT dbid,
       snap_id,
       SUM(r_reqs) r_reqs,
       SUM(w_reqs) w_reqs,
       SUM(r_bytes) r_bytes,
       SUM(w_bytes) w_bytes,
       AVG(elapsed_sec) elapsed_sec,
       MIN(begin_interval_time) begin_interval_time,
       MAX(end_interval_time) end_interval_time
  FROM io_per_inst_and_snap_id
 GROUP BY
       dbid,
       snap_id
),
io_per_inst AS (
SELECT dbid,
       instance_number,
       MIN(begin_interval_time) begin_interval_time,
       MAX(end_interval_time) end_interval_time,
       COUNT(DISTINCT snap_id) snap_shots,        
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
       ROUND(MEDIAN((r_reqs + w_reqs) / elapsed_sec)) rw_iops_med,
       ROUND(MEDIAN(r_reqs / elapsed_sec)) r_iops_med,
       ROUND(MEDIAN(w_reqs / elapsed_sec)) w_iops_med,
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
       ROUND(MEDIAN((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_med,
       ROUND(MEDIAN(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_med,
       ROUND(MEDIAN(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_med,
       ROUND(AVG((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_avg,
       ROUND(AVG(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_avg,
       ROUND(AVG(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_avg
  FROM io_per_inst_and_snap_id
 WHERE elapsed_sec > 60 -- ignore snaps too close
 GROUP BY
       dbid,
       instance_number
),
io_per_cluster AS ( -- combined
SELECT dbid,
       TO_NUMBER(NULL) instance_number,
       MIN(begin_interval_time) begin_interval_time,
       MAX(end_interval_time) end_interval_time,
       COUNT(DISTINCT snap_id) snap_shots,        
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
       ROUND(MEDIAN((r_reqs + w_reqs) / elapsed_sec)) rw_iops_med,
       ROUND(MEDIAN(r_reqs / elapsed_sec)) r_iops_med,
       ROUND(MEDIAN(w_reqs / elapsed_sec)) w_iops_med,
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
       ROUND(MEDIAN((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_med,
       ROUND(MEDIAN(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_med,
       ROUND(MEDIAN(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_med,
       ROUND(AVG((r_bytes + w_bytes) / POWER(2, 20) / elapsed_sec)) rw_mbps_avg,
       ROUND(AVG(r_bytes / POWER(2, 20) / elapsed_sec)) r_mbps_avg,
       ROUND(AVG(w_bytes / POWER(2, 20) / elapsed_sec)) w_mbps_avg
  FROM io_per_snap_id
 WHERE elapsed_sec > 60 -- ignore snaps too close
 GROUP BY
       dbid
),
io_per_inst_or_cluster AS (
SELECT dbid, 01 order_by, 'Maximum or peak' metric, instance_number, rw_iops_peak rw_iops, r_iops_peak r_iops, w_iops_peak w_iops, rw_mbps_peak rw_mbps, r_mbps_peak r_mbps, w_mbps_peak w_mbps, begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 02 order_by, '99.9th percentl' metric, instance_number, rw_iops_999 rw_iops,  r_iops_999 r_iops,  w_iops_999 w_iops,  rw_mbps_999 rw_mbps,  r_mbps_999 r_mbps,  w_mbps_999 w_mbps,  begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 03 order_by, '99th percentile' metric, instance_number, rw_iops_99 rw_iops,   r_iops_99 r_iops,   w_iops_99 w_iops,   rw_mbps_99 rw_mbps,   r_mbps_99 r_mbps,   w_mbps_99 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 04 order_by, '97th percentile' metric, instance_number, rw_iops_97 rw_iops,   r_iops_97 r_iops,   w_iops_97 w_iops,   rw_mbps_97 rw_mbps,   r_mbps_97 r_mbps,   w_mbps_97 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 05 order_by, '95th percentile' metric, instance_number, rw_iops_95 rw_iops,   r_iops_95 r_iops,   w_iops_95 w_iops,   rw_mbps_95 rw_mbps,   r_mbps_95 r_mbps,   w_mbps_95 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 06 order_by, '90th percentile' metric, instance_number, rw_iops_90 rw_iops,   r_iops_90 r_iops,   w_iops_90 w_iops,   rw_mbps_90 rw_mbps,   r_mbps_90 r_mbps,   w_mbps_90 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 07 order_by, '75th percentile' metric, instance_number, rw_iops_75 rw_iops,   r_iops_75 r_iops,   w_iops_75 w_iops,   rw_mbps_75 rw_mbps,   r_mbps_75 r_mbps,   w_mbps_75 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 08 order_by, 'Median'          metric, instance_number, rw_iops_med rw_iops,  r_iops_med r_iops,  w_iops_med w_iops,  rw_mbps_med rw_mbps,  r_mbps_med r_mbps,  w_mbps_med w_mbps,  begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 09 order_by, 'Average'         metric, instance_number, rw_iops_avg rw_iops,  r_iops_avg r_iops,  w_iops_avg w_iops,  rw_mbps_avg rw_mbps,  r_mbps_avg r_mbps,  w_mbps_avg w_mbps,  begin_interval_time, end_interval_time, snap_shots FROM io_per_inst
 UNION ALL
SELECT dbid, 01 order_by, 'Maximum or peak' metric, instance_number, rw_iops_peak rw_iops, r_iops_peak r_iops, w_iops_peak w_iops, rw_mbps_peak rw_mbps, r_mbps_peak r_mbps, w_mbps_peak w_mbps, begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 02 order_by, '99.9th percentl' metric, instance_number, rw_iops_999 rw_iops,  r_iops_999 r_iops,  w_iops_999 w_iops,  rw_mbps_999 rw_mbps,  r_mbps_999 r_mbps,  w_mbps_999 w_mbps,  begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 03 order_by, '99th percentile' metric, instance_number, rw_iops_99 rw_iops,   r_iops_99 r_iops,   w_iops_99 w_iops,   rw_mbps_99 rw_mbps,   r_mbps_99 r_mbps,   w_mbps_99 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 04 order_by, '97th percentile' metric, instance_number, rw_iops_97 rw_iops,   r_iops_97 r_iops,   w_iops_97 w_iops,   rw_mbps_97 rw_mbps,   r_mbps_97 r_mbps,   w_mbps_97 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 05 order_by, '95th percentile' metric, instance_number, rw_iops_95 rw_iops,   r_iops_95 r_iops,   w_iops_95 w_iops,   rw_mbps_95 rw_mbps,   r_mbps_95 r_mbps,   w_mbps_95 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 06 order_by, '90th percentile' metric, instance_number, rw_iops_90 rw_iops,   r_iops_90 r_iops,   w_iops_90 w_iops,   rw_mbps_90 rw_mbps,   r_mbps_90 r_mbps,   w_mbps_90 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 07 order_by, '75th percentile' metric, instance_number, rw_iops_75 rw_iops,   r_iops_75 r_iops,   w_iops_75 w_iops,   rw_mbps_75 rw_mbps,   r_mbps_75 r_mbps,   w_mbps_75 w_mbps,   begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 08 order_by, 'Median'          metric, instance_number, rw_iops_med rw_iops,  r_iops_med r_iops,  w_iops_med w_iops,  rw_mbps_med rw_mbps,  r_mbps_med r_mbps,  w_mbps_med w_mbps,  begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
 UNION ALL
SELECT dbid, 09 order_by, 'Average'         metric, instance_number, rw_iops_avg rw_iops,  r_iops_avg r_iops,  w_iops_avg w_iops,  rw_mbps_avg rw_mbps,  r_mbps_avg r_mbps,  w_mbps_avg w_mbps,  begin_interval_time, end_interval_time, snap_shots FROM io_per_cluster
)
SELECT dbid,
       metric,
       instance_number,
       rw_iops,
       r_iops,
       w_iops,
       rw_mbps,
       r_mbps,
       w_mbps,
       TO_CHAR(CAST(begin_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') begin_interval_time,
       TO_CHAR(CAST(end_interval_time AS DATE), 'YYYY-MM-DD HH24:MI') end_interval_time,
       snap_shots,
       ROUND(CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE), 1) days,
       ROUND(snap_shots / (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)), 1) avg_snaps_per_day
  FROM io_per_inst_or_cluster
 ORDER BY
       dbid,
       order_by,
       instance_number NULLS LAST
/

/*****************************************************************************************/

SPO OFF;
SET TERM ON ECHO OFF FEED ON VER ON HEA ON PAGES 14 COLSEP ' ' LIN 80 TRIMS OFF TRIM ON TI OFF TIMI OFF ARRAY 15 NUM 10 SQLBL OFF BLO ON RECSEP WR;










