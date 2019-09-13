/*[[Check related information for 'latch: row cache objects' event. Usage: @@NAME [<inst_id>]
    --[[
        &V1: default={&instance}
    --]]
]]*/
SELECT * FROM TABLE(GV$(CURSOR(
    SELECT ses.sid || ',' || ses.serial# || ',@' || S.inst_id SID, ses.p1raw latch_addr, ses.sql_id,
           ses.event, s.kqrstcln latch#, kqrstcid cache#, kqrsttxt NAME,
           decode(kqrsttyp, 1, 'PARENT', 'SUBORDINATE') TYPE,
           decode(kqrsttyp, 2, kqrstsno, NULL) subordinate#, kqrstgrq cache_gets,
           kqrstgmi cache_get_misses, kqrstmrq updates,l.gets latch_gets, l.misses latch_misses
    FROM   x$kqrst s, v$session ses, v$latch_children l
    WHERE  ses.p1raw = l.addr
    --AND    ses.p1text = 'cache id'
    AND    l.child# = s.kqrstcln
    AND    userenv('instance') = nvl(:V1, userenv('instance'))
)))
ORDER  BY sid,latch_addr, subordinate# nulls first;

