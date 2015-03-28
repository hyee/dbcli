@@&&edb360_0g.tkprof.sql
DEF section_id = '4b';
DEF section_name = 'Program Global Area (PGA) Statistics History';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF main_table = 'DBA_HIST_PGASTAT';
DEF chartype = 'LineChart';
DEF stacked = '';
DEF vaxis = 'PGA Statistics in GBs';
DEF vbaseline = '';
DEF tit_01 = 'PGA memory freed back to OS';
DEF tit_02 = 'aggregate PGA auto target';
DEF tit_03 = 'aggregate PGA target parameter';
DEF tit_04 = 'bytes processed';
DEF tit_05 = 'extra bytes read/written';
DEF tit_06 = 'global memory bound';
DEF tit_07 = 'maximum PGA allocated';
DEF tit_08 = 'maximum PGA used for auto workareas';
DEF tit_09 = 'maximum PGA used for manual workareas';
DEF tit_10 = 'total PGA allocated';
DEF tit_11 = 'total PGA inuse';
DEF tit_12 = 'total PGA used for auto workareas';
DEF tit_13 = 'total PGA used for manual workareas';
DEF tit_14 = 'total freeable PGA memory';
DEF tit_15 = '';
BEGIN
  :sql_text_backup := '
WITH 
pgastat_denorm_1 AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       dbid,
       instance_number,
       SUM(CASE name WHEN ''PGA memory freed back to OS''           THEN value ELSE 0 END) pga_mem_freed_to_os,
       SUM(CASE name WHEN ''aggregate PGA auto target''             THEN value ELSE 0 END) aggr_pga_auto_target,
       SUM(CASE name WHEN ''aggregate PGA target parameter''        THEN value ELSE 0 END) aggr_pga_target_param,
       SUM(CASE name WHEN ''bytes processed''                       THEN value ELSE 0 END) bytes_processed,
       SUM(CASE name WHEN ''extra bytes read/written''              THEN value ELSE 0 END) extra_bytes_rw,
       SUM(CASE name WHEN ''global memory bound''                   THEN value ELSE 0 END) global_memory_bound,
       SUM(CASE name WHEN ''maximum PGA allocated''                 THEN value ELSE 0 END) max_pga_allocated,
       SUM(CASE name WHEN ''maximum PGA used for auto workareas''   THEN value ELSE 0 END) max_pga_used_aut_wa,
       SUM(CASE name WHEN ''maximum PGA used for manual workareas'' THEN value ELSE 0 END) max_pga_used_man_wa,
       SUM(CASE name WHEN ''total PGA allocated''                   THEN value ELSE 0 END) tot_pga_allocated,
       SUM(CASE name WHEN ''total PGA inuse''                       THEN value ELSE 0 END) tot_pga_inuse,
       SUM(CASE name WHEN ''total PGA used for auto workareas''     THEN value ELSE 0 END) tot_pga_used_aut_wa,
       SUM(CASE name WHEN ''total PGA used for manual workareas''   THEN value ELSE 0 END) tot_pga_used_man_wa,
       SUM(CASE name WHEN ''total freeable PGA memory''             THEN value ELSE 0 END) tot_freeable_pga_mem
  FROM dba_hist_pgastat
 WHERE name IN
(''PGA memory freed back to OS''
,''aggregate PGA auto target''
,''aggregate PGA target parameter''
,''bytes processed''
,''extra bytes read/written''
,''global memory bound''
,''maximum PGA allocated''
,''maximum PGA used for auto workareas''
,''maximum PGA used for manual workareas''
,''total PGA allocated''
,''total PGA inuse''
,''total PGA used for auto workareas''
,''total PGA used for manual workareas''
,''total freeable PGA memory''
)
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND instance_number = @instance_number@
 GROUP BY
       snap_id,
       dbid,
       instance_number
),
pgastat_denorm_2 AS (
SELECT /*+ &&sq_fact_hints. */
       h.dbid,
       h.instance_number,
       s.startup_time,
       MIN(h.pga_mem_freed_to_os) pga_mem_freed_to_os,
       MIN(h.bytes_processed) bytes_processed,
       MIN(h.extra_bytes_rw) extra_bytes_rw
  FROM pgastat_denorm_1 h,
       dba_hist_snapshot s
 WHERE s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND s.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s.dbid = &&edb360_dbid.
 GROUP BY
       h.dbid,
       h.instance_number,
       s.startup_time
),
pgastat_delta AS (
SELECT /*+ &&sq_fact_hints. */
       h1.snap_id,
       h1.dbid,
       h1.instance_number,
       s1.begin_interval_time,
       s1.end_interval_time,
       ROUND((CAST(s1.end_interval_time AS DATE) - CAST(s1.begin_interval_time AS DATE)) * 24 * 60 * 60) interval_secs,
       (h1.pga_mem_freed_to_os - h0.pga_mem_freed_to_os) pga_mem_freed_to_os,
       h1.aggr_pga_auto_target,
       h1.aggr_pga_target_param,
       (h1.bytes_processed - h0.bytes_processed) bytes_processed,
       (h1.extra_bytes_rw - h0.extra_bytes_rw) extra_bytes_rw,
       h1.global_memory_bound,
       h1.max_pga_allocated,
       h1.max_pga_used_aut_wa,
       h1.max_pga_used_man_wa,
       h1.tot_pga_allocated,
       h1.tot_pga_inuse,
       h1.tot_pga_used_aut_wa,
       h1.tot_pga_used_man_wa,
       h1.tot_freeable_pga_mem       
  FROM pgastat_denorm_1 h0,
       pgastat_denorm_1 h1,
       dba_hist_snapshot s0,
       dba_hist_snapshot s1,
       pgastat_denorm_2 min /* to see cumulative use (replace h0 with min on select list above) */
 WHERE h1.snap_id = h0.snap_id + 1
   AND h1.dbid = h0.dbid
   AND h1.instance_number = h0.instance_number
   AND s0.snap_id = h0.snap_id
   AND s0.dbid = h0.dbid
   AND s0.instance_number = h0.instance_number
   AND s0.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s0.dbid = &&edb360_dbid.
   AND s1.snap_id = h1.snap_id
   AND s1.dbid = h1.dbid
   AND s1.instance_number = h1.instance_number
   AND s1.snap_id = s0.snap_id + 1
   AND s1.startup_time = s0.startup_time
   AND s1.begin_interval_time > (s0.begin_interval_time + (1 / (24 * 60))) /* filter out snaps apart < 1 min */
   AND min.dbid = s1.dbid
   AND min.instance_number = s1.instance_number
   AND min.startup_time = s1.startup_time
)
SELECT snap_id,
       TO_CHAR(MIN(begin_interval_time), ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(MIN(end_interval_time), ''YYYY-MM-DD HH24:MI'') end_time,
       ROUND(SUM(pga_mem_freed_to_os) / POWER(2, 30), 3) pga_mem_freed_to_os,
       ROUND(SUM(aggr_pga_auto_target) / POWER(2, 30), 3) aggr_pga_auto_target,
       ROUND(SUM(aggr_pga_target_param) / POWER(2, 30), 3) aggr_pga_target_param,
       ROUND(SUM(bytes_processed) / POWER(2, 30), 3) bytes_processed,
       ROUND(SUM(extra_bytes_rw) / POWER(2, 30), 3) extra_bytes_rw,
       ROUND(SUM(global_memory_bound) / POWER(2, 30), 3) global_memory_bound,
       ROUND(SUM(max_pga_allocated) / POWER(2, 30), 3) max_pga_allocated,
       ROUND(SUM(max_pga_used_aut_wa) / POWER(2, 30), 3) max_pga_used_aut_wa,
       ROUND(SUM(max_pga_used_man_wa) / POWER(2, 30), 3) max_pga_used_man_wa,
       ROUND(SUM(tot_pga_allocated) / POWER(2, 30), 3) tot_pga_allocated,
       ROUND(SUM(tot_pga_inuse) / POWER(2, 30), 3) tot_pga_inuse,
       ROUND(SUM(tot_pga_used_aut_wa) / POWER(2, 30), 3) tot_pga_used_aut_wa,
       ROUND(SUM(tot_pga_used_man_wa) / POWER(2, 30), 3) tot_pga_used_man_wa,
       ROUND(SUM(tot_freeable_pga_mem) / POWER(2, 30), 3) tot_freeable_pga_mem,
       0 dummy_15
  FROM pgastat_delta
 GROUP BY
       snap_id
 ORDER BY
       snap_id
';
END;
/

DEF skip_lch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'PGA Statistics for Cluster';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 'instance_number');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'PGA Statistics for Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'PGA Statistics for Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'PGA Statistics for Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'PGA Statistics for Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'PGA Statistics for Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'PGA Statistics for Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'PGA Statistics for Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'PGA Statistics for Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

