/*[[show schedule job information. Usage: jobs [schema]
    --[[
        @check_access_dba: dba_scheduler_jobs={dba},default={all}
    --]]
]]*/
set feed off

pro Active jobs:
PRO ============
select owner,job_name,RUN_COUNT,FAILURE_COUNT,enabled,state,START_DATE+0 START_DATE,0+NEXT_RUN_DATE NEXT_RUN_DATE,0+LAST_START_DATE LAST_RUN_DATE,LAST_RUN_DURATION LAST_DURATION,REPEAT_INTERVAL,schedule_type,SCHEDULE_NAME,JOB_CLASS,JOB_TYPE,JOB_ACTION
from &check_access_dba._scheduler_jobs 
where owner=nvl(:V1,sys_context('userenv','current_schema'))
and   (nvl(NEXT_RUN_DATE,date'4000-1-1') != date'4000-1-1' or state='RUNNING');

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