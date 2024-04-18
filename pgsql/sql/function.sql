/*[[Find SQL functions with the specific keyword. Usage: @@NAME <keyword>|f"<filter>"
    --[[
        @ARGS: 1
        @ALIAS: fn
        &filter: default={lower(concat(n.nspname,'.',p.proname,'|',p.probin,'|',d.description)) like lower('%&V1%')} f={}
    --]]
]]*/

SELECT p.oid,
       au.rolname AS "owner",
       n.nspname AS schema_name,
       p.proname AS function_name,
       l.lanname AS "lang",
       CASE WHEN p.proretset AND 'o'=ANY(proargmodes) THEN
           (SELECT string_agg(CASE WHEN a NOT LIKE 'OUT%' THEN substr(a,5) END,',') x
            FROM   unnest(string_to_array(pg_get_function_identity_arguments(p.oid),', ')) as a)
       ELSE pg_get_function_identity_arguments(p.oid) END AS "args",
       CASE WHEN p.proretset AND 'o'=ANY(proargmodes) THEN
           (SELECT concat('{',string_agg(CASE WHEN a LIKE 'OUT%' THEN substr(a,5) END,','),'}') x
            FROM   unnest(string_to_array(pg_get_function_identity_arguments(p.oid),', ')) as a)
       ELSE 
           CASE WHEN p.proretset THEN 'SET OF ' ELSE '' END || pg_typeof(p.prorettype)::text
       END AS "returns",
       CASE p.provolatile
           WHEN 'i' THEN
            'IMMUTABLE'
           WHEN 's' THEN
            'STABLE'
           WHEN 'v' THEN
            'VOLATILE'
       END AS volatility,
       RTRIM(CONCAT(
           CASE WHEN p.proisstrict THEN 'STRICT,' END,
           CASE WHEN p.proisagg THEN 'AGG,' END,
           CASE WHEN p.proiswindow THEN 'WINDOW,' END ,
           CASE WHEN p.prosecdef THEN 'SEC-DEF,' END,
           CASE WHEN p.proretset THEN 'RET-SET,' END),',') AS attrs,
       probin "Binary",
       d.description AS function_description
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
JOIN   pg_authid au ON p.proowner = au.oid
LEFT   JOIN pg_description d ON d.objoid = p.oid AND d.objsubid = 0
LEFT   JOIN pg_language l ON l.oid = p.prolang
WHERE  &filter
ORDER  BY schema_name,function_name,p.oid;
