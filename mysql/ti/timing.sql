/*[[Show TiDB metrics time modules within 10 minutes. Usage: @@NAME [<instance> | {-m <metric_name>}]  [-a]
    -m <metric_name>: The <metric_name> that can be found as table of metrics_schema.<metric_name>_*
    -a              : Use metrics_summary as the source table to query the stats within 30 minutes
    --[[
        &filter: default={value>0 and (\'&V1\' IS NULL OR lower(instance) LIKE lower(concat(\'%&V1%\')))}
        &grp   : default={--}     a={}
        &grp1  : default={--}     m={}
        &grp2  : default={}       a={--}
        &c1    : default={&grp}   m={} 
        &c2    : default={}       m={&grp}
        &c3    : default={}       a={&grp1}
        &c4    : default={}       m={&grp2}
    --]]
]]*/

COL "max|time,max|duration,time,duration,avg_time,Avg|Time,Avg|Dur,0 Min|Time,1 Min|Time,2 Min|Time,3 Min|Time,4 Min|Time,5 Min|Time,6 Min|Time,7 Min|Time,8 Min|Time,9 Min|Time" FOR usmhd2
COL "max|count,count,Avg|Count,0 Min|Count,1 Min|Count,2 Min|Count,3 Min|Count,4 Min|Count,5 Min|Count,6 Min|Count,7 Min|Count,8 Min|Count,9 Min|Count" FOR TMB2
col qry new_value qry noprint

&c1./*

WITH r AS
 (SELECT REPLACE(A.table_name, concat('_',suffix), '') t
  FROM   information_schema.metrics_tables A
  JOIN   (SELECT DISTINCT table_name, substring_index(table_name, '_', -2) suffix
         FROM   information_schema.COLUMNS
         WHERE  UPPER(COLUMN_NAME) = 'INSTANCE'
         AND    UPPER(TABLE_SCHEMA) = 'METRICS_SCHEMA') B
  USING  (table_name)
  WHERE  suffix IN ('total_time', 'total_count')
  GROUP  BY t
  HAVING COUNT(1) = 2 AND t NOT IN('tidb_connection_idle')
  ORDER  BY 1)
SELECT group_concat(qry ORDER BY qry separator ' union all\n') qry
FROM   (SELECT concat('select ''' , t , ''', time, instance, ''t'',value from metrics_schema.' , t , '_total_time where &filter') qry
        FROM   r
        UNION ALL
        SELECT concat('select ''' , t , ''', time, instance, ''c'',value from metrics_schema.' , t , '_total_count where &filter')
        FROM   r);

WITH R(n,time,instance,t,v) AS(&qry)
SELECT n `Unit: per second|Metric Name`,
       MAX(jobs) `Inst|Type`,
       MAX(inst) `Inst|Count`,
       '|' `|`,
       AVG(if(t='t',v,NULL)) `Avg|Time`,
       AVG(if(t='c',v,NULL)) `Avg|Count`,
       Round(AVG(if(t='t',v,NULL))/AVG(if(t='c',v,NULL)),2) `Avg|Dur`,
       '|'  `|`,
       MAX(if(t='t' AND ts=0,v,0)) `0 Min|Time`,
       MAX(if(t='c' AND ts=0,v,0)) `0 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=1,v,0)) `1 Min|Time`,
       MAX(if(t='c' AND ts=1,v,0)) `1 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=2,v,0)) `2 Min|Time`,
       MAX(if(t='c' AND ts=2,v,0)) `2 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=3,v,0)) `3 Min|Time`,
       MAX(if(t='c' AND ts=3,v,0)) `3 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=4,v,0)) `4 Min|Time`,
       MAX(if(t='c' AND ts=4,v,0)) `4 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=5,v,0)) `5 Min|Time`,
       MAX(if(t='c' AND ts=5,v,0)) `5 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=6,v,0)) `6 Min|Time`,
       MAX(if(t='c' AND ts=6,v,0)) `6 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=7,v,0)) `7 Min|Time`,
       MAX(if(t='c' AND ts=7,v,0)) `7 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=8,v,0)) `8 Min|Time`,
       MAX(if(t='c' AND ts=8,v,0)) `8 Min|Count`,
       '|' `|`,
       MAX(if(t='t' AND ts=9,v,0)) `9 Min|Time`,
       MAX(if(t='c' AND ts=9,v,0)) `9 Min|Count`
FROM (
    SELECT n,
           floor(time_to_sec(timediff(now(),time))/60) ts,
           t,
           group_concat(DISTINCT job order by job separator ', ') jobs,
           count(distinct instance) inst,
           round(SUM(v)/60*CASE WHEN t='t' AND n='tidb_batch_client_wait' THEN 1e-3 WHEN t='t' and n!='tidb_get_token' THEN 1E6 ELSE 1 END,2) v
    FROM   r LEFT JOIN (select distinct instance,job from metrics_schema.process_cpu_usage) r1 USING(instance)
    GROUP  BY n,ts,t) A
GROUP BY n
ORDER BY `Avg|Time` DESC;

&c1.*/ 

&c2./*

col minute break -
env colsep |

SELECT IFNULL(concat('select A.*,time/count `Avg_Time` from (\n',group_concat(qry ORDER BY n separator '\n'),'\n) A order by Minute desc,time desc'),'SELECT ''No such metrics'' error') qry
FROM (
SELECT concat(IF(n = 'A1', '  SELECT * FROM\n    ', '    JOIN  '),
              qry,
              ' ',
              n,
              IF(n = 'A1', '', CONCAT(' USING(', concat_ws(',', 'Minute', cols), ')'))) qry,n
FROM   (SELECT concat_ws(' ','(SELECT',
                  concat_ws(',',
                            'DATE_FORMAT(time,''%m-%d %H:%i'') Minute',
                            cols,
                            IF(unit = 'time','group_concat(DISTINCT job order by job separator \', \') type,Count(1) Instances',null),
                            CONCAT(IF(unit = 'duration', 'AVG(value)', 'SUM(value)/60'),
                                   CASE WHEN unit = 'count' OR table_name LIKE 'tidb_get_token%' THEN ' '
                                        WHEN unit!= 'count' AND table_name like 'tidb_batch_client_wait%' THEN '*1e-3 '
                                        ELSE '*1e6 '
                                   END,
                                   unit)),
                  'from',
                  'metrics_schema.',
                  table_name,
                  IF(unit = 'time','r LEFT JOIN (select distinct instance,job from metrics_schema.process_cpu_usage) r1 USING(instance)',''),
                  'where value>0',
                  concat_ws(',', 'group by Minute', cols),
                  ')') qry,
               CASE unit WHEN 'time' THEN 'A1' WHEN 'count' THEN 'A2' ELSE 'A3' END n,
               cols
        FROM   information_schema.METRICS_TABLES A
        JOIN   (SELECT table_name,
                      substring_index(lower(table_name), '_', -1) unit,
                      GROUP_CONCAT(CASE WHEN lower(column_name) in ('type','sql_type') THEN lower(column_name) END 
                                   ORDER BY column_name DESC SEPARATOR ',') cols
               FROM   information_schema.COLUMNS
               WHERE  lower(table_name) LIKE lower('&V1%')
               GROUP  BY table_name) B
        USING  (table_name)
        WHERE  lower(table_name) regexp lower('&V1(_total_time|_total_count|_duration)$')) C
ORDER BY n) d;
ECHO =============================================================================
ECHO Querying tables `metrics_schema.&V1._*` (Unit: per second)...
ECHO =============================================================================
&qry;

&c2.*/

&c3./*
SELECT n `Metric Name`,
       MAX(IF(t='time',s*adj,0)) `Time`,
       MAX(IF(t='count',s*adj,0)) `Count`,
       MAX(IF(t='time',s*adj,0))/NULLIF(MAX(IF(t='count',s*adj,NULL)),0) `Avg_Time`,
       MAX(IF(t='duration',s*adj,0)) `Duration`,
       '|' `|`,
       SUM(IF(t='time',max_value*adj/60,0)) `Max|Time`,
       SUM(IF(t='count',max_value*adj/60,0)) `Max|Count`,
       AVG(IF(t='duration',max_value*adj,NULL)) `Max|Duration`,
       '|' `|`,
       MAX(IF(t='count',COMMENT,NULL)) COMMENT
FROM (
    SELECT lower(REPLACE(REPLACE(metrics_name, concat('_', t), ''), '_total', '')) n,
           IF(t='duration',avg_value,sum_value/31/60) s,
           CASE WHEN t IN('duration','time') THEN 
                CASE WHEN metrics_name LIKE 'tidb_batch_client_wait%' THEN 1e-3 
                     WHEN metrics_name LIKE 'tidb_get_token%' THEN 1
                     ELSE 1e6
                END
                ELSE 1
           END adj,
           a.*
    FROM   (SELECT a.*,substring_index(metrics_name, '_', -1) t FROM information_schema.metrics_summary a) a
    WHERE  SUM_VALUE > 0
    AND    lower(metrics_name) NOT LIKE 'tidb_connection_idle%'
    AND    lower(metrics_name) regexp '(_total_count|_total_time|_duration)$') A
GROUP BY n
HAVING `Time`>0 AND `Count`>0
ORDER BY `Time` DESC;

&c3.*/

&c4./*
col "Metric Name" break -
env colsep |

SELECT concat(n,'/sec') `Metric Name`,
       label `Label`,
       group_concat(DISTINCT job order by job separator ', ') `Types`,
       count(DISTINCT inst) `Instances`,
       SUM(IF(t='time',s*adj,0)) `Time`,
       SUM(IF(t='count',s*adj,0)) `Count`,
       AVG(IF(t='duration',s*adj,NULL)) `Duration`,
       SUM(IF(t='time',s*adj,0))/NULLIF(SUM(IF(t='count',s*adj,NULL)),0) `Avg_Time`,
       '|/|' `|/|`,
       SUM(IF(t='time',max_value*adj/60,0)) `Max|Time`,
       SUM(IF(t='count',max_value*adj/60,0)) `Max|Count`,
       AVG(IF(t='duration',max_value*adj,NULL)) `Max|Duration`
FROM (
    SELECT lower(REPLACE(REPLACE(metrics_name, concat('_', t), ''), '_total', '')) n,
           Instance inst,
           IF(t='duration',avg_value,sum_value/31/60) s,
           CASE WHEN t IN('duration','time') THEN 
                CASE WHEN metrics_name LIKE 'tidb_batch_client_wait%' THEN 1e-3 
                     WHEN metrics_name LIKE 'tidb_get_token%' THEN 1
                     ELSE 1e6
                END
                ELSE 1
           END adj,
           a.*
    FROM   (SELECT a.*,substring_index(metrics_name, '_', -1) t FROM information_schema.metrics_summary_by_label a) a
    WHERE  SUM_VALUE > 0
    AND    lower(metrics_name) regexp '(_total_time|_total_count|_duration)$'
    AND    lower(metrics_name) LIKE lower('%&V1%')) A
LEFT   JOIN (select distinct instance,job from metrics_schema.process_cpu_usage) r1 USING(instance)
GROUP BY n,label
HAVING `Time`>0 AND `Count`>0
ORDER BY n,`Time` DESC;

&c4.*/