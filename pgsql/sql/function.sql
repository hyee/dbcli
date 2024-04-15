/*[[Find SQL functions with the specific keyword. Usage: @@NAME <keyword>
    --[[
        @ARGS: 1
        @ALIAS: fn
    --]]
]]*/

SELECT p.oid,
       n.nspname AS schema_name,
       p.proname AS function_name,
       CASE
           WHEN p.proretset THEN
            'SET OF '
           ELSE
            ''
       END || pg_typeof(p.prorettype)::text AS return_type,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner,
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
       d.description AS function_description
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
LEFT   JOIN pg_description d ON d.objoid = p.oid
AND    d.objsubid = 0
WHERE  lower(concat(p.proname,'|',d.description)) like lower('%&V1%')
ORDER  BY 2,3;
