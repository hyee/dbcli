/*[[Show current holding/waiting latch info]]*/
SELECT 'Holding' typ,
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
FROM   gv$process p, gv$session s, gv$latchholder h
WHERE  h.pid = p.pid
AND    p.addr = s.paddr
AND    p.inst_id = s.inst_id
AND    p.inst_id = h.inst_id
UNION  ALL
SELECT 'Waiting',
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
FROM   gv$session s, gv$process p, gv$latch l
WHERE  latchwait IS NOT NULL
AND    p.addr = s.paddr
AND    p.latchwait = l.addr
AND    p.inst_id = s.inst_id
AND    p.inst_id = l.inst_id;
