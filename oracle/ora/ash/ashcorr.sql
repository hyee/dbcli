/*[[Show the coefficient of correlation against the ASH. Usage: @@NAME "<keyword>"  [yymmddhh24mi] [yymmddhh24mi] [-dash]
    --[[
        &V2: default={&starttime}
        &V3: default={&endtime}
        &ASH: default={gv$active_Session_history} dash={dba_hist_active_sess_history}
    --]]
]]*/

WITH ash1 AS
 (SELECT /*+materialize no_merge(ash) ordered*/  *
  FROM   (SELECT rs,
                 DECODE(r, 1, 'sql_id', 2, 'event', 3, 'object_id', 4, 'program') clz,
                 trim(DECODE(r,
                        1,
                        sql_id,
                        2,
                        NVL(event, 'CPU => ' || TRIM(',' FROM p1text || ',' || p2text || ',' || p3text)),
                        3,
                        CASE WHEN current_obj# > 1 THEN to_char(current_obj#) when current_obj#!=-1 then 'UNDO' END,
                        4,
                        NVL(regexp_substr(program, '\(.*\)'), program))) NAME,
                 sample_id,
                 least(nvl(tm_delta_db_time,delta_time),delta_time) v
          FROM   (SELECT /*+no_expand*/ ROWNUM rs, a.* FROM  &ash a 
                  WHERE :V2<100000 AND sample_time+0> SYSDATE-:V2/86400 OR 
                        nvl(:V2,'100000')>=100000 AND  sample_time+0 BETWEEN nvl(to_date(:V2,'YYMMDDHH24MI'),sysdate-1) AND nvl(to_date(:V3,'YYMMDDHH24MI'),SYSDATE)) ash, 
                 (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM < 6) r)
  WHERE  NAME IS NOT NULL),
st2 AS(SELECT sample_id, v, rs FROM ash1 WHERE lower(NAME) = lower(:V1)),
st1 AS(SELECT * FROM ash1 WHERE lower(NAME) != lower(:V1)),
RES AS(
    SELECT a.*,CEIL(ROWNUM / 3) r1, MOD(ROWNUM, 3) R2 
    FROM (
        SELECT /*+use_hash(st1 st2) ordered*/ clz CLASS, NAME, CORR(st2.v, st1.v) / COUNT(st2.v) * COUNT(st1.v)*100 coe
        FROM   st2
        LEFT   JOIN st1
        USING  (sample_id)
        GROUP  BY clz, NAME
        HAVING CORR (st2.v, st1.v) IS NOT NULL
        ORDER  BY abs(coe) DESC NULLS LAST) a
    WHERE rownum<=90)
SELECT MAX(DECODE(R2, 1, CLASS)) CLASS,
       MAX(DECODE(R2, 1, NAME)) NAME,
       MAX(DECODE(R2, 1, coe)) "CORR(%)",
       '|' "|",
       MAX(DECODE(R2, 2, CLASS)) CLASS,
       MAX(DECODE(R2, 2, NAME)) NAME,
       MAX(DECODE(R2, 2, coe)) "CORR(%)",
       '|' "|",
       MAX(DECODE(R2, 0, CLASS)) CLASS,
       MAX(DECODE(R2, 0, NAME)) NAME,
       MAX(DECODE(R2, 0, coe)) "CORR(%)"
FROM   res
GROUP  BY r1
ORDER  BY r1