/*[[Show blocking infomation, including equeue and library waits]]*/

set feed off
PRO From DBA_Waiters:
PRO =================
select * from dba_waiters;

PRO From DBA_KGLLOCK:
PRO =================
SELECT /*+ ordered no_expand*/
 w1.sid || '@' || w1.inst_id waiting_session, h1.sid || '@' || h1.inst_id holding_session,
 w.kgllktype lock_or_pin, w.kgllkhdl address,
 decode(h.kgllkmod, 0, 'None', 1, 'Null', 2, 'Share', 3, 'Exclusive', 'Unknown') mode_held,
 decode(w.kgllkreq, 0, 'None', 1, 'Null', 2, 'Share', 3, 'Exclusive', 'Unknown') mode_requested
FROM   dba_kgllock w, dba_kgllock h, gv$session w1, gv$session h1
WHERE  h.kgllkreq IN (0, 1)
AND    w.kgllkmod IN (0, 1)
AND    h.kgllkmod NOT IN (0, 1)
AND    w.kgllkreq NOT IN (0, 1)
AND    w.kgllktype = h.kgllktype
AND    w.kgllkhdl = h.kgllkhdl
AND    w.kgllkuse = w1.saddr
AND    h.kgllkuse = h1.saddr;