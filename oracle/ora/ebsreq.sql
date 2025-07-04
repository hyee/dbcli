/*[[Show or execute EBS concurrent requests. Usage: @@NAME {[-p|-m|-r] <keyword> | -f "<filter>" | -f0 "<filter>" | -e <req_id>}
    -p : search with program name
    -r : search with request id
    -m : search with module name
    -f : filter(where clause) from output
    -f0: filter(where clause) from source tables 
    -e : copy and execute target request_id
    -trace: together with -e to enable trace(remember to manully turn off trace)
    --[[
        &filter: {
            default={start_ between sysdate-3 and sysdate}
            p={upper(program) like '%'||v1||'%'}
            m={upper(module) like '%'||v1||'%'}
            f={&v1}
            f0={1=1}
            e={req_id=req}
            r={req in(req_id,parent#)}
        }
        &f1: default={1=1} f0={&V1}
        &trace: default={0} trace={&check_obj_access_mon}
        &check_obj_access_mon: sys.DBMS_LOCK={1} default={0}
    --]]
]]*/
set feed off
var c refcursor;
var trace VARCHAR2(300)

DECLARE
    v1 VARCHAR2(300):=upper(:v1);
    req INT := regexp_substr(v1,'^\d+$');
    trace VARCHAR2(300);
    inst  INT;
    cnt   INT := 0;
BEGIN
    IF :filter = 'req_id=req' AND req IS NOT NULL THEN
        FOR r IN (SELECT a.*, fa.APPLICATION_SHORT_NAME, fcp.CONCURRENT_PROGRAM_NAME
                  FROM   apps.fnd_concurrent_Requests a, apps.fnd_application fa, apps.fnd_concurrent_programs fcp
                  WHERE  a.PROGRAM_APPLICATION_ID = fcp.application_id
                  AND    a.PROGRAM_APPLICATION_ID = fa.application_id
                  AND    a.concurrent_program_id = fcp.concurrent_program_id
                  AND    a.request_id = req) LOOP
            apps.fnd_global.apps_initialize(user_id      => r.requested_by,
                                       resp_id      => r.responsibility_id,
                                       resp_appl_id => r.responsibility_application_id);
            req := apps.fnd_request.submit_request(application => r.application_short_name,
                                                 program     => r.CONCURRENT_PROGRAM_NAME,
                                                 description => r.description,
                                                 start_time  => null,
                                                 sub_request => FALSE,
                                                 argument1   => r.argument1,
                                                 argument2   => r.argument2, 
                                                 argument3   => r.argument3,
                                                 argument4   => r.argument4, 
                                                 argument5   => r.argument5, 
                                                 argument6   => r.argument6, 
                                                 argument7   => r.argument7, 
                                                 argument8   => r.argument8, 
                                                 argument9   => r.argument9, 
                                                 argument10  => r.argument10,
                                                 argument11  => r.argument11,
                                                 argument12  => r.argument12,
                                                 argument13  => r.argument13,
                                                 argument14  => r.argument14,
                                                 argument15  => r.argument15,
                                                 argument16  => r.argument16,
                                                 argument17  => r.argument17,
                                                 argument18  => r.argument18,
                                                 argument19  => r.argument19,
                                                 argument20  => r.argument20,
                                                 argument21  => r.argument21,
                                                 argument22  => r.argument22,
                                                 argument23  => r.argument23,
                                                 argument24  => r.argument24,
                                                 argument25  => r.argument25);
            --ROLLBACK;
            dbms_output.put_line('Request # '||req||' submmited.');
            COMMIT;

            $IF &trace=1 $THEN
                LOOP
                    SELECT MAX('ora trace '||d.sid || ','||d.serial#),MAX(d.inst_id)
                    INTO trace,inst
                    FROM apps.fnd_concurrent_requests a,
                           apps.fnd_concurrent_processes b,
                           gv$process c,
                           gv$session d
                    WHERE  a.request_id= req
                    AND    a.controlling_manager = b.concurrent_process_id
                    AND    c.pid = b.oracle_process_id
                    AND    c.inst_id = b.instance_number
                    AND    c.inst_id = d.inst_id
                    AND    c.addr = d.paddr;
                    IF inst IS NOT NULL AND inst != userenv('instance') THEN
                        trace := null;
                    END IF;
                    EXIT WHEN inst IS NOT NULL;
                    cnt := cnt +1;
                    EXIT WHEN cnt >= 30;
                    sys.DBMS_LOCK.SLEEP(1);
                END LOOP;
            $END
            EXIT;
        END LOOP;
    END IF;

    :trace := trace;

    OPEN :c FOR
        SELECT * FROM (
            SELECT a.request_id req_id,
                   e1.program,
                   a.parent_request_id parent#,
                   (select request_id from apps.fnd_concurrent_requests a1 
                   where a1.parent_request_id=a.request_id and rownum<2) child#,
                   '('||a.status_code||')'||
                   decode(a.status_code,
                       'A','Waiting',
                       'B','Resuming',
                       'C','Normal',
                       'D','Cancelled',
                       'E','Errored',
                       'F','Scheduled',
                       'G','Warning',
                       'H','On Hold',
                       'I','Normal',
                       'M','No Manager',
                       'Q','Standby',
                       'R','Normal',
                       'S','Suspended',
                       'T','Terminating',
                       'U','Disabled',
                       'W','Paused',
                       'X','Terminated',
                       'Z','Waiting') status,
                   decode(a.phase_code,
                       'C','Completed',
                       'I','Inactive',
                       'P','Pending',
                       'R','Running') phase,    
                   CASE WHEN a.status_code='R' THEN d.sid || ','||d.serial#||',@'||d.inst_id ELSE to_char(b.session_id) END SID,
                   round(86400 * (coalesce(a.actual_completion_date,case when a.last_update_date>a.actual_start_date+1/1440 then a.last_update_date end, case when status_code='I' then SYSDATE end) - a.actual_start_date)) dur,
                   d.sql_id,
                   a.actual_start_date start_,
                   nvl(a.actual_completion_date,case when a.last_update_date>a.actual_start_date+1/1440 then a.last_update_date end) end_,
                   e1.LANGUAGE LANG,
                   f1.user_executable_name module,
                   decode(f2.execution_method_code,
                       'B','Request Set Stage Function',
                       'Q','SQL*Plus',
                       'H','Host',
                       'L','SQL*Loader',
                       'A','Spawned',
                       'I','PL/SQL',
                       'P','Oracle Reports',
                       'S','Immediate') execution_method,
                   f2.execution_file_name,
                   A.argument_text,
                   A.outfile_name,
                   A.logfile_name
            FROM   apps.fnd_concurrent_requests a,
                   apps.fnd_concurrent_processes b,
                   gv$process c,
                   gv$session d,
                   apps.fnd_concurrent_programs e,
                   (SELECT concurrent_program_id,
                           MAX(user_concurrent_program_name) keep(dense_rank LAST ORDER BY decode(LANGUAGE, 'US', 1, 2)) program,
                           MAX(LANGUAGE) keep(dense_rank LAST ORDER BY decode(LANGUAGE, 'US', 1, 2)) LANGUAGE
                    FROM   apps.fnd_concurrent_programs_tl
                    GROUP  BY concurrent_program_id) e1,
                   apps.fnd_executables_tl f1,
                   apps.fnd_executables f2
            WHERE  (&f1)
            AND    a.controlling_manager = b.concurrent_process_id
            AND    a.concurrent_program_id = e.concurrent_program_id
            AND    a.concurrent_program_id = e1.concurrent_program_id
            AND    e.executable_id = f1.executable_id
            AND    e.executable_application_id = f1.application_id
            AND    f1.executable_id=f2.executable_id
            AND    f1.application_id=f2.application_id
            AND    e1.LANGUAGE = f1.LANGUAGE
            AND    c.pid(+) = b.oracle_process_id
            AND    c.inst_id(+) = b.instance_number
            AND    c.inst_id = d.inst_id(+)
            AND    c.addr = d.paddr(+))
        WHERE &filter
        order by case when phase like '%Running%' AND status like '%Normal%' then 1 else 2 end, start_ desc 
        fetch first 50 rows only;
END;
/

&trace