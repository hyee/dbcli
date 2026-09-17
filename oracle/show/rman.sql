/*[[Show RMAN backup information.]]*/
WITH a AS
 (SELECT /*+rule materialize*/ * FROM v$rman_backup_job_details a),
b AS
 (SELECT /*+materialize*/ b.*,nvl(b.end_time-1e-5,lead(b.start_time-1e-5,1,sysdate) OVER(ORDER BY session_recid)) next_time  FROM v$rman_status b WHERE row_level=1),
c AS
 (SELECT /*+materialize*/ * FROM v$backup_set),
d AS
 (SELECT /*+materialize*/ * FROM v$backup_piece),
x AS
 (SELECT /*+opt_param('_optimizer_cartesian_enabled','false') materialize use_hash(b c d)*/
       b.session_recid,
       count(DISTINCT d.tag) tags,
       --to_char(wm_concat(DISTINCT DECODE(c.incremental_level, NULL, 'L', to_char(c.incremental_level)))) INCR_LEVEL,
       max(d.completion_time) tim,
       round(sum(d.bytes)/power(1024,3),3)||'G' outb,
       sum(CASE WHEN c.controlfile_included = 'YES' THEN c.pieces END) cf,
       sum(CASE WHEN c.controlfile_included = 'NO' AND c.backup_type||c.incremental_level = 'D' THEN c.pieces END) df,
       sum(CASE WHEN c.backup_type||c.incremental_level = 'D0' THEN c.pieces END) d0,
       sum(CASE WHEN c.backup_type||c.incremental_level = 'I1' THEN c.pieces END) d1,
       sum(CASE WHEN c.backup_type||c.incremental_level = 'I2' THEN c.pieces END) d2,
       sum(CASE WHEN c.backup_type = 'L' THEN c.pieces END) l
  FROM   b, c, d
  WHERE  (b.recid = d.rman_status_recid OR d.rman_status_recid=0 AND d.start_time BETWEEN b.start_time AND b.next_time)
  AND    c.recid = d.recid
  GROUP  BY b.session_recid)
SELECT /*+opt_param('_optimizer_cartesian_enabled','false') */ a.*
FROM   (SELECT /*+no_merge no_expand*/ *
        FROM   (SELECT /*+use_hash(a x)*/
                     session_recid ss_recid,x.tags, replace(status, 'COMPLETED', 'SUCCESS') status,
                     to_char(start_time, 'YYYY-MM-DD HH24:MI  ') start_time,
                     to_char(nvl(end_time,x.tim), 'YYYY-MM-DD HH24:MI  ') end_time,
                     round(24*(nvl(end_time,x.tim)-start_time),2) hours,
                     output_device_type device,
                     replace(input_bytes_display || '(' || input_bytes_per_sec_display || '/S)', ' ') input_size,
                     replace(decode(trim(output_bytes_display),'0.00K',x.outb,output_bytes_display) || '(' || output_bytes_per_sec_display || '/S)', ' ') output_size,
                     round(compression_ratio, 2) ratio, x.df,x.d0,x.d1,x.d2,x.l,x.cf
                FROM   a
                LEFT   JOIN x
                USING  (session_recid))
        ORDER  BY start_time DESC) a
WHERE  ROWNUM <= nvl(0+:V2,100)
