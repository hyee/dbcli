/*[[Show index info
    --[[
        @check_access_size: {
            mysql.innodb_index_stats={
            CASE WHEN seq_in_index=1 THEN (
                SELECT stat_value * @@innodb_page_size
                FROM   mysql.innodb_index_stats iis
                WHERE  stat_name = 'size'
                AND    iis.index_name=i.index_name
                AND    iis.table_name = i.table_name
                AND    iis.database_name = i.index_schema) 
            ELSE '' END "Size",}
            default={}
        }

        @check_access_ck: {
            information_schema.check_constraints={(select constraint_schema,constraint_name,check_clause from information_schema.check_constraints)}
            default={(SELECT '' constraint_schema,'' constraint_name,'' check_clause)}
        }

        &src1: default={index_} t={table_}
        &src2: default={constraint_} t={table_}
    }
    --]]
 ]]*/

COL "Size,DATA_LENGTH,DATA_FREE,INDEX_LENGTH" for KMG2

SELECT i.indexrelid oid,
       CONCAT(CASE WHEN isp.nspname != nsp.nspname THEN CONCAT(isp.nspname,'.') END,
       idx.relname) AS index_name,
       am.amname AS type,
       RTRIM(CONCAT(
         CASE WHEN indisprimary THEN 'PRIMAY,' WHEN indisunique THEN 'UNIQUE,' END,
         CASE WHEN indisexclusion THEN 'EXCLUSION,' END,
         CASE WHEN indisclustered THEN 'CLUSTER,' END,
         CASE WHEN indcheckxmin THEN 'CHECKXIM,' END,
         CASE WHEN indisreplident THEN 'REPLI,' END,
         CASE WHEN NOT indimmediate THEN 'DEFER,' END,
         CASE WHEN NOT indisvalid THEN 'INVALID,' END,
         CASE WHEN NOT indisready THEN 'UNREADY,' END),',') ATTRS,
       (SELECT string_agg(a.attname, CHR(10))
        FROM   (SELECT UNNEST(i.indkey) AS attnum ORDER BY attnum) AS key_with_order
        JOIN   pg_attribute a
        ON     a.attrelid = tbl.oid
        AND    a.attnum = key_with_order.attnum) AS indexed_columns,
       pg_get_expr(i.indpred, i.indrelid) AS predicate
FROM   pg_class tbl
JOIN   pg_namespace nsp     ON nsp.oid = tbl.relnamespace
JOIN   pg_index i           ON i.indrelid = tbl.oid
JOIN   pg_class idx         ON idx.oid = i.indexrelid
JOIN   pg_am am             ON am.oid = idx.relam
JOIN   pg_namespace isp     ON isp.oid = idx.relnamespace
LEFT JOIN pg_constraint con ON idx.oid=con.conindid
WHERE  nsp.nspname = :object_owner
AND    tbl.relname = :object_name
ORDER BY index_name;

SELECT conname "constraint_name",pg_get_constraintdef(c.oid) AS constraint_def
FROM pg_constraint c
WHERE conrelid = '&&object_fullname'::regclass;