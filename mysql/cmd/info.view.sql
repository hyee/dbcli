COL VIEW_DEFINITION NOPRINT

print Columns:
print ========
SELECT ordinal_position `#`,
	   column_name `Field`,
	   generation_expression `Expr`,
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
       column_comment `Comment`
FROM   information_schema.columns
WHERE  table_schema=:object_owner
AND    table_name=:object_name
ORDER  BY 1;

SELECT * 
FROM   information_schema.views
WHERE  table_schema=:object_owner
AND    table_name=:object_name\G;