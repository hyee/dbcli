/*[[show schedule job information. Usage: jobs [schema]
    --[[
        @check_access_dba: dba_scheduler_jobs={dba},default={all}
    --]]
]]*/
set feed off

pro Avail jobs:
PRO ============
select * from &check_access_dba._scheduler_jobs 
where owner=nvl(:V1,sys_context('userenv','current_schema'));

pro Running jobs:
pro =================
select * from &check_access_dba._scheduler_running_jobs 
where owner=nvl(:V1,sys_context('userenv','current_schema'));

pro Recent 50 historical jobs:
pro ==========================
select * from(
    select * from &check_access_dba._scheduler_job_run_details 
    where owner=nvl(:V1,sys_context('userenv','current_schema'))
    order by 2 desc)
where rownum<=50;