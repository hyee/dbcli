/*[[show active transactions]]*/
col duration,roll_left format smhd2
SELECT  sess.sid||','||sess.serial#||',@'||sess.inst_id sid, schemaname, XIDUSN || '.' || XIDSLOT || '.' || XIDSQN transaction#, r.name rollback_seg_name,
       USED_UBLK undo_blocks, t.used_urec records,
       round(t.used_ublk * p.value/1024/1024,2) used_mb,
       DECODE(t.space,
               'YES',
               'SPACE TX',
               DECODE(t.recursive,
                      'YES',
                      'RECURSIVE TX',
                      DECODE(t.noundo, 'YES', 'NO UNDO TX', t.status))) status, a.value total_commits,
       case when bitand(t.flag,power(2,7)) > 0 then round((rssize-t.used_ublk * p.value)/nullif(rssize,0)*100,3)||'%' else 'No' end as rollback,
       case when bitand(t.flag,power(2,7)) > 0 then ROUND((sysdate-t.start_date)*86400*(t.used_ublk * p.value)/nullIF(rssize-t.used_ublk * p.value,0)) else 0 end roll_left,
       t.space,t.recursive, 
       t.start_date,
       round((sysdate-t.start_date)*86400) duration,
       t.log_io,
       t.phy_io
FROM   gv$transaction t, v$rollname r,gv$rollstat r1,
       (SELECT VALUE FROM v$parameter WHERE NAME = 'db_block_size') p, gv$session sess,gv$sesstat a
WHERE  t.xidusn = r.usn(+)
AND    t.xidusn = r1.usn(+)
AND    t.inst_id=r1.inst_id(+)
AND    t.ses_addr = sess.saddr(+)
AND    t.inst_id = sess.inst_id(+)
AND    a.sid(+) = sess.sid
AND    a.inst_id(+) = sess.inst_id
AND    a.statistic#(+) = 6
order by start_date