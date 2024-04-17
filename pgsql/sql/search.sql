/*[[Search objects with the specific keywork. Usage: @@NAME <keyword>
    --[[--

    --]]--
]]*/
SELECT * FROM (
    SELECT  tbl.oid,
            nspname "SCHEMA",
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
            END "TYPE",
            au.rolname "owner",
            pg_has_role(au.oid, 'USAGE'::text) "Usage",
            null::boolean "Priv"
    FROM   pg_class tbl
    JOIN   pg_namespace nsp ON nsp.oid = tbl.relnamespace
    JOIN   pg_authid au on au.oid=tbl.relowner
    UNION ALL
    SELECT P.oid,n.nspname,p.proname,'FUNCTION',au.rolname,pg_has_role(au.oid, 'USAGE'::text) "Usage",has_function_privilege(p.oid, 'EXECUTE'::text) "Priv"
    FROM pg_namespace n,
         pg_proc p,
         pg_authid au
    WHERE n.oid = p.pronamespace AND p.proowner = au.oid
    UNION ALL
    SELECT t.oid,nspname "SCHEMA",t.tgname,'TRIGGER',au.rolname,pg_has_role(au.oid, 'USAGE'::text) "Usage",has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'::text)
    FROM pg_namespace n,
         pg_class c,
         pg_trigger t,
         pg_authid au
    WHERE n.oid = c.relnamespace AND c.oid = t.tgrelid AND au.oid=c.relowner) a
WHERE lower(concat("SCHEMA",'.',"NAME",'|',"TYPE")) LIKE lower('%&V1%')
ORDER BY 2,3