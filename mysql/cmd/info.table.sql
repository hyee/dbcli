/*[[Show table info
    --[[
        @CHECK_USER_TIDB1: tidb={LEFT JOIN information_schema.table_storage_stats USING(table_schema,table_name)} default={}
        @CHECK_USER_TIDB2: tidb={SELECT Table_Id,Peer_Count,Region_Count,Empty_Region_Count,Table_Size*1024*1024 volumn,Table_Keys table_rows FROM TABLE_STORAGE_STATS WHERE table_schema = :object_owner AND table_name = :object_name;} default={}
    --]]
]]*/

sql @info.view.sql

print Indexes and Constraints:
print ========================
sql @info.index.sql -t

ENV PIVOT 1 PIVOTSORT OFF
COL volumn,Data_Length,Index_Length,Data_Free,size for kmg2
COL Table_rows for tmb2

print Table and Partition Info:
print =========================
SELECT A.*,(DATA_LENGTH + INDEX_LENGTH + IFNULL(data_free,0)) `Size`
FROM   (
    SELECT * FROM information_schema.tables &CHECK_USER_TIDB1
    WHERE  table_schema=:object_owner
    AND    table_name=:object_name) A
;SELECT concat(partition_method, ' (', partition_expression, ')') `Partition By`,
       COUNT(DISTINCT partition_name) `Partitions`,
       concat(subpartition_method, ' (', subpartition_expression, ')') `Subpartition By`,
       COUNT(DISTINCT subpartition_name) `Subpartitions`,
       SUM(TABLE_ROWS) TABLE_ROWS,
       ROUND(AVG(AVG_ROW_LENGTH),2) AVG_ROW_LENGTH,
       SUM(DATA_LENGTH) DATA_LENGTH,
       SUM(INDEX_LENGTH) INDEX_LENGTH,
       SUM(DATA_FREE) DATA_FREE
FROM   information_schema.partitions
WHERE  table_schema = :object_owner
AND    table_name = :object_name
AND    partition_name IS NOT NULL
GROUP  BY `Partition By`, `Subpartition By`;&CHECK_USER_TIDB2