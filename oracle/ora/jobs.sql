/*[[
    show schedule job information. Usage: @@NAME [<schema>|all] [-e|-f"<filter>"]
    Options:
        -e: list the failure job history
        -f: customized the filter on the job history. i.e.: -f"job_name like 'ABCD%'"
    --[[
        @check_access_dba: dba_scheduler_jobs={dba},default={all}
        &filter: default={1=1} ,f={}, e={STATUS!='SUCCEEDED'} 
    --]]
]]*/
set feed off

pro Active jobs:
PRO ============
select owner,job_name,RUN_COUNT,FAILURE_COUNT,enabled,state,START_DATE+0 START_DATE,0+NEXT_RUN_DATE NEXT_RUN_DATE,0+LAST_START_DATE LAST_RUN_DATE,LAST_RUN_DURATION LAST_DURATION,REPEAT_INTERVAL,schedule_type,SCHEDULE_NAME,JOB_CLASS,JOB_TYPE,JOB_ACTION
from &check_access_dba._scheduler_jobs 
where (owner=nvl(upper(:V1),sys_context('userenv','current_schema')) or upper(:V1)='ALL')
and   (nvl(NEXT_RUN_DATE,date'4000-1-1') != date'4000-1-1' or state='RUNNING');

pro Running jobs:
pro =================
select * from &check_access_dba._scheduler_running_jobs 
where (owner=nvl(upper(:V1),sys_context('userenv','current_schema')) or upper(:V1)='ALL');

pro Recent 50 historical jobs:
pro ==========================
select * from(
    select /*+no_expand*/ * from &check_access_dba._scheduler_job_run_details 
    where (owner=nvl(upper(:V1),sys_context('userenv','current_schema')) or upper(:V1)='ALL')
    and   (&filter)
    order by 2 desc)
where rownum<=50;