/*[[Library cache lock/pin holders/waiters. Usage: liblock [sid] ]]*/
with sess as(select /*+materialize*/ * from gv$session)
SELECT /*+no_expand*/
     distinct hl.*, ho.kglnaown||'.'||ho.kglnaobj object_name, h.sid || ',' || h.serial# || ',@' || h.inst_id holder,
     h.sql_id holder_sql_id, h.event holder_event, 
     nvl2(w.sid,w.sid || ',' || w.serial# || ',@' || w.inst_id,null) waiter,
     w.sql_id waiter_sql_id, w.event waiter_event
FROM   Dba_Kgllock hl, x$kglob ho, x$kglob wo, sess h, sess w
WHERE  hl.KGLLKMOD > 1
AND    hl.KGLLKUSE = h.saddr
AND    hl.KGLLKHDL = ho.kglhdadr
AND    NVL(ho.kglnaown,'SYS')!='SYS'
AND    ho.inst_id = h.inst_id
AND    ho.kglnaown = wo.kglnaown(+)
AND    ho.kglnaobj = wo.kglnaobj(+)
AND    (wo.kglhdlkc>0 OR wo.kglhdadr IS NULL)
AND    wo.kglhdadr = w.p1raw(+)
AND    wo.inst_id = w.inst_id(+)
AND   (w.event is null or upper(w.event) like '%'||upper(Hl.KGLLKTYPE))
AND   (:V1 IS NULL AND w.sid IS NOT NULL OR :V1 IN(w.sid,h.sid))