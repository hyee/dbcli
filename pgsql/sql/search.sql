/*[[Search objects with the specific keywork. Usage: @@NAME <keyword>
    --[[--

    --]]--
]]*/
SELECT * FROM (
    SELECT nspname "SCHEMA",
            relname "NAME",
            CASE TRIM(tbl.relkind)
                WHEN 'r' THEN
                'TABLE'
                WHEN 'p' THEN
                'PARTITIONED TABLE'
                WHEN 'f' THEN
                'FOREIGN TABLE'
                WHEN 't' THEN
                'TOAST TABLE'
                WHEN 'm' THEN
                'MATERIALZED VIEW'
                WHEN 'v' THEN
                'VIEW'
                WHEN 'i' THEN
                'INDEX'
                WHEN 'I' THEN
                'PARTITIONED INDEX'
                WHEN 'S' THEN
                'SEQUENCE'
                WHEN 'c' THEN
                    'COMPOSITE TYPE'
            END "TYPE"
    FROM   pg_class tbl
    JOIN   pg_namespace nsp ON nsp.oid = tbl.relnamespace
    UNION ALL
    SELECT routine_schema, routine_name, routine_type
    FROM   information_schema.routines
    UNION ALL
    SELECT trigger_schema, trigger_name, 'TRIGGER'
    FROM   information_schema.triggers) a
WHERE lower(concat("SCHEMA",'.',"NAME",'|',"TYPE")) LIKE lower('%&V1%')
ORDER BY 1,2