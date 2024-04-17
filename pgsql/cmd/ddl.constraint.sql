SELECT format('alter table "%s"."%s" add constraint "%s" %s;',nspname,tbl.relname,conname, pg_get_constraintdef(con.oid, true)) as "DDL"
FROM   pg_constraint con
JOIN   pg_namespace nsp ON nsp.oid = con.connamespace
JOIN   pg_class tbl ON tbl.oid=con.conrelid
WHERE  nspname=:object_owner
AND    conname=:object_name;