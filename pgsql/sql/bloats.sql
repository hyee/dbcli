/*[[Show bloat information for table/index. Usage: @@NAME {[[schema.]<table>] | [<bloat_mb>]} 
    Refs: https://github.com/ioguix/pgsql-bloat-estimation
    --[[
        &table  : default={'&object_id'='' or } table={}
        &ixname : default={tblname}  table={tblname}
        &v1: default={0}
    ]]--
]]*/

findobj "&V1" 1 1
env feed off
col dead%,extra%,bloat% for pct2
col pages,rows,live_rows,dead_rows for tmb2
col real,extra,bloat for kmg2 
echo Bloat information:
echo ==================
WITH base_ AS(
    SELECT clz.oid tid,ns.nspname,clz.*
    FROM   pg_class      AS clz
    JOIN   pg_namespace  AS ns  ON ns.oid = clz.relnamespace
    WHERE  relkind IN('r','m','p','i','I')
    AND   (&table clz.oid=:object_id::bigint) 
),
tbls_ AS (
    SELECT base_.*, 
           CASE relkind WHEN 'r' THEN 'TABLE' WHEN 'p' THEN 'PARTITIONED TABLE' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'i' THEN 'INDEX' WHEN 'I' THEN 'PARTITIONED INDEX' END object_type
    FROM   base_
    UNION  ALL
    SELECT clz.oid,ns.nspname,clz.*, 'INHERIT TABLE'
    FROM   base_        
    JOIN   pg_inherits   AS i   ON i.inhparent = base_.tid
    JOIN   pg_class      AS clz ON i.inhrelid = clz.oid
    JOIN   pg_namespace  AS ns  ON ns.oid = clz.relnamespace
    WHERE  base_.relkind IN('r')
    AND    :V1 != '0'
),
ix_ AS (
    SELECT tbls_.*,ns.nspname parent_owner,clz.relname parent_name,clz.oid parent_oid,i.indnatts,i.indkey
    FROM   tbls_
    JOIN   pg_index      AS i   ON i.indexrelid = tbls_.tid
    JOIN   pg_class      AS clz ON i.indrelid = clz.oid
    JOIN   pg_namespace  AS ns  ON ns.oid = clz.relnamespace
    WHERE  tbls_.relkind IN('i','I')
    UNION ALL
    SELECT clz.oid, ns.nspname,clz.*,'INDEX', tbls_.nspname as parent_owner,tbls_.relname as parent_name,tbls_.tid parent_oid,i.indnatts,i.indkey
    FROM   tbls_        
    JOIN   pg_index      AS i   ON i.indrelid = tbls_.tid  
    JOIN   pg_class      AS clz ON i.indexrelid = clz.oid  
    JOIN   pg_namespace  AS ns  ON ns.oid = clz.relnamespace
    WHERE  tbls_.relkind NOT IN('i','I')
    AND    :V1 != '0'
)

SELECT a.*
FROM (
    SELECT tblid oid,
        schemaname,
        tblname "object_name",
        object_type,
        reltuples "rows",
        nullif(pg_stat_get_dead_tuples(tblid)/nullif(reltuples,0),0) "dead%",
        tblpages "pages",
        bs * tblpages AS "real",
        nullif(greatest(0,(tblpages - est_tblpages) * bs),0) AS "extra",
        nullif(greatest(0,(tblpages - est_tblpages) / nullif(tblpages,0)),0) "extra%",
        fillfactor,
        nullif(greatest(0,(tblpages - est_tblpages_ff) * bs),0) "bloat",
        nullif(greatest(0,(tblpages - est_tblpages_ff) / nullif(tblpages,0)),0) "bloat%",
        is_na
    FROM   (SELECT ceil(reltuples / ((bs - page_hdr) / tpl_size)) + ceil(toasttuples / 4) AS est_tblpages,
                ceil(reltuples / ((bs - page_hdr) * fillfactor / (tpl_size * 100))) + ceil(toasttuples / 4) AS est_tblpages_ff,
                s2.*
            FROM   (SELECT (4 + tpl_hdr_size + tpl_data_size + (2 * ma) 
                        - CASE WHEN tpl_hdr_size%ma = 0 THEN ma ELSE tpl_hdr_size%ma END 
                        - CASE WHEN ceil(tpl_data_size)::INT%ma = 0 THEN ma ELSE ceil(tpl_data_size)::INT %ma END
                        ) AS tpl_size,
                        bs - page_hdr AS size_per_block,
                        (heappages + toastpages) AS tblpages,
                        s.*
                    FROM   (SELECT tbl.tid AS tblid,
                                tbl.nspname AS schemaname,
                                tbl.relname AS tblname,
                                tbl.reltuples,
                                tbl.relpages AS heappages,
                                tbl.object_type,
                                coalesce(toast.relpages, 0) AS toastpages,
                                coalesce(toast.reltuples, 0) AS toasttuples,
                                coalesce(substring(array_to_string(tbl.reloptions, ' ') FROM 'fillfactor=([0-9]+)')::SMALLINT,100) AS fillfactor,
                                current_setting('block_size')::NUMERIC AS bs,
                                CASE WHEN version()~'mingw32' OR version()~'64-bit|x86_64|ppc64|ia64|amd64' THEN 8 ELSE 4 END AS ma,
                                24 AS page_hdr,
                                23 + CASE WHEN MAX(coalesce(s.null_frac, 0)) > 0 THEN (7 + COUNT(s.attname)) / 8 ELSE 0::INT END 
                                    + CASE WHEN bool_or(att.attname = 'oid' AND att.attnum < 0) THEN 4 ELSE 0 END AS tpl_hdr_size,
                                SUM((1 - coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 0)) AS tpl_data_size,
                                bool_or(att.atttypid = 'pg_catalog.name'::regtype) OR SUM(CASE WHEN att.attnum > 0 THEN 1 ELSE 0 END) <> COUNT(s.attname) AS is_na
                            FROM   pg_attribute  AS att
                            JOIN   tbls_         AS tbl ON att.attrelid = tbl.tid
                            LEFT   JOIN pg_stats AS s
                            ON     s.schemaname = tbl.nspname
                            AND    s.tablename = tbl.relname
                            AND    s.attname = att.attname
                            LEFT   JOIN pg_class AS toast
                            ON     tbl.reltoastrelid = toast.oid
                            WHERE  NOT att.attisdropped
                            AND    tbl.relkind NOT IN ('i', 'I')
                            GROUP  BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
                            ORDER  BY 2, 3) AS s) AS s2) AS s3
    UNION ALL
    SELECT idxoid,nspname AS schemaname, 
        CASE WHEN upper(idxname) like upper('%'||&ixname ||'%') THEN idxname ELSE tblname||' -> '||idxname END table_index,
        object_type,
        reltuples,null::float,relpages,
        bs*(relpages)::bigint AS real_size,
        nullif(greatest(0,bs*(relpages-est_pages)::bigint),0) AS extra_size,
        nullif(greatest(0,(relpages-est_pages)::float / relpages),0) AS extra_pct,
        fillfactor,
        nullif(greatest(0,CASE WHEN relpages > est_pages_ff THEN bs*(relpages-est_pages_ff) ELSE 0 END),0) AS bloat_size,
        nullif(greatest(0,(relpages-est_pages_ff)::float / relpages),0) AS bloat_pct,
        is_na --is the estimation "Not Applicable" ? If true, do not trust the stats.
    FROM (
        SELECT coalesce(1 + ceil(reltuples/floor((bs-pageopqdata-pagehdr)/(4+nulldatahdrwidth)::float)), 0) AS est_pages, -- ItemIdData size + computed avg size of a tuple (nulldatahdrwidth)
            coalesce(1 + ceil(reltuples/floor((bs-pageopqdata-pagehdr)*fillfactor/(100*(4+nulldatahdrwidth)::float))), 0) AS est_pages_ff,
            rows_hdr_pdg_stats.*
        FROM (
        SELECT rows_data_stats.*,
                ( index_tuple_hdr_bm + maxalign + nulldatawidth + maxalign 
                - CASE -- Add padding to the index tuple header to align on MAXALIGN
                    WHEN index_tuple_hdr_bm%maxalign = 0 THEN maxalign
                    ELSE index_tuple_hdr_bm%maxalign
                    END
                - CASE -- Add padding to the data to align on MAXALIGN
                    WHEN nulldatawidth = 0 THEN 0
                    WHEN nulldatawidth::integer%maxalign = 0 THEN maxalign
                    ELSE nulldatawidth::integer%maxalign
                    END
                )::numeric AS nulldatahdrwidth
        FROM (
            SELECT i.nspname, i.tblname, i.idxname, i.reltuples, i.relpages,i.object_type,
                    i.idxoid, i.fillfactor, 
                    current_setting('block_size')::numeric AS bs,
                    CASE WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64' THEN 8 ELSE 4 END AS maxalign, -- MAXALIGN: 4 on 32bits, 8 on 64bits (and mingw32 ?)
                    24 AS pagehdr, --per page header, fixed size: 20 for 7.X, 24 for others
                    16 AS pageopqdata,--per page btree opaque data
                    /* per tuple header: add IndexAttributeBitMapData if some cols are null-able */
                    CASE WHEN max(coalesce(s.null_frac,0)) = 0
                        THEN 8 -- IndexTupleData size
                        ELSE 8 + (( 32 + 8 - 1 ) / 8) -- IndexTupleData size + IndexAttributeBitMapData size ( max num filed per index + 8 - 1 /8)
                    END AS index_tuple_hdr_bm,
                    /* data len: we remove null values save space using it fractionnal part from stats */
                    sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS nulldatawidth,
                    max( CASE WHEN i.atttypid = 'pg_catalog.name'::regtype THEN 1 ELSE 0 END ) > 0 AS is_na
            FROM (
                SELECT ic.*,
                        a1.attnum, a1.attname, a1.atttypid atttypid,
                        CASE WHEN ic.indkey[ic.attpos] = 0 THEN ic.idxname ELSE ic.tblname END AS attrelname
                FROM (
                    SELECT ci.relname AS idxname, ci.reltuples, ci.relpages, ci.parent_oid AS tbloid,
                            ci.tid AS idxoid,
                            ci.parent_name tblname,ci.parent_owner,ci.nspname,
                            ci.object_type,
                            coalesce(substring(array_to_string(ci.reloptions, ' ') from 'fillfactor=([0-9]+)')::smallint, 90) AS fillfactor,
                            pg_catalog.generate_series(1,ci.indnatts) AS attpos,
                            pg_catalog.string_to_array(pg_catalog.textin(pg_catalog.int2vectorout(ci.indkey)),' ')::int[] AS indkey
                    FROM   ix_ ci
                    WHERE  ci.relam=(SELECT oid FROM pg_am WHERE amname = 'btree')
                    AND    ci.relpages > 0
                    AND    ci.relkind IN('i','I') ) AS ic
                JOIN pg_catalog.pg_attribute a1
                ON   a1.attrelid =  CASE WHEN ic.indkey[ic.attpos] <> 0 THEN ic.tbloid ELSE ic.idxoid END
                AND  a1.attnum   =  CASE WHEN ic.indkey[ic.attpos] <> 0 THEN ic.indkey[ic.attpos] ELSE ic.attpos END
            ) i
            LEFT JOIN pg_catalog.pg_stats s 
            ON   s.schemaname = i.parent_owner
            AND  s.tablename = i.attrelname
            AND  s.attname = i.attname
            GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
        ) AS rows_data_stats
    ) AS rows_hdr_pdg_stats
    ) AS relation_stats) A
WHERE '&object_name' !='' OR "bloat">(coalesce(nullif(regexp_replace('&V1'::text,'[^\.\d]+'::text,'','g'),''),'1')::numeric * 1024 * 1024)
ORDER BY "real" desc limit 100