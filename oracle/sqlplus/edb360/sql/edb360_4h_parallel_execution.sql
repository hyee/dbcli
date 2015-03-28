@@&&edb360_0g.tkprof.sql
DEF section_id = '4h';
DEF section_name = 'Parallel Execution';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'DOP Limit Method';
DEF main_table = 'V$PARALLEL_DEGREE_LIMIT_MTH';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
    FROM v$parallel_degree_limit_mth
';
END;				
/
@@edb360_9a_pre_one.sql

gv$px_buffer_advice

DEF title = 'PX Buffer Advice';
DEF main_table = 'GV$PX_BUFFER_ADVICE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM gv$px_buffer_advice 
 ORDER BY 1, 2
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'PQ System Stats';
DEF main_table = 'GV$PQ_SYSSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM gv$pq_sysstat 
 ORDER BY 1, 2
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'PX Process System Stats';
DEF main_table = 'GV$PX_PROCESS_SYSSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM gv$px_process_sysstat 
 ORDER BY 1, 2
';
END;				
/
@@edb360_9a_pre_one.sql

gv$sysstat

DEF title = 'System Stats';
DEF main_table = 'GV$SYSSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM gv$sysstat 
 ORDER BY 1, UPPER(name)
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'PQ Slave';
DEF main_table = 'GV$PQ_SLAVE';
BEGIN
  :sql_text := '
SELECT * FROM gv$pq_slave ORDER BY 1, 2
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'PX Sessions';
DEF main_table = 'GV$PX_SESSION';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       pxs.inst_id,
       pxs.qcsid,
       NVL(pxp.server_name, ''QC'') server_name,
       pxs.sid,
       pxs.serial#,
       NVL(pxp.pid, pro.pid) pid,
       NVL(pxp.spid, pro.spid) spid,
       pxs.server_group,
       pxs.server_set,
       pxs.server#,
       pxs.degree,
       pxs.req_degree,
       swt.event,
       ses.sql_id,
       ses.sql_child_number,
       ses.resource_consumer_group,
       ses.module,
       ses.action
  FROM gv$px_session pxs,
       gv$px_process pxp,
       gv$session ses,
       gv$process pro,
       gv$session_wait swt
 WHERE pxp.inst_id(+) = pxs.inst_id
   AND pxp.sid(+) = pxs.sid
   AND pxp.serial#(+) = pxs.serial#
   AND ses.inst_id(+) = pxs.inst_id
   AND ses.sid(+) = pxs.sid
   AND ses.serial#(+) = pxs.serial#
   AND ses.saddr(+) = pxs.saddr
   AND pro.inst_id(+) = ses.inst_id
   AND pro.addr(+) = ses.paddr
   AND swt.inst_id(+) = ses.inst_id
   AND swt.sid(+) = ses.sid
 ORDER BY
       pxs.inst_id,
       pxs.qcsid,
       pxs.qcserial# NULLS FIRST,
       pxp.server_name NULLS FIRST
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'PX Sessions Stats';
DEF main_table = 'GV$PX_SESSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       s.*,
       n.name
  FROM gv$px_sesstat s,
       gv$sysstat n
 WHERE s.value > 0
   AND n.inst_id = s.inst_id 
   AND n.statistic# = s.statistic#
 ORDER BY s.inst_id, s.qcsid NULLS FIRST, s.sid 
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'PX Processes';
DEF main_table = 'GV$PX_PROCESS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM gv$px_process 
 ORDER BY 1, 2
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'Services';
DEF main_table = 'GV$SERVICES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM gv$services 
 ORDER BY 1, 2
';
END;				
/
@@edb360_9a_pre_one.sql
DEF title = 'IO Last Calibration Results';
DEF main_table = 'DBA_RSRC_IO_CALIBRATE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_rsrc_io_calibrate
 ORDER BY
       1, 2
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'Parallel Parameters';
DEF main_table = 'GV$SYSTEM_PARAMETER2';
BEGIN
  :sql_text := '
-- inspired on parmsd.sql (Kerry Osborne)
select name, description, value, isdefault, ismodified, isset
from
(
select flag,name,value,isdefault,ismodified,
case when isdefault||ismodified = ''TRUEFALSE'' then ''FALSE'' else ''TRUE'' end isset ,
description
from
   (
       select 
            decode(substr(i.ksppinm,1,1),''_'',2,1) flag
            , i.ksppinm name
            , sv.ksppstvl value
            , sv.ksppstdf  isdefault
--            , decode(bitand(sv.ksppstvf,7),1,''MODIFIED'',4,''SYSTEM_MOD'',''FALSE'') ismodified
            , decode(bitand(sv.ksppstvf,7),1,''TRUE'',4,''TRUE'',''FALSE'') ismodified
, i.KSPPDESC description
         from sys.x$ksppi  i
            , sys.x$ksppsv sv
        where i.indx = sv.indx
   )
)
where name like nvl(''%parallel%'',name)
and flag != 3
order by flag,replace(name,''_'','''')
';
END;				
/
@@edb360_9a_pre_one.sql





