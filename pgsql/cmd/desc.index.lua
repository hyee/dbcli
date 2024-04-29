env.var.define_column("Size,DATA_LENGTH,DATA_FREE,INDEX_LENGTH","for","KMG2")
env.var.define_column("reads,scans,fetchs","for","TMB1")
return (([[
SELECT i.indexrelid oid,
       CONCAT(nsp.nspname,'.',tbl.relname) "table_name",
       CONCAT(CASE WHEN isp.nspname != nsp.nspname THEN CONCAT(isp.nspname,'.') END,idx.relname) AS index_name,
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
       p.part_by, p."partitions",  
       pg_relation_size(i.indexrelid) "size",
       s.idx_scan scans,
       s.idx_tup_read reads,
       s.idx_tup_fetch fetchs,
       (SELECT string_agg(a.attname, CHR(10))
        FROM   (SELECT UNNEST(i.indkey) AS attnum) AS keys
        JOIN   pg_attribute a
        ON     a.attrelid = tbl.oid
        AND    a.attnum = keys.attnum) AS columns,
       (SELECT string_agg(CASE WHEN attnum & 1 = 1 THEN 'DESC' ELSE 'ASC' END, CHR(10))
        FROM   UNNEST(i.indoption) AS attnum) AS dirs,
       pg_get_expr(i.indpred, i.indrelid) AS predicates
FROM   pg_class tbl
JOIN   pg_namespace nsp         ON nsp.oid = tbl.relnamespace
JOIN   pg_index i               ON i.indrelid = tbl.oid
JOIN   pg_class idx             ON idx.oid = i.indexrelid
JOIN   pg_am am                 ON am.oid = idx.relam
JOIN   pg_namespace isp         ON isp.oid = idx.relnamespace
LEFT   JOIN pg_stat_all_indexes S ON s.indexrelid=i.indexrelid
LEFT   JOIN (@index_partition_info) p ON p.parentid=idx.oid
WHERE  isp.nspname= :object_owner
AND    idx.relname= :object_name
ORDER BY index_name]]):gsub('@index_partition_info',
db.props.gaussdb and [[
   SELECT parentid,
          COUNT(1) "partitions",
          MAX(CASE partstrategy 
              WHEN 'r' THEN 'RANGE'
              WHEN 'v' THEN 'NUMERIC'
              WHEN 'i' THEN 'INTERVAL'
              WHEN 'l' THEN 'LIST'
              WHEN 'h' THEN 'HASH'
              WHEN 'n' THEN 'INVALID'
          END) part_by
   FROM pg_partition
   WHERE parttype='x'
   GROUP BY parentid
]] or 'SELECT null::integer parentid,null::text part_by,null::int "partitions"'))