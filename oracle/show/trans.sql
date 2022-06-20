/*[[show active transactions]]*/
col "Dura|tion,roll_left,Est|Complete" format smhd2
col "Undo|Bytes,Max|Bytes" for kmg
col "LOGI|IO,PHYS|IO,CR|GET,CR|CHANGE" for tmb
set autohide col
set feed off
SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/
       sess.sid || ',' || sess.serial# || ',@' || sess.inst_id sid,
       schemaname SCHEMA,
       xid,
       XIDUSN || '.' || XIDSLOT || '.' || XIDSQN trans#,
       t.START_SCNB scn#,
       r.name rollback_seg_name,
       TRIM(',' FROM DECODE(t.space,'YES','SPACE,')||DECODE(t.recursive, 'YES', 'RECURSIVE,')
       ||DECODE(t.noundo, 'YES', 'NO UNDO,')||DECODE(t.PTX, 'YES', 'PARALLEL,'))||t.STATUS status,
       t.used_urec "Undo|Records",
       t.used_ublk "Undo|Blks",
       t.used_ublk * nvl(p.blocksize,8192) "Undo|Bytes",
       rssize "Max|Bytes",
       CASE
           WHEN bitand(t.flag, power(2, 7)) > 0 THEN
               round((rssize - t.used_ublk * nvl(p.blocksize,8192)) / nullif(rssize, 0) * 100, 3) || '%'
           ELSE
               'No'
       END AS "Is|Rollback",
       CASE
           WHEN bitand(t.flag, power(2, 7)) > 0 THEN
                ROUND((SYSDATE - t.start_date) * 86400 * (t.used_ublk * nvl(p.blocksize,8192)) 
                    / nullIF(rssize - t.used_ublk * nvl(p.blocksize,8192), 0))
           ELSE 0
       END "Est|Complete",
       trim('/' from decode(t.space,'YES','SPACE')||decode(t.recursive,'YES','/RECURSIVE')||decode(t.NOUNDO,'YES','/NOUNDO')||decode(t.PTX,'YES','/PX')) FLAG,
       t.start_date "START|DATE",
       round((SYSDATE - t.start_date) * 86400) "Dura|tion",
       t.log_io "LOGI|IO",
       t.phy_io "PHYS|IO",
       T.CR_GET "CR|GET",
       T.CR_CHANGE "CR|CHANGE"
FROM   gv$transaction t,
       v$rollname r,
       gv$rollstat r1,
       (SELECT inst_id,value blocksize FROM gv$parameter WHERE name='db_block_size') p,
       gv$session sess
WHERE  t.xidusn = r.usn(+)
AND    t.xidusn = r1.usn(+)
AND    t.inst_id = r1.inst_id(+)
AND    r1.xacts>0
AND    t.ses_addr = sess.saddr(+)
AND    t.inst_id = sess.inst_id(+)
AND    t.inst_id=p.inst_id(+)
ORDER  BY start_date;

COL UNDOBLOCKSDONE HEAD Undo|Done
grid {[[/*grid:{topic="Fast Start Transactions"}*/
    SELECT inst_id,
           usn,
           state,
           undoblockstotal "Undo|Total",
           undoblocksdone "Undo|Done",
           undoblockstotal - undoblocksdone "Undo|ToDo",
           decode(cputime,0,'unknown',(undoblockstotal - undoblocksdone) / (undoblocksdone / cputime)) "Est|Complete"
    FROM   gv$fast_start_transactions
]],'|',[[/*grid:{topic="Fast Start Servers"}*/
    SELECT * FROM GV$FAST_START_SERVERS
]]}
