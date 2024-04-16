SELECT pg_get_functiondef(a.oid)||';' "ddl"
FROM   pg_proc a join pg_namespace n ON(a.pronamespace=n.oid)
WHERE  n.nspname=:object_owner
AND    a.proname=:object_name;