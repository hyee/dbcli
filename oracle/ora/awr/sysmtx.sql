/*[[Show system metric based on AWR data. Usage: @@NAME [yymmddhh24mi] [yymmddhh24mi] [inst_id] ]]*/

SELECT metric_name, round(AVG(average), 2) average, '| '||metric_unit unit
FROM   dba_hist_sysmetric_summary
WHERE  BEGIN_TIME<=NVL(to_date(NVL(:V2,:ENDTIME),'yymmddhh24mi'),sysdate)
AND    END_TIME>=NVL(to_date(NVL(:V1,:STARTTIME),'yymmddhh24mi'),sysdate-1)
AND    INSTANCE_NUMBER=COALESCE(0+:V3,0+:INSTANCE,INSTANCE_NUMBER)
GROUP  BY metric_name, metric_unit
HAVING round(AVG(average),2)>0
ORDER BY 1
