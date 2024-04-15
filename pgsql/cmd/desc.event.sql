SELECT * 
FROM   information_schema.events
WHERE  event_schema=:object_owner
AND    event_name=:object_name\G