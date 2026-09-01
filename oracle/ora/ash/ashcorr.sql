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
  FROM   (SELECT decode(r, 1, 'sql_id', 2, 'event', 3, 'object_id', 4, 'program',5,'blocker',6,'sid') clz,
                 trim(decode(r,
                        1,
                        nvl(sql_id,top_level_sql_id),
                        2,
                        nvl(event, 'CPU => ' || trim(',' FROM p1text || ',' || p2text || ',' || p3text)),
                        3,
                        CASE WHEN current_obj# > 1 THEN to_char(current_obj#) WHEN current_obj# IN(0,-1) THEN 'UNDO' ELSE '-2' END,
                        4,
                        CASE 
                          WHEN substr(program,-6) LIKE '(%)' AND upper(substr(program,-5,1))=substr(program,-5,1) THEN
                              CASE WHEN substr(program,-6) LIKE '(%)' AND substr(program,-5,1) IN('P','W','J') THEN
                                  '('||substr(program,-5,1)||'nnn)'
                              ELSE regexp_replace(substr(program,-6),'[0-9a-z]','n') END
                          WHEN instr(program,'@')>1 THEN
                              nullif(substr(program,1,instr(program,'@')-1),'oracle')
                          ELSE program
                        END,
                        5,
                        blocking_session||&binst,
                        6,
                        session_id||'@'||&INST1)) name,
                 nvl(tm_delta_db_time,delta_time) cost,
                 trunc(sample_time,'MI') sample_id,
                 &INST1 inst
          FROM   (SELECT /*+no_expand*/ a.* FROM  &ash a 
                  WHERE :V2<100000 AND sample_time+0> sysdate-:V2/86400 OR 
                        nvl(:V2,'100000')>=100000 AND  sample_time+0 BETWEEN nvl(to_date(:V2,'YYMMDDHH24MI'),sysdate-1) AND nvl(to_date(:V3,'YYMMDDHH24MI'),sysdate+1)) ash, 
                 (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM <=5) r)
  WHERE  name IS NOT NULL
  GROUP BY inst,clz,name,sample_id),
st2 AS(SELECT inst,sample_id, v FROM ash1 WHERE lower(name) = lower(:V1)),
st1 AS(SELECT * FROM ash1  a
       WHERE lower(name) != lower(:V1) 
       AND   EXISTS(SELECT * FROM (SELECT inst,min(sample_id) mn,max(sample_id) mx FROM st2 GROUP BY inst) b WHERE b.inst=a.inst AND a.sample_id BETWEEN mn AND mx)),
res AS(
    SELECT a.*,ceil(ROWNUM / 3) r1, mod(ROWNUM, 3) r2 
    FROM (
        SELECT /*+use_hash(st1 st2) ordered*/ clz class, name, round(corr(st2.v, st1.v) / count(st2.v) * count(st1.v)*100,3) coe
        FROM   st2
        LEFT   JOIN st1
        USING  (inst,sample_id)
        GROUP  BY clz, name
        HAVING corr (st2.v, st1.v) IS NOT NULL
        ORDER  BY abs(coe) DESC NULLS LAST) a
    WHERE ROWNUM<=150 AND abs(coe)<100)
SELECT max(decode(r2, 1, class)) class,
       max(decode(r2, 1, name)) name,
       max(decode(r2, 1, coe)) "CORR(%)",
       '|' "|",
       max(decode(r2, 2, class)) class,
       max(decode(r2, 2, name)) name,
       max(decode(r2, 2, coe)) "CORR(%)",
       '|' "|",
       max(decode(r2, 0, class)) class,
       max(decode(r2, 0, name)) name,
       max(decode(r2, 0, coe)) "CORR(%)"
FROM   res
GROUP  BY r1
ORDER  BY r1