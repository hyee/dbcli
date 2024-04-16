COL VIEW_DEFINITION NOPRINT
ENV COLSEP |
echo Columns:
echo ========
SELECT ordinal_position "#",
       concat(' ',column_name) "Field",
       concat(
           CASE 
               WHEN data_type='numeric' and numeric_precision IS NULL THEN 'decimal'
           ELSE
               data_type
           END,
           CASE 
               WHEN character_maximum_length IS NOT NULL THEN concat('(',character_maximum_length,')')
               WHEN data_type='numeric' and numeric_precision IS NOT NULL THEN concat('(',numeric_precision,',',numeric_scale,')')
               WHEN interval_precision IS NOT NULL THEN concat('(',interval_precision,')')
               WHEN datetime_precision IS NOT NULL THEN concat('(',datetime_precision,')')
           END)  "Type",
       column_default "Default",
       collation_name "Collation",
       CASE WHEN is_nullable='YES' then '' ELSE is_nullable END "Null",
       pg_catalog.col_description(format('%s.%s',table_schema,table_name)::regclass::oid,ordinal_position) as "description"
FROM   information_schema.columns a
WHERE  table_schema=:object_owner
AND    table_name=:object_name
ORDER  BY 1;

ENV COLSEP DEFAULT
SELECT * 
FROM   information_schema.views
WHERE  table_schema=:object_owner
AND    table_name=:object_name\G;