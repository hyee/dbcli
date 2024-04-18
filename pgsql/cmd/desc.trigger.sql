col Action_Statement noprint
SELECT a.*,
       (SELECT STRING_AGG(b.event_object_column,',')
        FROM   information_schema.triggered_update_columns b
        WHERE  a.trigger_catalog=b.trigger_catalog
        AND    a.trigger_schema=b.trigger_schema
        AND    a.trigger_name=b.trigger_name) update_of_columns
FROM   information_schema.triggers a
WHERE  trigger_schema=:object_owner
AND    trigger_name=:object_name\G

SELECT regexp_replace(regexp_replace(pg_get_triggerdef(t.oid, true),' (BEFORE|AFTER) ',e'\n\\1 '),' ON ',e'\nON ') as "definition"
FROM   pg_namespace n,
       pg_class c,
       pg_trigger t
WHERE n.oid = c.relnamespace 
AND   c.oid = t.tgrelid 
AND   nspname=:object_owner
AND   tgname=:object_name;