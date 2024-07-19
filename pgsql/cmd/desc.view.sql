COL VIEW_DEFINITION NOPRINT
COL "Null%" for pct
COL table_name noprint

SELECT obj_description(:object_fullname::regclass);

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
       case att.attstorage
          when 'p' then 'plain'
          when 'm' then 'main'
          when 'e' then 'external'
          when 'x' then 'extended'
       end as "Storage",
       pg_catalog.col_description(format('%s.%s',table_schema,table_name)::regclass::oid,ordinal_position) as "description"
FROM   (select a.*,case when column_default like 'nextval(%'||table_name||'_'||column_name||'_seq%)' then true else false end is_serial 
        from   information_schema.columns a
        WHERE  table_schema=:object_owner
        AND    table_name=:object_name) a
LEFT   JOIN pg_stats s 
ON     a.column_name=s.attname
AND    s.schemaname= :object_owner
AND    s.tablename=:object_name
LEFT   JOIN pg_attribute att
ON     att.attrelid=:object_id::int
AND    a.column_name=att.attname
ORDER  BY 1;

SELECT t.tgname DEP_NAME,'TRIGGER' "type",
        rtrim(concat(
            CASE tgenabled WHEN 'D' THEN 'DISABLE,' WHEN 'A' THEN 'ALWAYS,' WHEN 'R' THEN 'REPLICA,' ELSE 'ENABLE,' END,
            CASE WHEN tgdeferrable   THEN 'DEFERRABLE,' END, 
            CASE WHEN tginitdeferred THEN 'INITIALLY DEFERRABLE' END
        ),',')::text "status",
        concat(
            CASE t.tgtype::integer & 66
                WHEN 2 THEN 'BEFORE '::text
                WHEN 64 THEN 'INSTEAD OF '::text
                ELSE 'AFTER '::text
            END,
            CASE WHEN t.tgtype::integer & 4 >0 THEN 
                'INSERT' || CASE WHEN t.tgtype::integer & 24 >0 THEN  ' OR ' ELSE '' END
            END,
            CASE WHEN t.tgtype::integer & 8 >0 THEN 
                'DELETE' || CASE WHEN t.tgtype::integer & 16 >0 THEN  ' OR ' ELSE '' END
            END,
            CASE WHEN t.tgtype::integer & 16 >0 THEN 'UPDATE ' END,
            (
                SELECT 'OF '||nullif(string_agg(a.attname,','),'')||' ' cols
                FROM   (
                    SELECT ta0.tgoid,(ta0.tgat).x AS tgattnum,(ta0.tgat).n AS tgattpos
                    FROM   (SELECT pg_trigger.oid AS tgoid, information_schema._pg_expandarray(pg_trigger.tgattr) AS tgat FROM pg_trigger) ta0) ta,
                pg_attribute a
                WHERE  t.oid = ta.tgoid
                AND    a.attrelid = t.tgrelid AND a.attnum = ta.tgattnum
            ),
            CASE WHEN t.tgtype::integer & 32 >0 THEN 'TRUNCATE ' END, 
            CASE t.tgtype::integer & 1 WHEN 1 THEN 'FOR EACH ROW' END
        ) "definition"
FROM   pg_trigger t
JOIN   pg_class tbl
ON     t.tgrelid=tbl.oid
JOIN   pg_namespace n
ON     tbl.relnamespace=n.oid
WHERE  n.nspname=:object_owner
AND    tbl.relname=:object_name
AND    NOT t.tgisinternal
UNION ALL
SELECT r.rulename,'RULE',
       rtrim(concat(
            CASE r.ev_enabled WHEN 'D' THEN 'DISABLE,' WHEN 'A' THEN 'ALWAYS,' WHEN 'R' THEN 'REPLICA,' ELSE 'ENABLE,' END,
            CASE WHEN r.is_instead THEN 'INSTEAD' END),','),
       pg_get_ruledef(r.oid)
FROM   pg_rewrite r
JOIN   pg_class c ON c.oid = r.ev_class
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname=:object_owner
AND    c.relname=:object_name
AND    r.rulename <> '_RETURN'::name;

ENV COLSEP DEFAULT
SELECT * 
FROM   information_schema.views
WHERE  table_schema=:object_owner
AND    table_name=:object_name\G;