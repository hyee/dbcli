/*[[
show schedule job information. Usage: @@NAME [<schema>|all] [-e|-f"<filter>"]

Options:
    <schema> : Target schema name, defaults to sys_context('userenv','current_schema'). 'ALL' means all schemas.
    -e       : only list the failure job history
    -f       : customized the filter on the job history. i.e.: -f"job_name like 'ABCD%'"

Sample Output:
==============
ORCL> ora jobs
    Active jobs:                                                                                                        
    ============                                                                                                        
    OWNER           JOB_NAME           RUN_COUNT FAILURE_COUNT ENABLED   STATE       START_DATE         NEXT_RUN_DATE   
    ----- ---------------------------- --------- ------------- ------- --------- ------------------- -------------------
    SYS   PURGE_LOG                          186             1 TRUE    SCHEDULED 2011-08-29 03:00:00 2019-04-13 03:00:00
    SYS   ORA$AUTOTASK_CLEAN                 186             0 TRUE    SCHEDULED 2011-08-29 03:00:00 2019-04-13 03:00:00
    SYS   BSLN_MAINTAIN_STATS_JOB             62            12 TRUE    SCHEDULED 2011-09-04          2019-04-14         
    SYS   RSE$CLEAN_RECOVERABLE_SCRIPT       185             0 TRUE    SCHEDULED 2011-08-28 22:17:04 2019-04-13         
    SYS   SM$CLEAN_AUTO_SPLIT_MERGE          185             0 TRUE    SCHEDULED 2011-08-28 22:17:04 2019-04-13         
                                                                                                                        
                                                                                                                        
    Running jobs:                                                                                                       
    =================                                                                                                   
    OWNER JOB_NAME JOB_SUBNAME JOB_STYLE DETACHED SESSION_ID SLAVE_PROCESS_ID SLAVE_OS_PROCESS_ID RUNNING_INSTANCE RESOU
    ----- -------- ----------- --------- -------- ---------- ---------------- ------------------- ---------------- -----
                                                                                                                        
                                                                                                                        
    Recent 50 historical jobs:                                                                                          
    ==========================                                                                                          
    LOG_ID          LOG_DATE           OWNER           JOB_NAME           JOB_SUBNAME  STATUS   ERROR#       REQ_START_D
    ------ --------------------------- ----- ---------------------------- ----------- --------- ------ -----------------
     32770 2019-04-12 09:25:26.174 -04 SYS   PURGE_LOG                                SUCCEEDED      0 2019-04-12 03:00:
     32768 2019-04-12 09:25:25.435 -04 SYS   RSE$CLEAN_RECOVERABLE_SCRIPT             SUCCEEDED      0 2019-04-12 00:00:
     32771 2019-04-12 09:25:25.361 -04 SYS   ORA$AUTOTASK_CLEAN                       SUCCEEDED      0 2019-04-12 03:00:
     32769 2019-04-12 09:25:25.351 -04 SYS   SM$CLEAN_AUTO_SPLIT_MERGE                SUCCEEDED      0 2019-04-12 00:00:
    ...

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