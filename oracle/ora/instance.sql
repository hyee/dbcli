/*[[
Show all database instances
--[[
    @blocked: 11.2={blocked,},10.2={SHUTDOWN_PENDING,},  9.0={}
--]]
]]*/
SELECT decode(userenv('instance')+0,inst_id,'*',' ')||inst_id inst_id, instance_name,version,
       host_name,user,
       status,archiver,&blocked
       to_char(startup_time,'YYYY-MM-DD-HH24:MI') startup#,
       to_char(sysdate,'YYYY-MM-DD-HH24:MI:SS') current# 
from gv$instance a