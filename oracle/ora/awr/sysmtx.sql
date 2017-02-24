/*[[Show system metric based on AWR data. Usage: @@NAME {[yymmddhh24mi] [yymmddhh24mi] [inst_id]} ]]*/
set digits 3

SELECT COALESCE(:V3,:INSTANCE,'A') INST_ID,CATEGORY,metric_name,
       case when unit like '%\% %' escape '\' then avg(current_) else sum(current_) end current_,
       case when unit like '%\% %' escape '\' then avg(awr_avg)  else sum(awr_avg)  end awr_avg,
       sum(current_)*100/nullif(sum(awr_avg),0) "Ratio(%)",unit
FROM (
    SELECT /*+no_merge*/ INSTANCE_NUMBER INST_ID,metric_name, AVG(average) awr_avg, '| '||metric_unit unit
    FROM   dba_hist_sysmetric_summary
    WHERE  BEGIN_TIME<=NVL(to_date(NVL(:V2,:ENDTIME),'yymmddhh24mi'),sysdate)
    AND    END_TIME>=NVL(to_date(NVL(:V1,:STARTTIME),'yymmddhh24mi'),sysdate-7)
    AND    INSTANCE_NUMBER=COALESCE(0+:V3,INSTANCE_NUMBER)
    AND    group_id=2
    GROUP  BY INSTANCE_NUMBER,metric_name, metric_unit) d 
    NATURAL JOIN
   (SELECT /*+no_merge*/ c.inst_id,c.metric_name,a.INTERNAL_METRIC_CATEGORY CATEGORY,c.average current_
    FROM   v$alert_types a, V$THRESHOLD_TYPES b, gv$sysmetric_summary c
    WHERE  a.reason_id = b.ALERT_REASON_ID
    AND    b.metrics_id = c.metric_id
    AND    b.metrics_group_id = c.group_id
    AND    c.group_id = 2) v
WHERE current_+awr_avg>1e-3
GROUP BY CATEGORY,metric_name,unit
ORDER BY "Ratio(%)" desc nulls last