/*[[show active transactions]]*/
SELECT sess.inst_id, sess.sid, schemaname, XIDUSN || '.' || XIDSLOT || '.' || XIDSQN transaction#, r.name rollback_seg_name,
       USED_UBLK undo_blocks, t.used_urec records,
       round(t.used_ublk * p.value/1024/1024,2) used_mb,
       DECODE(t.space,
               'YES',
               'SPACE TX',
               DECODE(t.recursive,
                      'YES',
                      'RECURSIVE TX',
                      DECODE(t.noundo, 'YES', 'NO UNDO TX', t.status))) status, a.value total_commits,
        case when bitand(t.flag,power(2,7)) > 0 then 'YES' else 'NO' end as rollback,
       t.space,t.recursive, 
       t.start_date,
       round((sysdate-t.start_date)*1440,2) duration_min,
       t.log_io,
       t.phy_io
FROM   gv$transaction t, v$rollname r,
       (SELECT VALUE FROM v$parameter WHERE NAME = 'db_block_size') p, gv$session sess,gv$sesstat a
WHERE  t.xidusn = r.usn(+)
AND    t.ses_addr = sess.saddr(+)
AND    t.inst_id = sess.inst_id(+)
AND    a.sid(+) = sess.sid
AND    a.inst_id(+) = sess.inst_id
AND    a.statistic#(+) = 6
order by start_date