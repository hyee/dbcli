/*[[SHow Oracle managed auto tasks(dba_autotask_*)]]*/
set colsize 28
set scale 4
col ATTRIBUTES,WINDOW_START_TIME,WINDOW_DURATION,JOB_INFO noprint
grid {
	{[[/*grid={topic='dba_autotask_client',pivot=8,pivotsort='head'}*/ select * from dba_autotask_client order by 1]],
	 '-',
	 [[/*grid={topic='dba_autotask_task',pivot=8,pivotsort='head'}*/ select * from dba_autotask_task order by 1]]
	},
	'|',
	{[[/*grid={topic='dba_autotask_status'}*/select * from dba_autotask_status]],
	 '-',
	 [[/*grid={topic='dba_autotask_schedule_control',pivot=8,pivotsort='TASK_NAME'}*/ select * from dba_autotask_schedule_control]],
	 '-',
	 [[/*grid={topic='dba_autotask_window_clients'}*/select * from dba_autotask_window_clients]],
	 '-',
	 [[/*grid={topic='dba_autotask_job_history'}*/SELECT * FROM (SELECT * FROM dba_autotask_job_history ORDER BY JOB_START_TIME DESC,JOB_DURATION DESC) WHERE ROWNUM<=50]]
	}

}

