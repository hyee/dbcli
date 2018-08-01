/*[[
Show all database instances
--[[
    @blocked: 11.2={blocked,},10.2={SHUTDOWN_PENDING,}
--]]
]]*/

--Show node-level sysdate by querying the logon time of px sessions from px queries

SELECT decode(userenv('instance')+0,a.inst_id,'*',' ')||a.inst_id inst_id, instance_name,version,
       host_name,user,
       status,archiver,&blocked
       to_char(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
       b.current_time inst_current_time
from gv$instance a,
     TABLE(gv$(cursor(SELECT logon_time current_time,USERENV('instance') inst_id FROM v$session a JOIN v$mystat using(sid) WHERE ROWNUM<2))) b
WHERE a.inst_id=b.inst_id(+)
order by a.inst_id