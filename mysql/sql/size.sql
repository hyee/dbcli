/*[[Show table space usages. @@NAME [<schema> | -u | -f"<filter>" 
    -f"<filter>": Customize the `WHERE` clause
    -u          : Only list the SQLs for current database
    --[[--
            &filter: {
                default={:V1 IS NULL OR lower(table_schema)=lower(:V1)}
                f={}
                u={table_schema=database()}
            }
            @check_user_tidb: tidb={,Tidb_Pk_Type} default={}
    --]]--
]]*/
COL size,table_size,index_size,free_size for kmg2
COL of_schema for pct2
COL table_rows for tmb2
ENV headstyle initcap

SELECT table_schema, 
       table_name,
       COUNT(DISTINCT COALESCE(subpartition_name,partition_name,table_name)) segments,
       -- COUNT(DISTINCT index_name) indexes,
       SUM(data_length + index_length + IFNULL(data_free,0)) size, 
       ROUND(SUM(data_length + index_length + IFNULL(data_free,0))/IFNULL(MAX(schema_size),0),4) of_schema,
       SUM(data_length) table_size, 
       SUM(index_length) index_size,
       SUM(data_free)    free_size,
       SUM(table_rows)   table_rows,
       AVG(NULLIF(avg_row_length,0)) avg_row_length,
       engine &check_user_tidb,
       IFNULL(GROUP_CONCAT(DISTINCT tablespace_name SEPARATOR ', '),'') tablespaces,
       any_value(collation) collation
FROM   information_schema.partitions t
JOIN   (SELECT table_schema,
               SUM(data_length + index_length + IFNULL(data_free,0)) schema_size
        FROM   information_schema.tables
        GROUP  BY table_schema) c
USING  (table_schema)
JOIN   (SELECT table_schema,table_name,engine,table_collation collation &check_user_tidb from information_schema.tables) t1
USING  (table_schema,table_name)
WHERE  (&filter)
GROUP  BY table_schema, table_name,engine &check_user_tidb
HAVING SUM(data_length)>0 AND SUM(table_rows)>0
ORDER  BY size DESC LIMIT 100;
