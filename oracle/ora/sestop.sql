/*[[Show Top sessions based on session stats. Usage: @@NAME {<stat_name> [top-n]} [-a] [-u|-f"<filter>"]
    <stat_name>: Fussy search(like operator) based on the input keyword
    top-n      : Default as 1
    -u         : Only query the sessions within current schema
    -a         : Only query the active sessions
    --[[
       &FILTER1: default={1=1}, u={schemaname=nvl('&0',sys_context('userenv','current_schema'))},f={}
       &FILTER2: default={1=1}, a={status='ACTIVE'}
       &V2     : default={1}
    --]]
]]*/

WITH stat AS
 (SELECT /*+materialize*/*
  FROM   (SELECT a.*, row_number() OVER(PARTITION BY stat_name ORDER BY stat_value DESC) rnk
           FROM   (SELECT /*+no_merge no_expand*/inst_id, SID, NAME stat_name, MAX(VALUE) stat_value
                    FROM   gv$sesstat NATURAL
                    JOIN   V$STATNAME
                    WHERE  VALUE > 0
                    AND    (:V1 IS NULL OR lower(name) like lower('%&V1%'))
                    GROUP  BY inst_id, SID, NAME) a)
  WHERE  rnk <= &V2)
SELECT  /*+no_expand*/ stat_name, rnk,stat_value, status, SID || ',' || serial# || ',@' || inst_id SID,event, sql_id, schemaname, osuser,logon_time, machine, program, MODULE, action
FROM   stat NATURAL JOIN gv$session
WHERE (&FILTER1) AND (&FILTER2) 
ORDER BY stat_name,rnk;
