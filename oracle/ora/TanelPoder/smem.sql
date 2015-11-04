/*[[Show session memory usage: smem <sid|spid>
    --[[
       Templates:
           @11g : 11.1={, pm.sql_id},10.0={}
    ]]--
]]*/

set feed off
SELECT /*+no_expand*/
    s.inst_id,s.sid,p.spid, pm.category,
    round(allocated/1024/1024,2) allocated_mb,
    round(used/1024/1024,2) used_mb,
    round(max_allocated/1024/1024,2) max_allocated_mb
FROM
    gv$session s
  , gv$process p
  , gv$process_memory pm
WHERE
    s.paddr = p.addr and s.inst_id=p.inst_id
AND p.pid = pm.pid and pm.inst_id=p.inst_id
AND (:V1 is not null and :V1 in(s.sid,p.spid) or :V1 is null and (s.sid,s.inst_id) in (select sid,inst_id from gv$sql_workarea_active))
ORDER BY
    s.inst_id,
    s.sid,
    category
/
select /*+no_expand*/ inst_id,SID,NAME,ROUND(VALUE/1024/1024,2) MB
from  gv$sesstat JOIN v$statname USING(statistic#)
WHERE (:V1 is not null and :V1 =SID or :V1 is null and (sid,inst_id) in (select sid,inst_id from gv$sql_workarea_active))
 AND NAME LIKE '%memory%'
ORDER BY inst_id,sid,NAME
/

SELECT   /*+no_expand*/
    s.inst_id
  , s.sid,p.spid
  , qcinst_id
  , qcsid
  &11g
  , pm.operation_type
  , pm.operation_id plan_line
  , pm.policy
  , ROUND(pm.active_time/1000000,1) active_sec
  , round(pm.actual_mem_used/1024/1024,2) act_mb_used
  , round(pm.max_mem_used/1024/1024,2) max_mb_used
  , round(pm.work_area_size/1024/1024,2) work_area_mb
  , pm.number_passes
  , pm.tempseg_size
  , pm.tablespace
FROM
    gv$session s
  , gv$process p
  , gv$sql_workarea_active pm
WHERE
    s.paddr = p.addr and s.inst_id=p.inst_id
AND s.sid = pm.sid and pm.inst_id=s.inst_id
AND (:V1 is null or :V1 in(s.sid,p.spid))
ORDER BY
    s.inst_id,
    s.sid;

