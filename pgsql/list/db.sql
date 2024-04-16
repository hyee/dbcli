/*[[Show databases
    --[[
        @CHECK_USER_GAUSS: gaussdb={datcompatibility "Compatibility",} default={}
    --]]
]]*/
col size for kmg2
SELECT p.datid "dbid",
       case when current_database()=p.datname then '* ' else '  ' end||p.datname "database_name",
       pg_database_size(d.oid) "size",
       o.rolname "owner",
       t.spcname "tablespace",
       pg_encoding_to_char(encoding) "encoding",
       d.datcollate "Collate",
       d.datctype "Ctype",
       d.datallowconn "Allow-Conn",
       d.datconnlimit, &CHECK_USER_GAUSS
       datacl
FROM   pg_stat_database p, pg_database d, pg_authid o, pg_tablespace t
WHERE  p.datid = d.oid
AND    d.datdba = o.oid
AND    d.dattablespace = t.oid
AND    d.datistemplate = FALSE
ORDER  BY p.datid;
