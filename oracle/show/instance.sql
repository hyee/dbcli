/*[[
Show all database instances
--[[
    @blocked: 11.2={blocked,},10.2={SHUTDOWN_PENDING,}
--]]
]]*/
SELECT decode(userenv('instance')+0,inst_id,'*',' ')||inst_id inst_id, instance_name,version,
       host_name,user,
       status,archiver,&blocked
       to_char(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
       (select to_char(max(end_time),'YYYY-MM-DD HH24:MI:SS') from gv$sessmetric b where b.inst_id=a.inst_id) current_time
from gv$instance a