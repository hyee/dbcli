/*[[Diag the RAC System (Doc ID 135714.1)]]*/
SET FEED OFF
PRO GES LOCK BLOCKERS: 
PRO ==================
SELECT dl.inst_id,
       s.sid,
       p.spid,
       dl.resource_name1,
       decode(substr(dl.grant_level, 1, 8),
              'KJUSERNL',
              'Null',
              'KJUSERCR',
              'Row-S (SS)',
              'KJUSERCW',
              'Row-X (SX)',
              'KJUSERPR',
              'Share',
              'KJUSERPW',
              'S/Row-X (SSX)',
              'KJUSEREX',
              'Exclusive',
              request_level) AS grant_level,
       decode(substr(dl.request_level, 1, 8),
              'KJUSERNL',
              'Null',
              'KJUSERCR',
              'Row-S (SS)',
              'KJUSERCW',
              'Row-X (SX)',
              'KJUSERPR',
              'Share',
              'KJUSERPW',
              'S/Row-X (SSX)',
              'KJUSEREX',
              'Exclusive',
              request_level) AS request_level,
       decode(substr(dl.state, 1, 8),
              'KJUSERGR',
              'Granted',
              'KJUSEROP',
              'Opening',
              'KJUSERCA',
              'Canceling',
              'KJUSERCV',
              'Converting') AS state,
       s.sid,
       sw.event,
       sw.seconds_in_wait sec
FROM   gv$ges_enqueue dl, gv$process p, gv$session s, gv$session_wait sw
WHERE  blocker = 1
AND    (dl.inst_id = p.inst_id AND dl.pid = p.spid)
AND    (p.inst_id = s.inst_id AND p.addr = s.paddr)
AND    (s.inst_id = sw.inst_id AND s.sid = sw.sid)
ORDER  BY sw.seconds_in_wait DESC;

PRO GES LOCK WAITERS: 
PRO ==================
SELECT dl.inst_id,
       s.sid,
       p.spid,
       dl.resource_name1,
       decode(substr(dl.grant_level, 1, 8),
              'KJUSERNL',
              'Null',
              'KJUSERCR',
              'Row-S (SS)',
              'KJUSERCW',
              'Row-X (SX)',
              'KJUSERPR',
              'Share',
              'KJUSERPW',
              'S/Row-X (SSX)',
              'KJUSEREX',
              'Exclusive',
              request_level) AS grant_level,
       decode(substr(dl.request_level, 1, 8),
              'KJUSERNL',
              'Null',
              'KJUSERCR',
              'Row-S (SS)',
              'KJUSERCW',
              'Row-X (SX)',
              'KJUSERPR',
              'Share',
              'KJUSERPW',
              'S/Row-X (SSX)',
              'KJUSEREX',
              'Exclusive',
              request_level) AS request_level,
       decode(substr(dl.state, 1, 8),
              'KJUSERGR',
              'Granted',
              'KJUSEROP',
              'Opening',
              'KJUSERCA',
              'Cancelling',
              'KJUSERCV',
              'Converting') AS state,
       s.sid,
       sw.event,
       sw.seconds_in_wait sec
FROM   gv$ges_enqueue dl, gv$process p, gv$session s, gv$session_wait sw
WHERE  blocked = 1
AND    (dl.inst_id = p.inst_id AND dl.pid = p.spid)
AND    (p.inst_id = s.inst_id AND p.addr = s.paddr)
AND    (s.inst_id = sw.inst_id AND s.sid = sw.sid)
ORDER  BY sw.seconds_in_wait DESC;


PRO LOCAL ENQUEUES
PRO ===============
SELECT l.inst_id,
       l.sid,
       l.addr,
       l.type,
       l.id1,
       l.id2,
       decode(l.block, 0, 'blocked', 1, 'blocking', 2, 'global') BLOCK,
       sw.event,
       sw.seconds_in_wait sec
FROM   gv$lock l, gv$session_wait sw
WHERE  (l.sid = sw.sid AND l.inst_id = sw.inst_id)
AND    l.block IN (0, 1)
ORDER  BY l.type, l.inst_id, l.sid;

PRO LATCH HOLDERS
PRO ===============
SELECT DISTINCT lh.inst_id, s.sid, s.username, p.username os_user, lh.name
FROM   gv$latchholder lh, gv$session s, gv$process p
WHERE  (lh.sid = s.sid AND lh.inst_id = s.inst_id)
AND    (s.inst_id = p.inst_id AND s.paddr = p.addr)
ORDER  BY lh.inst_id, s.sid;

PRO LATCH STATS
PRO ===============
SELECT inst_id,
       NAME latch_name,
       round((gets - misses) / decode(gets, 0, 1, gets), 3) hit_ratio,
       round(sleeps / decode(misses, 0, 1, misses), 3) "SLEEPS/MISS"
FROM   gv$latch
WHERE  round((gets - misses) / decode(gets, 0, 1, gets), 3) < .99
AND    gets != 0
ORDER  BY round((gets - misses) / decode(gets, 0, 1, gets), 3);

PRO NO WAIT LATCHES
PRO ===================
SELECT inst_id,
       NAME latch_name,
       round((immediate_gets / (immediate_gets + immediate_misses)), 3) hit_ratio,
       round(sleeps / decode(immediate_misses, 0, 1, immediate_misses), 3) "SLEEPS/MISS"
FROM   gv$latch
WHERE  round((immediate_gets / (immediate_gets + immediate_misses)), 3) < .99
AND    immediate_gets + immediate_misses > 0
ORDER  BY round((immediate_gets / (immediate_gets + immediate_misses)), 3);

PRO GLOBAL CACHE CR PERFORMANCE 
PRO ===========================
SELECT b1.inst_id,
       b2.value "GCS CR BLOCKS RECEIVED",
       b1.value "GCS CR BLOCK RECEIVE TIME",
       ((b1.value / b2.value) * 10) "AVG CR BLOCK RECEIVE TIME (ms)"
FROM   gv$sysstat b1, gv$sysstat b2
WHERE  b1.name = 'global cache cr block receive time'
AND    b2.name = 'global cache cr blocks received'
AND    b1.inst_id = b2.inst_id
OR     b1.name = 'gc cr block receive time'
AND    b2.name = 'gc cr blocks received'
AND    b1.inst_id = b2.inst_id;

PRO GLOBAL CACHE LOCK PERFORMANCE
PRO ==============================
SELECT b1.inst_id,
       (b1.value + b2.value) "GLOBAL LOCK GETS",
       b3.value "GLOBAL LOCK GET TIME",
       (b3.value / (b1.value + b2.value) * 10) "AVG GLOBAL LOCK GET TIME (ms)"
FROM   gv$sysstat b1, gv$sysstat b2, gv$sysstat b3
WHERE  b1.name = 'global lock sync gets'
AND    b2.name = 'global lock async gets'
AND    b3.name = 'global lock get time'
AND    b1.inst_id = b2.inst_id
AND    b2.inst_id = b3.inst_id
OR     b1.name = 'global enqueue gets sync'
AND    b2.name = 'global enqueue gets async'
AND    b3.name = 'global enqueue get time'
AND    b1.inst_id = b2.inst_id
AND    b2.inst_id = b3.inst_id;


PRO LOCK ACTIVITY
PRO ==============================
select * from gv$lock_activity; 