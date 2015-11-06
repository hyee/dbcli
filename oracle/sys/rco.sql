/*[[Check related information for 'latch: row cache objects' event]]*/
SELECT ses.sid || ',' || ses.serial# || ',@' || ses.inst_id SID, ses.p1raw latch_addr, ses.sql_id,
       ses.event, s.kqrstcln latch#, kqrstcid cache#, kqrsttxt NAME,
       decode(kqrsttyp, 1, 'PARENT', 'SUBORDINATE') TYPE,
       decode(kqrsttyp, 2, kqrstsno, NULL) subordinate#, kqrstgrq cache_gets,
       kqrstgmi cache_get_misses, kqrstmrq updates,l.gets latch_gets, l.misses latch_misses
FROM   x$kqrst s, gv$session ses, gv$latch_children l
WHERE  s.inst_id = ses.inst_id
AND    s.inst_id = l.inst_id
AND    ses.p1raw = l.addr
AND    l.child# = s.kqrstcln
ORDER  BY sid,latch_addr, subordinate# nulls first;

