/*[[
   Sample V$SESSION_WAIT at high frequency and show resulting session wait event and parameter profile by session.  Usage: @@NAME {<sid> [<seconds>] [<inst_id>]} [-p|-sql|-block|-obj]
   Refer to Tanel Poder's same script
    --[[
        &V1    : default={1}
        &v2    : default={10}
        &v3    : default={&instance}
        &fields: p={event,sw_p1,sw_p2,sw_p3,sq_id_or_hash,wait_obj#}, sql={event,sw_p1,sw_p2,sw_p3,sq_id_or_hash}, block={sq_id_or_hash,wait_obj#,block#}, obj={sq_id_or_hash,wait_obj#}
        @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
    --]]
]]*/

col all_samples noprint
col "% Total|Time" for pct3
PRO Sampling, it could take around &V2 seconds ...
WITH
   t1 AS (SELECT hsecs FROM v$timer),
   samples AS(
       SELECT * FROM &GV
            SELECT /*+ordered use_nl(w) NO_TRANSFORM_DISTINCT_AGG no_merge(w)*/
                   sid||',@'||USERENV('instance') sess#,&fields,
                   COUNT(*) samples,
                   COUNT(DISTINCT seq#) waits,
                   TRUNC(COUNT(*) / COUNT(DISTINCT seq#)) "Average|Samples",
                   MAX(max(r)) over() all_samples
            FROM   (SELECT  hsecs,ROWNUM r 
                    FROM    v$timer 
                    WHERE   USERENV('instance') = coalesce(:V3,:instance, ''||USERENV('instance')) 
                    CONNECT BY sys.standard.current_timestamp - current_timestamp <= numtodsinterval(&v2,'second')) s,
                   (SELECT  /*+opt_param('_optimizer_generate_transitive_pred' 'false')*/ sw.*,
                           case when p1text='idn' and (p1>131072 or event not like '%bucket%') then ''||p1 else sql_id end sq_id_or_hash,
                           nvl2(nullif(ROW_WAIT_FILE#,0),ROW_WAIT_FILE#||','||ROW_WAIT_BLOCK#,'') block#,
                           ROW_WAIT_OBJ# wait_obj#,
                           nvl2(sw.p1text,sw.p1text || '= ' || CASE WHEN (LOWER(sw.p1text) LIKE '%addr%' OR sw.p1 >= 536870912) THEN RAWTOHEX(sw.p1raw) ELSE TO_CHAR(sw.p1) END,'') sw_p1,
                           nvl2(sw.p2text,sw.p2text || '= ' || CASE WHEN (LOWER(sw.p2text) LIKE '%addr%' OR sw.p2 >= 536870912) THEN RAWTOHEX(sw.p2raw) ELSE TO_CHAR(sw.p2) END,'') sw_p2,
                           nvl2(sw.p3text,sw.p3text || '= ' || CASE WHEN (LOWER(sw.p3text) LIKE '%addr%' OR sw.p3 >= 536870912) THEN RAWTOHEX(sw.p3raw) ELSE TO_CHAR(sw.p3) END,'') sw_p3 
                    FROM   v$session sw WHERE SID = :V1) w
            WHERE USERENV('instance')=nvl(:V3,USERENV('instance'))
            GROUP  BY sid,&fields
            ORDER  BY samples desc)))),
   t2 AS (SELECT hsecs FROM v$timer)
SELECT /*+ordered monitor*/ 
       s.*,
       round(s.samples /all_samples,5)  "% Total|Time",
       round((t2.hsecs - t1.hsecs) * 10 * s.samples /all_samples,4) "Total Event|Time (ms)",
       round((t2.hsecs - t1.hsecs) * 10 * s.samples / waits / all_samples,4) "Avg time|ms/Event"
FROM   t1,samples s,t2
WHERE  ROWNUM<=100;