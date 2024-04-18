SELECT nspname,tbl.relname,conname, pg_get_constraintdef(con.oid, true) as "definition"
FROM   pg_constraint con
JOIN   pg_namespace nsp ON nsp.oid = con.connamespace
LEFT JOIN   pg_class tbl ON tbl.oid=con.conrelid
WHERE  nspname=:object_owner
AND    conname=:object_name;