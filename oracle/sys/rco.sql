/*[[
    Check related information for 'latch: row cache objects'/'row cache xxx' events. Usage: @@NAME [<sid>] [<inst_id>]
    Refer to Doc ID 34609.1
    --[[
        &V2: default={&instance}
    --]]
]]*/
SELECT * FROM TABLE(GV$(CURSOR(
    SELECT h.sid H_SID,
           ses.sid || ',' || ses.serial# || ',@' || S.inst_id W_SID, ses.p1raw latch_addr, ses.sql_id,
           ses.event, s.kqrstcln latch#, kqrstcid cache#, kqrsttxt NAME,
           decode(kqrsttyp, 1, 'PARENT', 'SUBORDINATE') TYPE,
           decode(kqrsttyp, 2, kqrstsno, NULL) subordinate#, kqrstgrq cache_gets,
           kqrstgmi cache_get_misses, kqrstmrq updates,l.gets latch_gets, l.misses latch_misses
    FROM   x$kqrst s, v$session ses, v$latch_children l,v$latchholder h
    WHERE  ses.p1raw = l.addr
    AND    l.child# = s.kqrstcln
    AND    l.addr   =h.laddr(+)
    AND    nvl(0+:v1,-1) IN(-1,h.sid,ses.sid)
    AND    userenv('instance') = nvl(:V2, userenv('instance'))
)))
ORDER  BY W_SID,latch_addr, subordinate# nulls first;

SELECT * FROM TABLE(GV$(CURSOR(
    SELECT s.inst_id,
           s.KQRFPCID cache#,
           s.KQRFPCNM cache_name,
           s.KQRFPII1 INST_LOCK_ID1,
           s.KQRFPII2 INST_LOCK_ID2,
           h.sid holder_sid,
           h.sql_id holder_sqlid,
           h.event holder_event,
           w.sid waiter_sid,
           w.sql_id waiter_sqlid,
           w.event waiter_Event,
           decode(w.p3,0,'NULL',3,'SHARED',5,'EXCLUSIVE','FAIL TO AQUIRE INST LOCK') req_mode
    FROM   X$KQRFP s, v$session h, v$session w
    WHERE  w.p1(+)=s.KQRFPCID and s.KQRFPSES=h.saddr(+)
    AND    w.p1text='cache id'
    AND    greatest(KQRFPMOD, KQRFPREQ, KQRFPIRQ)>0
    AND    nvl(0+:v1,-1) IN(-1,h.sid,w.sid)
    AND    userenv('instance') = nvl(:V2, userenv('instance'))
)));