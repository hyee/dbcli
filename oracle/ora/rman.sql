/*[[Show RMAN backup infomation.]]*/
SELECT a.*,
       (select max(b.incremental_level) from v$backup_set b
        where  b.start_time<=to_date(a.etime,'YYYY-MM-DD HH24:MI  ') 
        and   b.completion_time>=to_date(a.stime,'YYYY-MM-DD HH24:MI  ')) inc_level
FROM   (SELECT /*+no_merge*/ *
        FROM   (SELECT session_recid ss_recid,
                       replace(status,'COMPLETED','SUCCES') STATUS,
                       to_char(start_time, 'YYYY-MM-DD HH24:MI  ') stime,
                       to_char(end_time, 'YYYY-MM-DD HH24:MI  ') etime,
                       time_taken_display COST,
                       input_type,
                       output_device_type output_device,                       
                       REPLACE(input_bytes_display || '(' || input_bytes_per_sec_display ||'/S)',' ')   input_Size,
                       REPLACE(output_bytes_display || '(' || output_bytes_per_sec_display ||'/S)',' ') output_Size,
                       round(COMPRESSION_RATIO, 2) COMP_RATIO
                FROM   v$rman_backup_job_details a
                )
        WHERE  nvl(upper(:V1),'A')='A'
        OR     status || stime || etime || COST || input_type || output_device LIKE UPPER('%' || :V1 || '%')
        ORDER  BY stime DESC) a
WHERE  ROWNUM <= nvl(0+:V2,50)
