/*[[
Show all database instances
--[[
    @blocked: 11.2={blocked,},10.2={SHUTDOWN_PENDING,}
--]]
]]*/

--Show node-level sysdate by querying the logon time of px sessions from px queries
WITH SS AS (SELECT /*+materialize*/ inst_id,sid,logon_time,qcsid,qcinst_id 
            from   gv$session join gv$px_session using(sid,inst_id)
            WHERE  logon_time>=sysdate and username=user),
     tim AS(SELECT /*+no_merge*/ inst_id,max(logon_time) tim
            FROM   ss
            WHERE  qcsid = userenv('sid')
            AND    qcinst_id = userenv('instance')
            GROUP BY inst_id)
SELECT decode(userenv('instance')+0,a.inst_id,'*',' ')||a.inst_id inst_id, instance_name,version,
       host_name,user,
       status,archiver,&blocked
       to_char(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
       nvl(to_char(b.tim,'YYYY-MM-DD HH24:MI:SS'),'UNKOWN') inst_current_time
from gv$instance a,tim b
WHERE a.inst_id=b.inst_id(+)
order by a.inst_id