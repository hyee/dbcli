/*[[Show bloat information for table/index. Usage: @@NAME {[[schema.]<table>] | [<bloat_mb>]} 
    Refs: https://github.com/francs/PostgreSQL-healthcheck-script/blob/master/pg_healthcheck_v1.2.sh
    --[[
        &table: default={'&object_name'='' or } table={}
    ]]--
]]*/

findobj "&V1" 1 1
env feed off
col bloat for pct2
col pages,rows,b-pages,live_rows,dead_rows for tmb2
col size,b-bytes for kmg2 
echo Bloat information:
echo ==================
WITH bloats as(
    SELECT tid,toid,c2.reltablespace iid,c2.oid ioid,
           nn.nspname AS schema_name,
           cc.relname AS table_name,
           COALESCE(cc.reltuples,0) AS reltuples,
           COALESCE(cc.relpages,0) AS relpages,
           bs,
           COALESCE(CEIL((cc.reltuples*((datahdr+ma-(CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)),0) AS otta,
           COALESCE(c2.relname,'?') AS index_name, 
           COALESCE(c2.reltuples,0) AS ituples, 
           COALESCE(c2.relpages,0) AS ipages,
           COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
    FROM   pg_class cc
    JOIN   pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname <> 'information_schema'
    LEFT JOIN
    (
        SELECT tid,toid,
               ma,foo.nspname,foo.relname,bs,
               (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
               (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
        FROM (
            SELECT tbl.reltablespace  tid,tbl.oid toid,
                ns.nspname, tbl.relname, hdr, ma,
                COALESCE(pg_table_size(tbl.oid) /nullif(tbl.relpages,0),current_setting('block_size')::bigint) bs,
                SUM((1-coalesce(null_frac,0))*coalesce(avg_width, 2048)) AS datawidth,
                MAX(coalesce(null_frac,0)) AS maxfracsum,
                hdr+(
                    SELECT 1+count(*)/8
                    FROM pg_stats s2
                    WHERE null_frac<>0 AND s2.schemaname = ns.nspname AND s2.tablename = tbl.relname
                ) AS nullhdr
            FROM pg_attribute att 
            JOIN pg_class tbl ON att.attrelid = tbl.oid
            JOIN pg_namespace ns ON ns.oid = tbl.relnamespace 
            LEFT JOIN pg_stats s ON s.schemaname=ns.nspname
            AND s.tablename = tbl.relname
            AND s.inherited=false
            AND s.attname=att.attname,
            (
                SELECT CASE WHEN SUBSTRING(SPLIT_PART(v, ' ', 2) FROM '#"[0-9]+.[0-9]+#"%' for '#')
                         IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
                       CASE WHEN v ~ 'mingw32' OR v ~ '64-bit' THEN 8 ELSE 4 END AS ma
                FROM (SELECT version() AS v) AS foo
            ) AS constants
            WHERE att.attnum > 0 AND tbl.relkind='r'
            AND   (&table '&object_type' LIKE '%TABLE' and tbl.relname='&object_name' and ns.nspname='&object_owner')
            GROUP BY 1,2,3,4,5,6,7
            ) AS foo
    ) AS rs
    ON cc.relname = rs.relname AND nn.nspname = rs.nspname
    LEFT JOIN pg_index i ON indrelid = cc.oid
    LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
    WHERE (&table CC.relname='&object_name' and nn.nspname='&object_owner')
),
default_tbs as(
    SELECT t.spcname
    FROM   pg_database d, pg_tablespace t
    WHERE  d.dattablespace = t.oid
    AND    d.datname = current_database()
)
SELECT a.*,'|' "|", b.n_live_tup live_rows,n_dead_tup dead_rows
FROM 
(
    SELECT DISTINCT
           toid oid,
           schema_name, 
           table_name object_name,
           'TABLE' "type",
           coalesce(t.spcname,(select spcname from default_tbs)) "tablespace", 
           reltuples::bigint AS "rows", 
           relpages::bigint AS "pages", 
           bs*relpages "size",
           '|' "|",
           ROUND(CASE WHEN otta=0 OR relpages=0 OR relpages=otta THEN 0.0 ELSE relpages/otta::numeric END-1,4) AS "bloat",
           CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS "b-pages",
           CASE WHEN relpages < otta THEN 0 ELSE bs*(relpages-otta)::bigint END AS "b-bytes"
    FROM bloats b
    LEFT JOIN pg_tablespace  t ON b.tid=t.oid
    UNION ALL
    SELECT ioid,
           schema_name , 
           index_name ,
           'INDEX' object_type,
           coalesce(t.spcname,(select spcname from default_tbs)), 
           ituples::bigint AS itups,
           ipages::bigint AS ipages,
           bs*ipages "size",
           '|' "|",
           ROUND(greatest(0,CASE WHEN iotta=0 OR ipages=0 OR ipages=iotta THEN 0.0 ELSE ipages/iotta::numeric END-1),4) AS ibloat,
           CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS "b-pages",
           CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS "b-bytes"
    FROM bloats b
    LEFT JOIN pg_tablespace  t ON b.iid=t.oid
) AS A
LEFT JOIN pg_stat_all_tables B ON a.schema_name=b.schemaname and a.object_name=b.relname
WHERE '&object_name' !='' OR "b-bytes">(coalesce(nullif(regexp_replace('&V1'::text,'[^\.\d]+'::text,'','g'),''),'1')::numeric * 1024 * 1024)
ORDER BY "b-bytes" desc,"bloat" desc
LIMIT 50;