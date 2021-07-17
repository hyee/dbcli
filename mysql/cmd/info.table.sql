/*[[Show table info
    --[[
        @CHECK_USER_TIDB: tidb={LEFT JOIN information_schema.table_storage_stats USING(table_schema,table_name)} default={}
    --]]
]]*/

sql @info.view.sql

print Indexes and Constraints:
print ========================
sql @info.index.sql -t

ENV PIVOT 1 PIVOTSORT OFF

print Table and Partition Info:
print =========================
SELECT A.*,(DATA_LENGTH + INDEX_LENGTH + IFNULL(data_free,0)) `Size`
FROM   (
    SELECT * FROM information_schema.tables &CHECK_USER_TIDB
    WHERE  table_schema=:object_owner
    AND    table_name=:object_name) A
;SELECT concat(partition_method, ' (', partition_expression, ')') `Partition By`,
       COUNT(DISTINCT partition_name) `Partitions`,
       concat(subpartition_method, ' (', subpartition_expression, ')') `Subpartition By`,
       COUNT(DISTINCT subpartition_name) `Subpartitions`
FROM   information_schema.partitions
WHERE  table_schema = :object_owner
AND    table_name = :object_name
AND    partition_name IS NOT NULL
GROUP  BY `Partition By`, `Subpartition By`;