/*[[Show system metric based on AWR data. Usage: ora sysmtx [yyyymmddhh24mi] [yyyymmddhh24mi] [inst_id] ]]*/

SELECT metric_name, round(AVG(average), 2) average, '| '||metric_unit unit
FROM   dba_hist_sysmetric_summary
WHERE  BEGIN_TIME<=NVL(to_char(:V2,'yyyymmddhh24mi'),sysdate)
AND    END_TIME>=NVL(to_char(:V1,'yyyymmddhh24mi'),sysdate-1)
AND    INSTANCE_NUMBER=NVL(:V3,INSTANCE_NUMBER)
GROUP  BY metric_name, metric_unit
HAVING round(AVG(average),2)>0
ORDER BY 1
