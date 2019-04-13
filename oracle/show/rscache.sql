/*[[Show result cache report]]*/
set feed off serveroutput on
select * from gv$result_cache_statistics where inst_id=nvl(:instance,userenv('instance'));
exec dbms_result_cache.memory_report(true);