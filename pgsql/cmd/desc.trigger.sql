SELECT * 
FROM   information_schema.triggers
WHERE  trigger_schema=:object_owner
AND    trigger_name=:object_name\G