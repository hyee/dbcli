/*[[Show RMAN backup infomation.]]*/
SELECT a.*
FROM   (SELECT /*+no_merge*/ *
        FROM   (SELECT session_recid ss_recid,
                       replace(status,'COMPLETED','SUCCES') STATUS,
                       to_char(start_time, 'YYYY-MM-DD HH24:MI  ') start_time,
                       to_char(end_time, 'YYYY-MM-DD HH24:MI  ') end_time,
                       time_taken_display Duration,
                       (select to_char(wm_concat(DISTINCT object_type)) from v$rman_status where session_recid=a.session_recid) input_type,
                       output_device_type output_device,                       
                       REPLACE(input_bytes_display || '(' || input_bytes_per_sec_display ||'/S)',' ')   input_Size,
                       REPLACE(output_bytes_display || '(' || output_bytes_per_sec_display ||'/S)',' ') output_Size,
                       round(COMPRESSION_RATIO, 2) COMP_RATIO,
                       (select  min(c.incremental_level) 
                        from v$rman_status b,v$backup_set c ,v$backup_piece d
                        where b.session_recid=a.session_recid
                        and   b.recid=d.rman_status_recid
                        and   c.recid=d.recid) INCR_LEVEL
                FROM   v$rman_backup_job_details a
                )
        WHERE  nvl(upper(:V1),'A')='A'
        OR     status || start_time || end_time  || output_device LIKE UPPER('%' || :V1 || '%')
        ORDER  BY start_time DESC) a
WHERE  ROWNUM <= nvl(0+:V2,100)
