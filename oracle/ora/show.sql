/*[[Usage: show <SGA|SGASTAT|PGASTAT|ME|TRANS>
--[[
&V9:{
   SGA={INST_ID,NAME,ROUND(VALUE/1024/1024,2) MB FROM GV$SGA ORDER BY 1,2},
   SGASTAT={INST_ID,POOL,NVL2(POOL,decode(NAME,'free memory','free memory','used memory'),NAME) typ,Round(SUM(bytes)/1024/1024,2) MB FROM GV$SGASTAT GROUP BY INST_ID,POOL,NVL2(POOL,decode(NAME,'free memory','free memory','used memory'),NAME) ORDER BY 1,2},
   PGASTAT={ * from GV$PGASTAT ORDER BY 1,2},
   ME={sid,SERIAL#,audsid,logon_time,SCHEMANAME,MACHINE,SERVICE_NAME,FAILOVER_METHOD,(select value from v$diag_info where name='Default Trace File') trace_file from v$session where audsid=userenv('sessionid')},
   TRANS={ b.sid || ',' || b.serial# || ',@' || b.inst_id SID,
               regexp_substr(b.program, '\(.*\)') program,
               b.sql_id,
               b.event,
               XID,
               start_time,
               decode(ubablk,0,0,ubablk-START_UBABLK+1) unablocks,
               a.phy_io,
               a.log_io
        FROM   gv$transaction a, gv$session b
        WHERE  a.inst_id = b.inst_id
        AND    a.SES_ADDR = b.SADDR
        ORDER  BY ubablk, phy_io, start_time DESC
        },
   DB={}
}]]--

]]*/

SELECT &V9
