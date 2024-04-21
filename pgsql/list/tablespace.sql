/*[[Show tablespace info
    --[[
        @ALIAS: tbs
    --]]
]]*/
col size for kmg2
select oid,
       t.*,
       pg_tablespace_size(oid) "size",
       has_tablespace_privilege(oid,'CREATE') "granted",
       pg_tablespace_location(oid) "location",
       (select string_agg(datname,e',\n') 
        from pg_database 
        where oid in(select * from pg_tablespace_databases(t.oid))) "databases"
from   pg_tablespace t