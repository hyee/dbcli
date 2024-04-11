/*[[ Fuzzily search objects. Usage: @@NAME <keyword> [-u | -f"<filter>"]
    -f"<filter>": Customize the other `WHERE` clause
    -u          : Only list the statements for current database
  --[[
        @ARGS: 1
        &filter: {
            default={1=1}
            f={}
            u={`Schema`=database()}
        }
  --]]
]]*/
env feed off
set @target=UPPER(concat('%',:V1,'%'));

SELECT M.*
FROM   (SELECT table_schema `Schema`,
               table_name `Object Name`,
               ELT(matches,NULL,partition_name,subpartition_name) `Sub Name`,
               ELT(matches,'TABLE','PARTITION','SUBPARTITION') `Object Type`,
               create_time `Created`,
               update_time `Updated`,
               concat_ws('.',table_schema,table_name,ELT(matches,null,partition_name,subpartition_name)) `Full Name`,
               'information_schema.partitions' `Source`
        FROM   (SELECT table_schema,table_name,partition_name,subpartition_name,create_time,update_time,
                       CASE WHEN UPPER(concat(table_schema, '.', table_name)) LIKE @target THEN 1
                            WHEN UPPER(concat_ws('.',table_schema,table_name,partition_name)) LIKE @target THEN 2
                            WHEN UPPER(concat_ws('.',table_schema,table_name,subpartition_name)) LIKE @target THEN 3
                            ELSE 0
                       END matches
                FROM   information_schema.partitions) A
        WHERE   matches>0
        UNION
        SELECT DISTINCT 
               index_schema,
               index_name,
               NULL,
               'INDEX',
               NULL,
               NULL,
               upper(concat(index_schema, '.', index_name)),
               'information_schema.statistics'
        FROM   information_schema.statistics
        WHERE  INDEX_NAME != 'PRIMARY'
        AND    upper(concat(index_schema, '.', index_name)) LIKE @target
        UNION
        SELECT routine_schema,
               routine_name,
               null,
               routine_type,
               created,
               last_altered,
               upper(concat(routine_schema, '.', routine_name)),
               'information_schema.routines'
        FROM   information_schema.routines
        WHERE  upper(concat(routine_schema, '.', routine_name)) LIKE @target
        UNION
        SELECT trigger_schema,
               event_object_table,
               trigger_name COLLATE &DEFAULT_COLLATION,
               'TRIGGER',
               created,
               NULL,
               upper(concat(trigger_schema, '.', trigger_name)),
               'information_schema.triggers'
        FROM   information_schema.triggers
        WHERE  upper(concat(trigger_schema, '.', trigger_name)) LIKE @target) AS M
WHERE &FILTER
ORDER BY CASE WHEN `Schema`=database() THEN 0 ELSE 1 END,1,2
limit 100;
