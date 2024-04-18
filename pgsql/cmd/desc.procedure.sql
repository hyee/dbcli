col Owner,Schema_Name,Function_Name noprint
echo attributes:
echo ==========
sql fn "&object_owner..&object_name"

echo information_schema.routines:
echo ============================
SELECT * 
FROM   information_schema.routines
WHERE  routine_schema=:object_owner
AND    routine_name=:object_name\G