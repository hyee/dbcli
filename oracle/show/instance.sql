/*[[
Show all database instances
--[[
    @blocked: 11.2={blocked,},10.2={SHUTDOWN_PENDING,}
--]]
]]*/

--Show node-level sysdate by querying the logon time of px sessions from px queries
WITH PX AS (SELECT /*+materialize parallel*/ * FROM gv$px_session),
tim AS(  
    SELECT /*+materialize*/ inst_id,max(logon_time) tim
    FROM   gv$session
    WHERE  (inst_id, sid) IN (SELECT /*+no_merge(a)*/ inst_id, sid
                              FROM   PX
                              WHERE  qcsid = userenv('sid')
                              AND    qcinst_id = userenv('instance'))
    GROUP BY inst_id)
SELECT decode(userenv('instance')+0,a.inst_id,'*',' ')||a.inst_id inst_id, instance_name,version,
       host_name,user,
       status,archiver,&blocked
       to_char(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
       nvl(b.tim,sysdate) inst_current_time
from gv$instance a,tim b
WHERE a.inst_id=b.inst_id(+)
order by a.inst_id