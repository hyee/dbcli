
SELECT pg_get_triggerdef(t.oid, true) as "DDL"
FROM   pg_namespace n,
       pg_class c,
       pg_trigger t
WHERE n.oid = c.relnamespace 
AND   c.oid = t.tgrelid 
AND   nspname=:object_owner
AND   tgname=:object_name;