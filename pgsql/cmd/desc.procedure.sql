sql fn "&object_name"

SELECT * 
FROM   information_schema.routines
WHERE  routine_schema=:object_owner
AND    routine_name=:object_name\G