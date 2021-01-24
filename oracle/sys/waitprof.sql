/*[[
   Sample V$SESSION_WAIT at high frequency and show resulting session wait event and parameter profile by session.  Usage: @@NAME {<sid> [<seconds>] [<inst_id>]} [-p|-sql|-block]
   Refer to Tanel Poder's same script
    --[[
        &V1    : default={1}
        &v2    : default={10}
        &v3    : default={&instance}
        &fields: p={sql_id,plan_hash_value,wait_obj#}, sql={sql_id}, block={sql_id,wait_obj#,block#}
        @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
    --]]
]]*/

col all_samples noprint
PRO Sampling, it could take around &V2 seconds ...
WITH
   t1 AS (SELECT hsecs FROM v$timer),
   samples AS(
       SELECT * FROM &GV
            SELECT /*+ordered use_nl(w) NO_TRANSFORM_DISTINCT_AGG no_merge(w)*/
                   sid||',@'||USERENV('instance') sess#,e.name event,c.COMMAND_NAME,&fields,
                   COUNT(*) samples,
                   COUNT(DISTINCT seq#) waits,
                   TRUNC(COUNT(*) / COUNT(DISTINCT seq#)) "Average|Samples",
                   MAX(max(r)) over() all_samples
            FROM   (SELECT  hsecs,ROWNUM r 
                    FROM    v$timer 
                    WHERE   USERENV('instance') = coalesce(:V3,:instance, ''||USERENV('instance')) 
                    CONNECT BY sys.standard.current_timestamp - current_timestamp <= numtodsinterval(&v2,'second')) s,
                   (SELECT sw.*,
                           nvl2(nullif(ROW_WAIT_FILE#,0),ROW_WAIT_FILE#||','||ROW_WAIT_BLOCK#,'') block#,
                           ROW_WAIT_OBJ# wait_obj#
                    FROM   (SELECT u.INST_ID,
                                   u.ADDR SADDR,
                                   u.INDX SID,
                                   u.KSUSESER SERIAL#,
                                   u.KSUSEQCSID  QC_SID,
                                   u.KSUUDSES AUDSID,
                                   u.KSUSEPRO PADDR,
                                   u.KSUUDLUI USER#,
                                   u.KSUUDLNA USERNAME,
                                   u.KSUUDOCT COMMAND,
                                   u.KSUSESOW OWNERID,
                                   DECODE(u.KSUSETRN, HEXTORAW('00'), NULL, u.KSUSETRN) TADDR,
                                   DECODE(u.KSQPSWAT, HEXTORAW('00'), NULL, u.KSQPSWAT) LOCKWAIT,
                                   DECODE(BITAND(u.KSUSEIDL, 9),
                                          1,'ACTIVE',
                                          0,DECODE(BITAND(u.KSUSEFLG, 4096), 0, 'INACTIVE', 'CACHED'),
                                          'KILLED') STATUS,
                                   DECODE(u.KSSPATYP, 1, 'DEDICATED', 2, 'SHARED', 3, 'PSEUDO', 4, 'POOLED', 'NONE') SERVER,
                                   u.KSUUDSID SCHEMA#,
                                   u.KSUUDSNA SCHEMANAME,
                                   u.KSUSEUNM OSUSER,
                                   u.KSUSEPID PROCESS,
                                   u.KSUSEMNM MACHINE,
                                   u.KSUSEMNP PORT,
                                   u.KSUSETID TERMINAL,
                                   u.KSUSEPNM PROGRAM,
                                   DECODE(BITAND(u.KSUSEFLG, 19), 17, 'BACKGROUND', 1, 'USER', 2, 'RECURSIVE', '?') TYPE,
                                   u.KSUSESQL SQL_ADDRESS,
                                   u.KSUSESQH SQL_HASH_VALUE,
                                   u.KSUSESQI SQL_ID,
                                   u.KSUSESPH PLAN_HASH_VALUE,
                                   --u.KSUSEFULLSPH FULL_PLAN_HASH_VALUE,
                                   DECODE(u.KSUSESCH, 65535, NULL, u.KSUSESCH) SQL_CHILD_NUMBER,
                                   u.KSUSESESTA SQL_EXEC_START,
                                   DECODE(u.KSUSESEID, 0, NULL, u.KSUSESEID) SQL_EXEC_ID,
                                   u.KSUSEPSQ PREV_SQL_ADDR,
                                   u.KSUSEPHA PREV_HASH_VALUE,
                                   u.KSUSEPSI PREV_SQL_ID,
                                   u.KSUSEPPH PREV_PLAN_HASH_VALUE,
                                   DECODE(u.KSUSEPCH, 65535, NULL, u.KSUSEPCH) PREV_CHILD_NUMBER,
                                   u.KSUSEPESTA PREV_EXEC_START,
                                   DECODE(u.KSUSEPEID, 0, NULL, u.KSUSEPEID) PREV_EXEC_ID,
                                   DECODE(u.KSUSEPEO, 0, NULL, u.KSUSEPEO) PLSQL_ENTRY_OBJECT_ID,
                                   DECODE(u.KSUSEPEO, 0, NULL, u.KSUSEPES) PLSQL_ENTRY_SUBPROGRAM_ID,
                                   DECODE(u.KSUSEPCO, 0, NULL, DECODE(BITAND(u.KSUSSTMBV, POWER(2, 11)), POWER(2, 11), u.KSUSEPCO, NULL)) PLSQL_OBJECT_ID,
                                   DECODE(u.KSUSEPCS, 0, NULL, DECODE(BITAND(u.KSUSSTMBV, POWER(2, 11)), POWER(2, 11), u.KSUSEPCS, NULL)) PLSQL_SUBPROGRAM_ID,
                                   u.KSUSEAPP MODULE,
                                   u.KSUSEAPH MODULE_HASH,
                                   u.KSUSEACT ACTION,
                                   u.KSUSEACH ACTION_HASH,
                                   u.KSUSECLI CLIENT_INFO,
                                   u.KSUSEFIX FIXED_TABLE_SEQUENCE,
                                   u.KSUSEOBJ ROW_WAIT_OBJ#,
                                   u.KSUSEFIL ROW_WAIT_FILE#,
                                   u.KSUSEBLK ROW_WAIT_BLOCK#,
                                   u.KSUSESLT ROW_WAIT_ROW#,
                                   u.KSUSEORAFN TOP_LEVEL_CALL#,
                                   u.KSUSELTM LOGON_TIME,
                                   u.KSUSECTM LAST_CALL_ET,
                                   DECODE(BITAND(u.KSUSEPXOPT, 12), 0, 'NO', 'YES') PDML_ENABLED,
                                   DECODE(u.KSUSEFT, 2, 'SESSION', 4, 'SELECT', 8, 'TRANSACTIONAL', 32, 'AUTO', 'NONE') FAILOVER_TYPE,
                                   DECODE(u.KSUSEFM, 1, 'BASIC', 2, 'PRECONNECT', 4, 'PREPARSE', 'NONE') FAILOVER_METHOD,
                                   DECODE(u.KSUSEFS, 1, 'YES', 'NO') FAILED_OVER,
                                   u.KSUSEGRP RESOURCE_CONSUMER_GROUP,
                                   DECODE(BITAND(u.KSUSEPXOPT, 4), 4, 'ENABLED', DECODE(BITAND(u.KSUSEPXOPT, 8), 8, 'FORCED', 'DISABLED')) PDML_STATUS,
                                   DECODE(BITAND(u.KSUSEPXOPT, 2), 2, 'FORCED', DECODE(BITAND(u.KSUSEPXOPT, 1), 1, 'DISABLED', 'ENABLED')) PDDL_STATUS,
                                   DECODE(BITAND(u.KSUSEPXOPT, 32), 32, 'FORCED', DECODE(BITAND(u.KSUSEPXOPT, 16), 16, 'DISABLED', 'ENABLED')) PQ_STATUS,
                                   u.KSUSECQD CURRENT_QUEUE_DURATION,
                                   u.KSUSECLID CLIENT_IDENTIFIER,
                                   DECODE(u.KSUSEBLOCKER,
                                          4294967295,'UNKNOWN',
                                          4294967294,'UNKNOWN',
                                          4294967293,'UNKNOWN',
                                          4294967292,'NO HOLDER',
                                          4294967291,'NOT IN WAIT',
                                          'VALID') BLOCKING_SESSION_STATUS,
                                   DECODE(u.KSUSEBLOCKER,
                                          4294967295,NULL,
                                          4294967294,NULL,
                                          4294967293,NULL,
                                          4294967292,NULL,
                                          4294967291,NULL,
                                          BITAND(u.KSUSEBLOCKER, 2147221504) / 262144) BLOCKING_INSTANCE,
                                   DECODE(u.KSUSEBLOCKER,
                                          4294967295,NULL,
                                          4294967294,NULL,
                                          4294967293,NULL,
                                          4294967292,NULL,
                                          4294967291,NULL,
                                          BITAND(u.KSUSEBLOCKER, 262143)) BLOCKING_SESSION,
                                   DECODE(u.KSUSEFBLOCKER,
                                          4294967295,NULL,
                                          4294967294,NULL,
                                          4294967293,NULL,
                                          4294967292,NULL,
                                          4294967291,NULL,
                                          'NOT IN WAIT',
                                          'VALID') FINAL_BLOCKING_SESSION_STATUS,
                                   DECODE(u.KSUSEFBLOCKER,
                                          4294967295,NULL,
                                          4294967294,NULL,
                                          4294967293,NULL,
                                          4294967292,NULL,
                                          4294967291,NULL,
                                          BITAND(u.KSUSEFBLOCKER, 2147221504) / 262144) FINAL_BLOCKING_INSTANCE,
                                   DECODE(u.KSUSEFBLOCKER,
                                          4294967295,NULL,
                                          4294967294,NULL,
                                          4294967293,NULL,
                                          4294967292,NULL,
                                          4294967291,NULL,
                                          BITAND(u.KSUSEFBLOCKER, 262143)) FINAL_BLOCKING_SESSION,
                                   u.KSUSESEQ SEQ#,
                                   u.KSUSEOPC EVENT#,
                                   u.KSUSEP1 P1,
                                   u.KSUSEP1R P1RAW,
                                   u.KSUSEP2 P2,
                                   u.KSUSEP2R P2RAW,
                                   u.KSUSEP3 P3,
                                   u.KSUSEP3R P3RAW,
                                   DECODE(u.ksusetim, 0, 0, -1, -1, -2, -2, decode (round (u.ksusetim/10000), 0, -1, round (u.ksusetim/10000))) WAIT_TIME
                            FROM   sys.X$KSUSE u
                            WHERE  BITAND(u.KSSPAFLG, 1) <> 0
                            AND    BITAND(u.KSUSEFLG, 1) <> 0) sw 
                    WHERE SID = &V1
                    AND   inst_id=nvl(0+:V3,inst_id)) w,
                  v$event_name e,
                  v$sqlcommand c
            WHERE w.event#=e.event#
            AND   c.command_type=w.command
            GROUP BY sid,e.name,c.COMMAND_NAME,&fields
            ORDER BY samples desc)))),
   t2 AS (SELECT hsecs FROM v$timer)
SELECT /*+ordered monitor*/ 
       s.*,
       round(s.samples /all_samples* 100,4)  "% Total|Time",
       round((t2.hsecs - t1.hsecs) * 10 * s.samples /all_samples,4) "Total Event|Time (ms)",
       round((t2.hsecs - t1.hsecs) * 10 * s.samples / waits / all_samples,4) "Avg time|ms/Event"
FROM   t1,samples s,t2;