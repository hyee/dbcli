SELECT "definition"
FROM   pg_rules
WHERE  schemaname=:object_owner
AND    rulename=:object_name;