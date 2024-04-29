/*[[Search top 100 objects with the specific keywork. Usage: @@NAME [<keyword>|-f"<filter>"]
    --[[--
        &filter: default={lower(concat(oid,'|',schemaname,'.',objectname,'|',objecttype)) LIKE lower('%&V1%')} f={}
    --]]--
]]*/
SELECT * FROM (
    SELECT  tbl.oid,
            nspname schemaname,
            relname objectname,
            CASE TRIM(tbl.relkind)
                WHEN 'r' THEN 'TABLE'
                WHEN 'c' THEN 'TYPE'  
                WHEN 'p' THEN 'PARTITIONED TABLE'
                WHEN 'f' THEN 'FOREIGN TABLE'
                WHEN 't' THEN 'TOAST TABLE'
                WHEN 'm' THEN 'MATERIALZED VIEW'
                WHEN 'v' THEN 'VIEW'
                WHEN 'i' THEN 'INDEX'
                WHEN 'I' THEN 'PARTITIONED INDEX'
                WHEN 'L' THEN 'SEQUENCE' 
                WHEN 'S' THEN 'SEQUENCE'
            END objecttype,
            pg_get_userbyid(tbl.relowner) "owner",
            pg_has_role(tbl.relowner, 'USAGE'::text) "Usage",
            has_table_privilege(tbl.oid, 'SELECT'::text) "Priv"
    FROM   pg_class tbl
    JOIN   pg_namespace nsp ON nsp.oid = tbl.relnamespace
    UNION ALL
    SELECT P.oid,n.nspname,p.proname,'FUNCTION',pg_get_userbyid(p.proowner),pg_has_role(p.proowner, 'USAGE'::text) "Usage",has_function_privilege(p.oid, 'EXECUTE'::text) "Priv"
    FROM pg_namespace n,
         pg_proc p
    WHERE n.oid = p.pronamespace
    UNION ALL
    SELECT t.oid,nspname "SCHEMA",t.tgname,'TRIGGER',pg_get_userbyid(c.relowner),pg_has_role(c.relowner, 'USAGE'::text) "Usage",has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'::text)
    FROM pg_namespace n,
         pg_class c,
         pg_trigger t
    WHERE n.oid = c.relnamespace AND c.oid = t.tgrelid
    UNION ALL
    SELECT r.oid,n.nspname,
           r.rulename,'RULE',
           pg_get_userbyid(c.relnamespace),
           NULL,NULL
    FROM pg_rewrite r
    JOIN pg_class c ON c.oid = r.ev_class
    LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE r.rulename <> '_RETURN'::name) a
WHERE &filter
ORDER BY 2,3 LIMIT 100