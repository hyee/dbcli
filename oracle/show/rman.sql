/*[[Show RMAN backup infomation.]]*/
WITH a AS
 (SELECT /*+rule materialize*/ * FROM v$rman_backup_job_details a),
b AS
 (SELECT /*+materialize*/ b.*,nvl(b.end_time-1e-5,lead(b.start_time-1e-5,1,sysdate) over(order by session_recid)) next_time  FROM v$rman_status b where ROW_LEVEL=1),
c AS
 (SELECT /*+materialize*/ * FROM v$backup_set),
d AS
 (SELECT /*+materialize*/* FROM v$backup_piece),
x AS
 (SELECT /*+opt_param('_optimizer_cartesian_enabled','false') materialize use_hash(b c d)*/
       b.session_recid,
       count(distinct d.tag) tags,
       --to_char(wm_concat(DISTINCT DECODE(c.incremental_level, NULL, 'L', to_char(c.incremental_level)))) INCR_LEVEL,
       max(d.completion_time) tim,
       round(sum(d.bytes)/power(1024,3),3)||'G' outb,
       sum(case when c.controlfile_included = 'YES' then c.pieces end) CF,
       sum(case when c.controlfile_included = 'NO' and c.backup_type||c.incremental_level = 'D' then c.pieces end) DF,
       sum(case when c.backup_type||c.incremental_level = 'D0' then c.pieces end) D0,
       sum(case when c.backup_type||c.incremental_level = 'I1' then c.pieces end) D1,
       sum(case when c.backup_type||c.incremental_level = 'I2' then c.pieces end) D2,
       sum(case when c.backup_type = 'L' then c.pieces end) L
  FROM    b, c, d
  WHERE  (b.recid = d.rman_status_recid or d.rman_status_recid=0 and d.start_time between b.start_time and b.next_time)
  AND    c.recid = d.recid
  GROUP  BY b.session_recid)
SELECT /*+opt_param('_optimizer_cartesian_enabled','false') */ a.*
FROM   (SELECT /*+no_merge no_expand*/ *
        FROM   (SELECT /*+use_hash(a x)*/
                     session_recid ss_recid,x.tags, REPLACE(status, 'COMPLETED', 'SUCCES') STATUS,
                     to_char(start_time, 'YYYY-MM-DD HH24:MI  ') start_time,
                     to_char(nvl(end_time,x.tim), 'YYYY-MM-DD HH24:MI  ') end_time,
                     round(24*(nvl(end_time,x.tim)-start_time),2) hours,
                     output_device_type device,
                     REPLACE(input_bytes_display || '(' || input_bytes_per_sec_display || '/S)', ' ') input_Size,
                     REPLACE(decode(trim(output_bytes_display),'0.00K',x.outb,output_bytes_display) || '(' || output_bytes_per_sec_display || '/S)', ' ') output_Size,
                     round(COMPRESSION_RATIO, 2) RATIO, x.df,x.D0,x.D1,x.D2,x.L,x.cf
                FROM   a
                LEFT   JOIN x
                USING  (session_recid))
        ORDER  BY start_time DESC) a
WHERE  ROWNUM <= nvl(0+:V2,100)
