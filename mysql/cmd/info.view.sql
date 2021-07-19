COL VIEW_DEFINITION NOPRINT
ENV COLSEP |
print Columns:
print ========
SELECT ordinal_position `#`,
       concat(' ',column_name) `Field`,
       CASE WHEN column_type LIKE 'enum%' AND LENGTH(column_type)>50 THEN 
            REPLACE(column_type,',',',\n     ')
       WHEN column_type LIKE 'set%' AND LENGTH(column_type)>50 THEN
            REPLACE(column_type,',',',\n    ')
       ELSE column_type END `Type`,
       IFNULL(column_default,'') `Default`,
       collation_name `Collation`,
       is_nullable `Null`,
       column_key  `Key`,
       Extra `Extra`,
       privileges `Privs`,
       generation_expression `Expr`,
       column_comment `Comment`
FROM   information_schema.columns
WHERE  table_schema=:object_owner
AND    table_name=:object_name
ORDER  BY 1;

ENV COLSEP DEFAULT
SELECT * 
FROM   information_schema.views
WHERE  table_schema=:object_owner
AND    table_name=:object_name\G;