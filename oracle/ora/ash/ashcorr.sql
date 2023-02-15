/*[[Show the coefficient of correlation against the ASH. Usage: @@NAME "<keyword>"  [yymmddhh24mi] [yymmddhh24mi] [-dash]
    --[[
        &V2: default={&starttime}
        &V3: default={&endtime}
        &ASH: default={gv$active_Session_history} dash={dba_hist_active_sess_history}
        @binst: 11={'@'|| BLOCKING_INST_ID} default={''}
        &INST1 : default={inst_id}, dash={instance_number}
    --]]
]]*/

--lag correlation in case of l=0: sum((x-avg(x)) * (y-avg(y))) / sqrt(sum(power(x-avg(x)))) / sqrt(sum(power(y-avg(y))))
WITH ash1 AS
 (SELECT /*+ no_merge(ash) ordered*/  inst,clz,name,sample_id,sum(cost) v
  FROM   (SELECT DECODE(r, 1, 'sql_id', 2, 'event', 3, 'object_id', 4, 'program',5,'blocker',6,'sid') clz,
                 trim(DECODE(r,
                        1,
                        nvl(sql_id,top_level_sql_id),
                        2,
                        NVL(event, 'CPU => ' || TRIM(',' FROM p1text || ',' || p2text || ',' || p3text)),
                        3,
                        CASE WHEN current_obj# > 1 THEN to_char(current_obj#) when current_obj# in(0,-1) then 'UNDO' else '-2' END,
                        4,
                        CASE 
                          WHEN SUBSTR(program,-6) LIKE '(%)' AND upper(SUBSTR(program,-5,1))=SUBSTR(program,-5,1) THEN
                              CASE WHEN SUBSTR(program,-6) LIKE '(%)' AND SUBSTR(program,-5,1) IN('P','W','J') THEN
                                  '('||SUBSTR(program,-5,1)||'nnn)'
                              ELSE regexp_replace(SUBSTR(program,-6),'[0-9a-z]','n') END
                          WHEN instr(program,'@')>1 THEN
                              nullif(substr(program,1,instr(program,'@')-1),'oracle')
                          ELSE program
                        END,
                        5,
                        blocking_session||&binst,
                        6,
                        SESSION_ID||'@'||&INST1)) NAME,
                 nvl(tm_delta_db_time,delta_time) cost,
                 TRUNC(sample_time,'MI') sample_id,
                 &INST1 inst
          FROM   (SELECT /*+no_expand*/ a.* FROM  &ash a 
                  WHERE :V2<100000 AND sample_time+0> SYSDATE-:V2/86400 OR 
                        nvl(:V2,'100000')>=100000 AND  sample_time+0 BETWEEN nvl(to_date(:V2,'YYMMDDHH24MI'),sysdate-1) AND nvl(to_date(:V3,'YYMMDDHH24MI'),SYSDATE+1)) ash, 
                 (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM <=5) r)
  WHERE  NAME IS NOT NULL
  GROUP BY inst,clz,name,sample_id),
st2 AS(SELECT inst,sample_id, v FROM ash1 WHERE lower(NAME) = lower(:V1)),
st1 AS(SELECT * FROM ash1  a
       WHERE lower(NAME) != lower(:V1) 
       AND   exists(select * from (select inst,min(sample_id) mn,max(sample_id) mx from st2 group by inst) b where b.inst=a.inst and a.sample_id between mn and mx)),
RES AS(
    SELECT a.*,CEIL(ROWNUM / 3) r1, MOD(ROWNUM, 3) R2 
    FROM (
        SELECT /*+use_hash(st1 st2) ordered*/ clz CLASS, NAME, ROUND(CORR(st2.v, st1.v) / COUNT(st2.v) * COUNT(st1.v)*100,3) coe
        FROM   st2
        LEFT   JOIN st1
        USING  (inst,sample_id)
        GROUP  BY clz, NAME
        HAVING CORR (st2.v, st1.v) IS NOT NULL
        ORDER  BY abs(coe) DESC NULLS LAST) a
    WHERE rownum<=150 AND ABS(COE)<100)
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