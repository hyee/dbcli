/*[[show current holding/waiting latch info]]*/
select 'Holding' typ,
       s.inst_id,s.sid,
       s.serial#,
       s.process,
       s.username,
       s.terminal,
       h.name latch_name,
       rawtohex(laddr) addr,
       p1raw,
       p2raw,
       p3raw,
       p1text,
       p2text,
       p3text
  from gv$process p, gv$session s, gv$latchholder h
 where h.pid = p.pid
   and p.addr = s.paddr
   and p.inst_id = s.inst_id
   and p.inst_id = h.inst_id
UNION ALL
select 'Waiting',
       s.inst_id,s.sid,
       s.serial#,
       s.process,
       s.username,
       s.terminal,
       l.name,
       p.latchwait,
       p1raw,
       p2raw,
       p3raw,
       p1text,
       p2text,
       p3text
  from gv$session s, gv$process p, gv$latch l
 where latchwait is not null
   and p.addr = s.paddr
   and p.latchwait = l.addr
   and p.inst_id = s.inst_id
   and p.inst_id = l.inst_id;
