/*[[Show tablespace info
    --[[
        @ALIAS: tbs
    --]]
]]*/
col size for kmg2
env autohide col
select t.oid,
       t.*,
       pg_tablespace_size(t.oid) "size",
       pg_catalog.pg_get_userbyid(spcowner)  "owner",
       has_tablespace_privilege(t.oid,'CREATE') "granted",
       pg_tablespace_location(t.oid) "location",
       (select string_agg(datname,e',\n') 
        from pg_database 
        where oid in(select * from pg_tablespace_databases(t.oid))
        and   t.spcname!='pg_global') "databases"
from   pg_tablespace t