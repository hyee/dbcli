/*[[Check table/routine/mview/etc privileges. Usage: @@NAME [<owner>.]<name>
    --[[
        @ARGS: 1
    ]]
]]*/

findobj "&V1" 1 1

ECHO &object_type &object_fullname
ECHO ===================================
SELECT pg_get_userbyid(c.grantor) AS grantor,
       pg_get_userbyid(c.grantee) AS grantee,
       nc.nspname object_schema,
       c.relname object_name,
       c.prtype privilege_type,
       pg_has_role(c.relowner, 'USAGE'::text) "MyUsage",
       CASE c.grp 
           WHEN '_' THEN has_function_privilege(c.oid,c.prtype) 
           WHEN 's' THEN has_sequence_privilege(c.oid,c.prtype)
           WHEN 'c' THEN has_type_privilege(c.oid,c.prtype)
           ELSE has_table_privilege(c.oid,c.prtype)
       END "MyPriv",
       CASE
           WHEN pg_has_role(c.grantee, c.relowner, 'USAGE'::text) OR c.grantable THEN
            'YES'::text
           ELSE
            'NO'::text
       END::information_schema.yes_or_no AS is_grantable,
       CASE
           WHEN c.prtype = 'SELECT'::text THEN
            'YES'::text
           ELSE
            'NO'::text
       END::information_schema.yes_or_no AS with_hierarchy
FROM   (SELECT relkind grp,
               pg_class.oid,
               pg_class.relname,
               pg_class.relowner,
               pg_class.relnamespace,
               (aclexplode(COALESCE(pg_class.relacl, acldefault('r'::"char", pg_class.relowner)))).grantor                     AS grantor,
               (aclexplode(COALESCE(pg_class.relacl, acldefault('r'::"char", pg_class.relowner)))).grantee                     AS grantee,
               (aclexplode(COALESCE(pg_class.relacl, acldefault('r'::"char", pg_class.relowner)))).privilege_type              AS privilege_type,
               (aclexplode(COALESCE(pg_class.relacl, acldefault('r'::"char", pg_class.relowner)))).is_grantable                AS is_grantable
        FROM   pg_class
        WHERE  pg_class.oid=:object_id::bigint
        AND    pg_class.relname !~~ 'mlog\_%'::text
        AND    pg_class.relname !~~ 'matviewmap\_%'::text
        UNION ALL
        SELECT '_',
               pg_proc.oid,
               pg_proc.proname,
               pg_proc.proowner,
               pg_proc.pronamespace,
               (aclexplode(COALESCE(pg_proc.proacl, acldefault('f'::"char", pg_proc.proowner)))).grantor                    AS grantor,
               (aclexplode(COALESCE(pg_proc.proacl, acldefault('f'::"char", pg_proc.proowner)))).grantee                    AS grantee,
               (aclexplode(COALESCE(pg_proc.proacl, acldefault('f'::"char", pg_proc.proowner)))).privilege_type             AS privilege_type,
               (aclexplode(COALESCE(pg_proc.proacl, acldefault('f'::"char", pg_proc.proowner)))).is_grantable               AS is_grantable
        FROM   pg_proc
        WHERE  pg_proc.oid=:object_id::bigint) c(grp,OID, relname,  relowner, relnamespace, grantor, grantee, prtype, grantable),
       pg_namespace nc
WHERE  c.relnamespace = nc.oid
AND   (c.grp!='_' AND c.prtype = ANY(ARRAY['INSERT', 'SELECT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) OR 
       c.grp ='_' AND c.prtype = ANY(ARRAY['EXECUTE', 'ALTER', 'DROP', 'COMMENT']))

