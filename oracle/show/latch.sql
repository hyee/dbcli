/*[[show current latch info]]*/
SELECT a.sid||','||a.serial#||',@'||a.inst_id sid,
       a.EVENT,
       a.SQL_ID,
       A.SECONDS_IN_WAIT Secs,
       a.P1RAW,
       a.p3 tries,
       b.FILE#,
       b.BLOCK#,
       b.STATUS,
       TRIM(',' FROM
       DECODE(b.DIRTY,'Y','dirty,')||
       DECODE(b.TEMP,'Y','temp,')||
       DECODE(b.PING,'Y','ping,')||
       DECODE(b.STALE,'Y','Stale,')||
       DECODE(b.DIRECT,'Y','direct,')||
       DECODE(b.new,'Y','new,')) typ,
       (SELECT CLASS FROM (SELECT ROWNUM r,CLASS FROM v$waitstat) WHERE r=b.CLASS#)  CLASS,
       (SELECT object_name
        FROM   All_Objects d
        WHERE  b.OBJD IN (d.DATA_OBJECT_ID, d.OBJECT_ID)
        AND    ROWNUM < 2) obj,
       c.NAME latch,
       c.GETS,
       c.MISSES,
       c.SLEEPS
FROM   gv$session a, gv$bh b, gv$latch_children c
WHERE  a.inst_id = b.inst_id
AND    a.inst_id = c.inst_id
AND    a.P1RAW = b.LOCK_ELEMENT_ADDR
AND    a.P1RAW = c.ADDR
AND    a.event LIKE '%latch%'