SELECT 'CREATE SEQUENCE "' || a.sequence_schema || '"."' || a.sequence_name || '" AS ' || data_type ||
       ' INCREMENT BY ' || a.increment || ' START WITH ' || a.start_value || ' MINVALUE ' || a.minimum_value ||
       ' MAXVALUE ' || a.maximum_value || 
       CASE WHEN a.cycle_option = 'NO' THEN ' NO CYCLE' ELSE ' CYCLE' END 
       --|| CASE WHEN a.cache_size = 1 THEN ' NOCACHE' ELSE ' CACHE ' || cache_size END 
       || ';' "Definition"
FROM   information_schema.sequences a
WHERE  a.sequence_schema=:object_owner
AND    a.sequence_name=:object_name;