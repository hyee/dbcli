/*[[Search objects with the specific keywork. Usage: @@NAME <keyword>
    --[[--

    --]]--
]]*/

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
WHERE  lower(concat(nspname, '.', relname)) LIKE lower('%&V1%')
UNION ALL
SELECT routine_schema, routine_name, routine_type
FROM   information_schema.routines
WHERE  lower(concat(routine_schema, '.', routine_name)) LIKE lower('%&V1%')
UNION ALL
SELECT trigger_schema, trigger_name, 'TRIGGER'
FROM   information_schema.triggers
WHERE  lower(concat(trigger_schema, '.', trigger_name)) LIKE lower('%&V1%')