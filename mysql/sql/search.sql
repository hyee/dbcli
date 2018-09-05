/*[[ Fuzzily search object. Usage: @@NAME <keyword> ]]*/
set feed off
set @target=UPPER(concat('%',:V1,'%'))
SELECT M.*
FROM   (SELECT table_schema `Schema`,
               table_name `Top Name`,
               NULL `Sub Name`,
               table_type `Object Type`,
               create_time `Created`,
               update_time `Updated`,
               upper(concat(table_schema, '.', table_name)) `Match`
        FROM   information_schema.tables
        WHERE  upper(concat(table_schema, '.', table_name)) LIKE @target
        UNION
        SELECT table_schema,
               table_name,
               partition_name,
               'PARTITION',
               create_time,
               update_time,
               upper(concat(table_schema, '.', table_name, '.', partition_name))
        FROM   information_schema.partitions
        WHERE  upper(concat(table_schema, '.', table_name, '.', partition_name)) LIKE @target
        UNION
        SELECT table_schema,
               table_name,
               subpartition_name,
               'SUB-PARTITION',
               create_time,
               update_time,
               upper(concat(table_schema, '.', table_name, '.', subpartition_name))
        FROM   information_schema.partitions
        WHERE  upper(concat(table_schema, '.', table_name, '.', subpartition_name)) LIKE @target
        UNION
        SELECT trigger_schema, event_object_table, trigger_name, 'Trigger', created, NULL, upper(concat(trigger_schema, '.', trigger_name))
        FROM   information_schema.triggers
        WHERE  upper(concat(trigger_schema, '.', trigger_name)) LIKE @target
        UNION
        SELECT DISTINCT index_schema, table_name, index_name, 'INDEX', NULL, NULL, upper(concat(index_schema, '.', index_name))
        FROM   information_schema.statistics
        WHERE  upper(concat(index_schema, '.', index_name)) LIKE @target) AS M
WHERE @target<>'%%' 
order by case when `Schema`=database() then 0 else 1 end, 
         abs(substring(soundex(`Match`),2)-substring(soundex(upper(:V1)),2))
limit 100;
