/*[[
    Show system metric based on AWR data. Usage: @@NAME {[yymmddhh24mi] [yymmddhh24mi] [inst_id]} 
    Sample Output:
    ==============
    INST_ID           CATEGORY             METRIC_NAME                                   CURRENT_   AWR_AVG    Ratio(%)                UNIT
    ------- ----------------------------- --------------------------------------------- ---------- ---------- ---------- --------------------------------
    A       instance_throughput           Physical Reads Direct Lobs Per Txn               262.377      0.037 715821.244 | Reads Per Txn
    A       instance_throughput           Physical Reads Direct Lobs Per Sec                 4.371      0.002 187169.002 | Reads Per Second
    A       instance_throughput           Physical Writes Direct Per Txn                  1129.275     15.724   7181.822 | Writes Per Txn
    A       instance_throughput           Physical Writes Direct Per Sec                    19.032      0.271   7026.776 | Writes Per Second
    A       instance_throughput           Physical Reads Direct Per Txn                    881.221     13.485   6534.946 | Reads Per Txn
    A       instance_throughput           Physical Reads Direct Per Sec                     14.771      0.262   5635.359 | Reads Per Second
    A       instance_throughput           Physical Reads Per Txn                           902.483     30.882   2922.341 | Reads Per Txn
    A       instance_throughput           Total Index Scans Per Txn                       5024.988    181.493   2768.698 | Scans Per Txn
    A       instance_throughput           Physical Reads Per Sec                            15.132      0.567   2668.888 | Reads Per Second
    A       instance_throughput           Physical Writes Direct Lobs  Per Txn               0.045      0.003   1778.713 | Writes Per Txn
    A       instance_throughput           Physical Writes Direct Lobs Per Sec                0.005      0.000   1771.269 | Writes Per Second
    A       instance_throughput           Total Index Scans Per Sec                         86.451      7.065   1223.586 | Scans Per Second
    A       instance_throughput           Hard Parse Count Per Txn                           2.582      0.215   1198.590 | Parses Per Txn
    --[[
        @ALIAS: sysmetric
    ]]--
]]*/
set digits 3

SELECT COALESCE(:V3,:INSTANCE,'A') INST_ID,CATEGORY,metric_name,
       case when unit like '%\% %' escape '\' or metric_name like '%Average%' then avg(current_) else sum(current_) end current_,
       case when unit like '%\% %' escape '\' or metric_name like '%Average%' then avg(awr_avg)  else sum(awr_avg)  end awr_avg,
       sum(current_)*100/nullif(sum(awr_avg),0) "Ratio(%)",unit
FROM (
    SELECT /*+no_merge*/ INSTANCE_NUMBER INST_ID,metric_name, median(average) awr_avg, '| '||metric_unit unit
    FROM   dba_hist_sysmetric_summary
    WHERE  BEGIN_TIME<=NVL(to_date(NVL(:V2,:ENDTIME),'yymmddhh24mi'),sysdate+1)
    AND    END_TIME>=NVL(to_date(NVL(:V1,:STARTTIME),'yymmddhh24mi'),sysdate-7)
    AND    INSTANCE_NUMBER=COALESCE(0+:V3,INSTANCE_NUMBER)
    AND    group_id=2
    GROUP  BY INSTANCE_NUMBER,metric_name, metric_unit) d 
    LEFT JOIN
   (SELECT /*+no_merge*/ c.inst_id,c.metric_name,a.INTERNAL_METRIC_CATEGORY CATEGORY,c.average current_
    FROM   v$alert_types a, V$THRESHOLD_TYPES b, gv$sysmetric_summary c
    WHERE  a.reason_id = b.ALERT_REASON_ID
    AND    b.metrics_id = c.metric_id
    AND    b.metrics_group_id = c.group_id
    AND    c.group_id = 2) V USING(INST_ID,metric_name)
WHERE NVL(current_,0)+awr_avg>1e-3
GROUP BY CATEGORY,metric_name,unit
ORDER BY "Ratio(%)" desc nulls last