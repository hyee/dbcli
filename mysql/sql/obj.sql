/*[[List the objects that meet the input criteria. Usage: @@NAME [<owner>.]<object_name>[.<partition>]
    --[[
        @ARGS: 1
    --]]
]]*/

env feed off
findobj "&V1" 0 1

SELECT * FROM (
    SELECT table_schema `Schema`,
           table_name `Top Name`,
           IFNULL(subpartition_name,partition_name) `Sub Name`,
           ELT(FIELD(COALESCE(subpartition_name,partition_name,''),'',partition_name,subpartition_name),'TABLE','PARTITON','SUBPARTITION') `Object Type`,
           create_time `Created`,
           update_time `Updated`
    FROM   information_schema.partitions
    WHERE  table_schema=:object_owner
    AND    table_name=:object_name
    AND    IFNULL(:object_subname,'') IN('',partition_name,subpartition_name)
    UNION ALL
    SELECT DISTINCT 
           index_schema,
           index_name COLLATE utf8_general_ci,
           NULL,
           'INDEX',
           NULL,
           NULL
    FROM   information_schema.statistics
    WHERE  IFNULL(:object_subname,'')=''
    AND    index_schema=:object_owner
    AND    index_name=:object_name
    UNION ALL
    SELECT routine_schema,
           routine_name,
           null,
           routine_type,
           created,
           last_altered
    FROM   information_schema.routines
    WHERE  IFNULL(:object_subname,'')=''
    AND    routine_schema=:object_owner
    AND    routine_name=:object_name
    UNION ALL
    SELECT trigger_schema,
           event_object_table,
           trigger_name COLLATE utf8_general_ci,
           'TRIGGER',
           created,
           NULL
    FROM   information_schema.triggers
    WHERE  IFNULL(:object_subname,'')=''
    AND    trigger_schema=:object_owner
    AND    trigger_name=:object_name) AS M
ORDER BY 1,2,3
LIMIT 50;