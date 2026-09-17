/*[[Show Oracle managed auto tasks (dba_autotask_*)
    --[[
        @check_version: 12.1={}
    --]]
]]*/
set colsize 28
set scale 4
col ATTRIBUTES,WINDOW_START_TIME,WINDOW_DURATION,JOB_INFO noprint
grid {
    {[[/*grid={topic='dba_autotask_client',pivot=8,pivotsort='head'}*/ SELECT * FROM dba_autotask_client ORDER BY 1]],
     '-',
     [[/*grid={topic='dba_autotask_task',pivot=8,pivotsort='head'}*/ SELECT * FROM dba_autotask_task ORDER BY 1]]
    },
    '|',
    {[[/*grid={topic='dba_autotask_status'}*/SELECT * FROM dba_autotask_status]],
     '-',
     [[/*grid={topic='dba_autotask_schedule_control',pivot=8,pivotsort='TASK_NAME'}*/ SELECT * FROM dba_autotask_schedule_control ORDER BY enabled DESC, task_name]],
     '-',
     [[/*grid={topic='dba_autotask_window_clients'}*/SELECT * FROM dba_autotask_window_clients]],
     '-',
     [[/*grid={topic='dba_autotask_job_history'}*/SELECT * FROM (SELECT * FROM dba_autotask_job_history ORDER BY job_start_time DESC, job_duration DESC) WHERE rownum<=50]]
    }

}

