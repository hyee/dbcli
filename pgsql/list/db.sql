/*[[Show databases
    --[[
        @CHECK_USER_GAUSS1: gaussdb={datcompatibility "comp",} default={}
        @CHECK_USER_GAUSS2: gaussdb={system_identifier} default={to_timestamp(system_identifier >> 32)}
    --]]
]]*/
col size,temp for kmg2
col reads,hits,temps,commits,rollbacks for tmb2
env feed off
select pg_control_version,
       catalog_version_no,
       &CHECK_USER_GAUSS2 cluster_init,
       pg_control_last_modified
from   pg_control_system();

SELECT p.datid "dbid",
       case when current_database()=p.datname then '* ' else '  ' end||p.datname "database_name",
       pg_database_size(d.oid) "size",
       p.temp_bytes "temp",
       o.rolname "owner",
       t.spcname "tablespace",
       pg_encoding_to_char(encoding) "encoding",
       d.datcollate "Collate",
       d.datctype "Ctype",
       d.datallowconn "Allow-Conn",
       &CHECK_USER_GAUSS1
       d.datconnlimit connlimit, 
       p.numbackends AS conns,
       p.xact_commit AS COMMITs,
       p.xact_rollback AS ROLLBACKs,
       p.blks_read reads,
       p.blks_hit  hits,
       p.temp_files temps,
       p.deadlocks, 
       p.stats_reset,
       d.datacl
FROM   pg_stat_database p, pg_database d, pg_authid o, pg_tablespace t
WHERE  p.datid = d.oid
AND    d.datdba = o.oid
AND    d.dattablespace = t.oid
AND    d.datistemplate = FALSE
ORDER  BY p.datid;
