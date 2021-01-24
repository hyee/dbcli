/*[[show active transactions]]*/
col "duration,roll_left,Est|Complete" format smhd2
col "Undo|Bytes" for kmg
set feed off
SELECT sess.sid || ',' || sess.serial# || ',@' || sess.inst_id sid,
       schemaname SCHEMA,
       xid,
       XIDUSN || '.' || XIDSLOT || '.' || XIDSQN trans#,
       r.name rollback_seg_name,
       DECODE(t.space,
              'YES',
              'SPACE TX',
              DECODE(t.recursive, 'YES', 'RECURSIVE TX', DECODE(t.noundo, 'YES', 'NO UNDO TX', t.status))) status,
       t.used_urec "Undo|Records",
       t.used_ublk "Undo|Blks",
       t.used_ublk * p.value "Undo|Bytes",
       a.value "Total|Commits",
       CASE
           WHEN bitand(t.flag, power(2, 7)) > 0 THEN
            round((rssize - t.used_ublk * p.value) / nullif(rssize, 0) * 100, 3) || '%'
           ELSE
            'No'
       END AS "Is|Rollback",
       CASE
           WHEN bitand(t.flag, power(2, 7)) > 0 THEN
            ROUND((SYSDATE - t.start_date) * 86400 * (t.used_ublk * p.value) / nullIF(rssize - t.used_ublk * p.value, 0))
           ELSE
            0
       END "Est|Complete",
       trim('/' from decode(t.space,'YES','SPACE')||decode(t.recursive,'YES','/RECURSIVE')||decode(t.NOUNDO,'YES','/NOUNDO')||decode(t.PTX,'YES','/PX')) FLAG,
       t.start_date,
       round((SYSDATE - t.start_date) * 86400) duration,
       t.log_io,
       t.phy_io,
       T.CR_GET,
       T.CR_CHANGE
FROM   gv$transaction t,
       v$rollname r,
       gv$rollstat r1,
       (SELECT VALUE FROM v$parameter WHERE NAME = 'db_block_size') p,
       gv$session sess,
       gv$sesstat a
WHERE  t.xidusn = r.usn(+)
AND    t.xidusn = r1.usn(+)
AND    t.inst_id = r1.inst_id(+)
AND    t.ses_addr = sess.saddr(+)
AND    t.inst_id = sess.inst_id(+)
AND    a.sid(+) = sess.sid
AND    a.inst_id(+) = sess.inst_id
AND    a.statistic#(+) = 6
ORDER  BY start_date;

COL UNDOBLOCKSDONE HEAD Undo|Done
grid {[[/*grid:{topic="Fast Start Transactions"}*/
    SELECT inst_id,
           usn,
           state,
           undoblockstotal "Undo|Total",
           undoblocksdone "Undo|Done",
           undoblockstotal - undoblocksdone "Undo|ToDo",
           decode(cputime,
                  0,
                  'unknown',
                  SYSDATE + (((undoblockstotal - undoblocksdone) / (undoblocksdone / cputime)) / 86400)) "Est|Complete"
    FROM   gv$fast_start_transactions
]],'|',[[/*grid:{topic="Fast Start Servers"}*/
    SELECT * FROM GV$FAST_START_SERVERS
]]}
