/*[[Show databases]]*/
SELECT p.datid,p.datname,d.encoding,d.datcollate,d.datctype,d.datallowconn,d.datconnlimit
FROM   pg_stat_database p, pg_database d
WHERE  p.datid = d.oid
AND    d.datistemplate = FALSE
ORDER  BY p.datid;
