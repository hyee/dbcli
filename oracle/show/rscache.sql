/*[[Show result cache report]]*/
set feed off serveroutput on
exec dbms_result_cache.memory_report(true);
pro
select * from gv$result_cache_statistics where inst_id=nvl(:instance,userenv('instance'));