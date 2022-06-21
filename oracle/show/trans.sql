/*[[show active transactions
    --[[--
        @check_access_undo: {
            dba_undo_extents={SELECT segment_name,sum(bytes) undo_bytes from dba_undo_extents where status='ACTIVE' group by segment_name}
            default={select '' segment_name,0 undo_byte from dual where 1=2}
        }
    --]]--
]]*/
col "Dura|tion,roll_left,Est|Complete,CPU|Spent" format smhd2
col "Undo|Bytes,Rollb|Bytes" for kmg
col "LOGI|IO,PHYS|IO,CR|GET,CR|CHANGE" for tmb
COL "Rollback|Progress" FOR PCT
set autohide col
set feed off
PRO GV$TRANSACTIONS
PRO ==========================
SELECT /*+opt_param('optimizer_dynamic_sampling' 5) no_merge(p) no_merge(undo)*/
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
       rssize "Rollb|Bytes",
       CASE
           WHEN bitand(t.flag, power(2, 7)) > 0 THEN
               round((nvl(undo_bytes,rssize) - t.used_ublk * nvl(p.blocksize,8192)) / nullif(nvl(undo_bytes,rssize), 0) * 100, 3) || '%'
           ELSE
               'No'
       END AS "Is|Rollback",
       CASE
           WHEN bitand(t.flag, power(2, 7)) > 0 THEN
                ROUND((SYSDATE - t.start_date) * 86400 * (t.used_ublk * nvl(p.blocksize,8192)) 
                    / nullIF(nvl(undo_bytes,rssize) - t.used_ublk * nvl(p.blocksize,8192), 0))
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
       gv$session sess,
       (&check_access_undo) undo
WHERE  t.xidusn = r.usn(+)
AND    t.xidusn = r1.usn(+)
AND    t.inst_id = r1.inst_id(+)
AND    r1.xacts>0
AND    t.ses_addr = sess.saddr(+)
AND    t.inst_id = sess.inst_id(+)
AND    t.inst_id=p.inst_id(+)
AND    r.name=undo.segment_name
ORDER  BY start_date;

COL UNDOBLOCKSDONE HEAD Undo|Done

PRO GV$FAST_START_TRANSACTIONS
PRO ==========================
SELECT /*+no_merge(b)*/ 
       inst_id,
       usn,
       r.name,
       state,
       XID,
       "PIDs",
       undoblockstotal "Undo|Total",
       undoblocksdone "Undo|Done",
       undoblockstotal - undoblocksdone "Undo|ToDo",
       undoblocksdone/undoblockstotal "Rollback|Progress",
       cputime "CPU|Spent",
       decode(cputime,0,'unknown',(undoblockstotal - undoblocksdone) / (undoblocksdone / cputime)) "Est|Complete"
FROM   gv$fast_start_transactions
LEFT  JOIN (
    SELECT inst_id,COUNT(1) "PIDs",XID 
    FROM   GV$FAST_START_SERVERS
    GROUP  BY inst_id,xid) B
USING(inst_id,xid)
LEFT  JOIN v$rollname r
USING (usn)
