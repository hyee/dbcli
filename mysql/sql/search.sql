/*[[ Search object ]]*/
select * from(
    select table_schema as `Schema`,table_name `Name`, null sub_name,table_type `Type`,create_time,update_time,upper(concat(table_schema,'.',table_name)) sdx
    from information_schema.tables
    where upper(concat(table_schema,'.',table_name)) like UPPER(concat('%',:V1,'%'))
    union
    select table_schema,table_name,partition_name,'PARTITION',create_time,update_time,upper(concat(table_schema,'.',table_name,'.',partition_name))
    from information_schema.partitions
    where upper(concat(table_schema,'.',table_name,'.',partition_name)) like UPPER(concat('%',:V1,'%'))
    union
    select table_schema,table_name,subpartition_name,'SUB-PARTITION',create_time,update_time,upper(concat(table_schema,'.',table_name,'.',subpartition_name))
    from information_schema.partitions
    where upper(concat(table_schema,'.',table_name,'.',subpartition_name)) like UPPER(concat('%',:V1,'%'))
    union
    select trigger_schema,event_object_table,trigger_name,'Trigger',created,null,upper(concat(trigger_schema,'.',trigger_name))
    from information_schema.triggers
    where upper(concat(trigger_schema,'.',trigger_name)) like UPPER(concat('%',:V1,'%'))
    union
    select DB,NAME,null,type,created,modified,upper(concat(db,'.',name))
    from mysql.proc
    where upper(concat(db,'.',name)) like UPPER(concat('%',:V1,'%'))
    union
    select distinct index_schema,table_name,index_name,'INDEX',null,null,upper(concat(index_schema,'.',index_name))
    from information_schema.statistics
    where upper(concat(index_schema,'.',index_name)) like UPPER(concat('%',:V1,'%'))
) AS M WHERE :V1<>'' limit 100;
