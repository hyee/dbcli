/*[[Show histogram. Usage: ora histogram <table_name>[.<partition_name>] <column_name>]]*/
WITH r AS (
SELECT /*+materialize*/*
FROM   (SELECT endpoint_number Bucket#,
               endpoint_value ev,
               LPAD(to_char(endpoint_value, 'fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'),
                    LENGTHB(high_value),
                    '0') rv,
               endpoint_actual_value,
               high_value,low_value,density, num_nulls, num_distinct,sample_size,data_type,a.column_name,NUM_BUCKETS,HISTOGRAM
        FROM   all_tab_histograms a, All_Tab_Cols b
        WHERE  a.owner = b.owner
        AND    a.table_name = b.table_name
        AND    a.column_name = b.column_name
        AND    upper('.' || a.owner || '.' || a.table_name || '.') LIKE '%.' || UPPER(:V1) || '.%'
        AND    upper(a.column_name) = UPPER(:V2)
        UNION ALL
        SELECT bucket_number Bucket#,
               endpoint_value ev,
               LPAD(to_char(endpoint_value, 'fmxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'),
                    LENGTHB(high_value),
                    '0') rv,
               endpoint_actual_value,
               high_value,low_value,density, num_nulls, num_distinct,sample_size,
               (select data_type from all_tab_cols c where a.owner=c.owner and a.table_name=c.table_name and a.column_name=c.column_name),
               a.partition_name,NUM_BUCKETS,HISTOGRAM
        FROM   all_part_histograms a, All_Part_Col_Statistics b
        WHERE  a.owner = b.owner
        AND    a.table_name = b.table_name
        AND    a.column_name = b.column_name
        AND    a.partition_name = b.partition_name
        AND    instr(UPPER(:V1),upper('.'||a.partition_name))>1
        AND    upper('.' || a.owner || '.' || a.table_name || '.' || a.partition_name || '.') LIKE '%.' || UPPER(:V1) || '.%'
        AND    upper(a.column_name) = UPPER(:V2))),
r1 AS
 (SELECT r.*,
         NVL(endpoint_actual_value,
             CASE
                 WHEN data_type LIKE '%CHAR%' THEN
                  utl_raw.cast_to_varchar2(rv)
                 WHEN data_type LIKE '%N%CHAR%' THEN
                  to_char(utl_raw.cast_to_nvarchar2(rv))
                 WHEN data_type = 'DATE' OR data_type LIKE 'TIMESTAMP' THEN
                  to_char(to_date(trunc(ev), 'J') + MOD(ev, 1),'YYYY-MM-DD' || DECODE(MOD(ev, 1), 0, '', ' HH24:MI:SS'))
                 WHEN data_type IN ('NUMBER', 'BINARY_DOUBLE', 'BINARY_FLOAT') THEN
                  '' || ev
                 ELSE
                  rv
             END) ep_value
  FROM   r)
SELECT column_name,
       Bucket#,
       lag(ep_value) over(ORDER BY Bucket#) bp_value,
       ep_value,
       --(Bucket#-lag(ep_value) over(ORDER BY Bucket#))/count(1) over()* cardinality,
       NULL density,
       NULL num_nulls,
       NULL num_distinct,
       NULL sample_size
FROM   r1