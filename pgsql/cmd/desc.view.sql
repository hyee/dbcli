COL VIEW_DEFINITION NOPRINT
COL "Null%" for pct
ENV COLSEP |
echo Columns:
echo ========
SELECT ordinal_position "#",
       concat(' ',column_name) "Field",
       concat(
           CASE 
               WHEN data_type='numeric' and numeric_precision IS NULL THEN 'decimal'
               WHEN is_serial and data_type='smallint' then 'smallserial'
               WHEN is_serial and data_type='integer' then 'serial'
               WHEN is_serial and data_type='bigint' then 'bigserial'
               ELSE data_type
           END,
           CASE 
               WHEN character_maximum_length IS NOT NULL THEN concat('(',character_maximum_length,')')
               WHEN data_type='numeric' and numeric_precision IS NOT NULL THEN concat('(',numeric_precision,',',numeric_scale,')')
               WHEN interval_precision IS NOT NULL THEN concat('(',interval_precision,')')
               WHEN datetime_precision IS NOT NULL THEN concat('(',datetime_precision,')')
           END)  "Type",
       case when not is_serial then column_default end "Default",
       collation_name "Collation",
       CASE WHEN is_nullable='YES' then '' ELSE is_nullable END "Null",
       s.avg_width::int AS "len",
       CASE WHEN s.n_distinct<0 THEN ROUND(ABS(100*n_distinct)::numeric,2)::text||'%' ELSE nullif(n_distinct,0)::text END  AS ndv,
       nullif(s.null_frac,0)::numeric AS "null%",
       pg_catalog.col_description(format('%s.%s',table_schema,table_name)::regclass::oid,ordinal_position) as "description"
FROM   (select a.*,case when column_default like 'nextval(%'||table_name||'_'||column_name||'_seq%)' then true else false end is_serial 
        from   information_schema.columns a
        WHERE  table_schema=:object_owner
        AND    table_name=:object_name) a
LEFT   JOIN pg_stats s 
ON     a.column_name=s.attname
AND    s.schemaname= :object_owner
AND    s.tablename=:object_name
ORDER  BY 1;

ENV COLSEP DEFAULT
SELECT * 
FROM   information_schema.views
WHERE  table_schema=:object_owner
AND    table_name=:object_name\G;