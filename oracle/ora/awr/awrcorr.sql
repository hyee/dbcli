/*[[
    Show the coefficient of correlation against the specific stats/event/latch/etc. Usage: @@NAME "<name>" [yymmddhh24mi] [yymmddhh24mi] [inst_id] [source] [-p|-k|-s]
    
    source:  filter by the source_table field
    -p    :  sort by the Pearson's rho correlation coefficient(CORR_S), this is the default.
    -s    :  sort by the Spearman's rho correlation coefficient(CORR_S) 
    -k    :  sort by the Kendall's tau-b correlation coefficient(CORR_K)
    -a    :  sort by the sum of above options
    --[[
        @ARGS: 1
        &V4: default={&instance}
        &V2: default={&starttime}
        &V3: default={&endtime}
        &V1: default={Database CPU Time Ratio}
        &BASE: p={cop} s={cox} k={cok} a={cop+cox+cok}
        &co  : {
            default={st0 as(select * from STATS where LOWER(NAME) != LOWER(:V1) AND (:V5 is null or regexp_like(source_table||' '||lower(name),lower(:V5) ))),
                     ss as(select snap_id from st0 union select snap_id from st2),
                     st1 as(select source_table,name,snap_id,nvl(value,0) value from (select * from (select distinct source_table,name from st0),ss) LEFT JOIN st0 USING(snap_id,source_table,name)),    
                     res as(SELECT source_table,name, CEIL(ROWNUM / 2) r1, MOD(ROWNUM, 2) R2, cop,cox,cok
                          FROM   (SELECT --+ no_merge(st1) no_merge(st2) use_hash(st1 st2)
                                         replace(source_table,'dba_hist_') source_table, NAME, 
                                         trunc(CORR(st1.value,st2.value) * 100,3) cop,
                                         trunc(CORR_S(NVL(st1.value,0),nvl(st2.value,0)) * 100,3) cox,
                                         trunc(CORR_K(NVL(st1.value,0),nvl(st2.value,0),'COEFFICIENT') * 100,3) cok
                                  FROM   st1 
                                  JOIN   (select snap_id,nvl(value,0) value from ss left join st2 USING(snap_id)) st2 USING(snap_id)
                                  GROUP  BY source_table, NAME
                                  ORDER  BY abs(&base) desc nulls last) a
                          WHERE  ROWNUM <= 140 AND ABS(&BASE) NOT IN(100,300))
                    SELECT MAX(DECODE(R2, 1, source_table)) source_table,
                           MAX(DECODE(R2, 1, NAME)) NAME,
                           MAX(DECODE(R2, 1, cop)) "CORR(%)",
                           MAX(DECODE(R2, 1, cox)) "CORR_S(%)",
                           MAX(DECODE(R2, 1, cok)) "CORR_K(%)",
                           '|' "|",
                           MAX(DECODE(R2, 0, source_table)) source_table,
                           MAX(DECODE(R2, 0, NAME)) NAME,
                           MAX(DECODE(R2, 0, cop)) "CORR(%)",
                           MAX(DECODE(R2, 0, cox)) "CORR_S(%)",
                           MAX(DECODE(R2, 0, cok)) "CORR_K(%)"
                    FROM   res
                    GROUP  BY r1
                    ORDER  BY r1},
            d={res AS (
                   select --+ no_merge(st1) no_merge(st2)
                          snap_time , name, unit, st1.value value, st2.value target_value, 
                          CORR(NVL(st1.value,0),nvl(st2.value,0)) over(order by snap_time) * 100 "CORR(%)"
                   FROM   st2 full join (select * from stats where LOWER(NAME) = LOWER('&0') or LOWER(NAME) like '%] &0') st1 USING (snap_id, snap_time)
               ) select * from res
            } 
        }
    --]]
    
]]*/
PRO Target: &V1
SET FEED OFF
WITH snap AS(
    SELECT a.*,
           MAX(snap_id) over(PARTITION BY pkey ORDER BY etime RANGE BETWEEN UNBOUNDED PRECEDING AND diff PRECEDING) min_snap,
           round(86400*(etime-LAG(etime,1,stime) OVER(PARTITION BY pkey ORDER BY snap_id))) secs
    FROM   (SELECT /*+no_merge no_expand no_or_expand*/ 
                   snap_id,
                   dbid,
                   instance_number,
                   instance_number inst_id,
                   begin_interval_time+0 btime,
                   MAX(end_interval_time+0) OVER(PARTITION BY snap_id) etime,
                   startup_time+0 stime,
                   (dbid+to_char(startup_time,'yymmddhh24mi'))*1e3+instance_number pkey,
                   (end_interval_time+0) - GREATEST(startup_time+0, MIN(end_interval_time+0) over(PARTITION BY instance_number,startup_time)) diff
            FROM   dba_hist_snapshot
            WHERE  dbid=:dbid
             AND   end_interval_time+0 BETWEEN 
                   NVL(to_date(:V2,'yymmddhh24miss'),sysdate-7) AND 
                   NVL(to_date(:V3,'yymmddhh24miss'),sysdate+1)
             AND  (:V4 IS NULL OR lower(:V4) IN ('0', 'a') OR instance_number = :V4)) a),
STATS AS
 (SELECT /*+materialize no_expand*/
         source_table, snap_id,etime snap_time,unit, NAME, SUM(VALUE) VALUE
  FROM   (SELECT 'dba_hist_sysstat' source_table,
                 inst_id,
                 snap_id,etime,
                 STAT_NAME NAME,
                 'count' unit,
                 VALUE - LAG(VALUE) OVER(PARTITION BY STAT_NAME, pkey ORDER BY snap_id) VALUE
          FROM   snap
          JOIN   dba_hist_sysstat
          USING  (dbid, instance_number, snap_id)
          WHERE  VALUE > 0
          AND    dbid = :dbid
          UNION ALL
          SELECT 'dba_hist_dlm_misc' source_table,
                 inst_id,
                 snap_id,etime,
                 NAME,
                 'count' unit,
                 VALUE - LAG(VALUE) OVER(PARTITION BY NAME, pkey ORDER BY snap_id) VALUE
          FROM   snap
          JOIN   dba_hist_dlm_misc
          USING  (dbid, instance_number, snap_id)
          WHERE  VALUE > 0
          AND    dbid = :dbid
          UNION ALL
          SELECT 'dba_hist_sysmetric_summary' source_table, inst_id, snap_id,etime, metric_name NAME, metric_unit, AVERAGE
          FROM   snap
          JOIN   dba_hist_sysmetric_summary
          USING  (dbid, instance_number, snap_id)
          WHERE  dbid = :dbid
          UNION ALL
          SELECT 'dba_hist_system_event' source_table,
                 inst_id,
                 snap_id,etime,
                 '['||wait_class||'] '||event_name,
                 'us',
                 TIME_WAITED_MICRO - LAG(TIME_WAITED_MICRO) OVER(PARTITION BY event_name, pkey ORDER BY snap_id)
          FROM   snap
          JOIN   dba_hist_system_event
          USING  (dbid, instance_number, snap_id)
          WHERE  TIME_WAITED_MICRO > 0
          AND    wait_class!='Idle'
          AND    dbid = :dbid
          UNION ALL
          SELECT 'dba_hist_sys_time_model' source_table,
                 inst_id,
                 snap_id,etime,
                 STAT_NAME,
                 'us',
                 value - LAG(value) OVER(PARTITION BY STAT_NAME, pkey ORDER BY snap_id)
          FROM   snap
          JOIN   dba_hist_sys_time_model
          USING  (dbid, instance_number, snap_id)
          WHERE  value > 0
          AND    dbid = :dbid
          UNION ALL
          SELECT 'dba_hist_latch' source_table,
                 inst_id,
                 snap_id,etime,
                 latch_name,
                 'gets',
                 gets + immediate_gets - LAG(gets + immediate_gets) OVER(PARTITION BY latch_name, pkey ORDER BY snap_id)
          FROM   snap
          JOIN   dba_hist_latch
          USING  (dbid, instance_number, snap_id)
          WHERE  gets + immediate_gets > 0
          AND    dbid = :dbid
          UNION ALL
          SELECT 'dba_hist_mutex_sleep' source_table,
                 inst_id,
                 snap_id,etime,
                 '['||MUTEX_TYPE || '] ' || TRIM(REPLACE(LOCATION, CHR(10))),
                 'us',
                 wait_time -LAG(wait_time) OVER(PARTITION BY '['||MUTEX_TYPE || '] ' || TRIM(REPLACE(LOCATION, CHR(10))), pkey ORDER BY snap_id)
          FROM   snap
          JOIN   dba_hist_mutex_sleep
          USING  (dbid, instance_number, snap_id)
          WHERE  wait_time > 0
          AND    dbid = :dbid
          UNION ALL
          SELECT 'dba_hist_sgastat' source_table, 
                 inst_id, 
                 snap_id,etime, 
                 nullif('['||pool || '] ', '[] ') || TRIM(REPLACE(NAME, CHR(10))), 'bytes', bytes-LAG(bytes) OVER(PARTITION BY NAME, pkey ORDER BY snap_id)
          FROM   snap
          JOIN   dba_hist_sgastat
          USING  (dbid, instance_number, snap_id)
          WHERE  dbid = :dbid)
  GROUP  BY source_table, snap_id, etime,unit, NAME
  HAVING SUM(VALUE)>0),
st2 as (SELECT /*+no_merge no_expand*/ snap_id, snap_time, VALUE FROM STATS WHERE LOWER(NAME) =LOWER(:V1) or LOWER(NAME) like '%] '||LOWER(:V1)),
&co 
;
