/*[[Diag the RAC System (Doc ID 135714.1)]]*/
SET FEED OFF
col "AVG TIME,GCS CURRENT BLOCK RECEIVE TIME,GCS CR BLOCK RECEIVE TIME" for usmhd2
col "HIT_RATIO,SLEEPS/MISS" for pct
col "gets,GCS CR BLOCKS RECEIVED,GCS CURRENT BLOCKS RECEIVED" for tmb

grid {
    {[[q'[ /*grid={topic="LOCAL ENQUEUES"}*/ 
        SELECT * FROM TABLE(GV$(CURSOR(
           SELECT userenv('instance') inst_id,
                  l.sid,
                  l.addr,
                  l.type,
                  l.id1,
                  l.id2,
                  decode(l.block, 0, 'blocked', 1, 'blocking', 2, 'global') BLOCK,
                  sw.event,
                  sw.seconds_in_wait sec
            FROM   v$lock l, v$session_wait sw
            WHERE  (l.sid = sw.sid)
            AND    l.block IN (0, 1))))
        ORDER BY 1,4]']],'|',
    [[q'[/*grid={topic="LATCH HOLDERS"}*/
        SELECT * FROM TABLE(GV$(CURSOR(
            SELECT DISTINCT userenv('instance') inst_id, s.sid, s.username, p.username os_user, lh.name
            FROM   v$latchholder lh, v$session s, v$process p
            WHERE  (lh.sid = s.sid)
            AND    (s.paddr = p.addr)
            ORDER  BY s.sid)))
        ORDER BY 1,2]']]
    },'-',{[[
      q'[/*grid={topic="LATCH STATS"}*/
        SELECT * FROM ( 
            SELECT NAME latch_name,
                   SUM(gets) gets,
                   round(SUM(gets - misses) / nullif(SUM(decode(gets, 0, 1, gets)),0), 4) hit_ratio,
                   round(SUM(sleeps) / nullif(SUM(decode(misses, 0, 1, misses)),0), 4) "SLEEPS/MISS"
            FROM   gv$latch
            WHERE  gets>0
            GROUP  BY name) 
        WHERE hit_ratio < 0.98
        ORDER  BY hit_ratio]']],'|',
    [[q'[/*grid={topic="NO WAIT LATCHES"}*/
        SELECT * FROM (
            SELECT NAME latch_name,
                   sum(immediate_gets) gets,
                   round(SUM(immediate_gets) / nullif(SUM(immediate_gets + immediate_misses),0), 4) hit_ratio,
                   round(SUM(sleeps) / nullif(SUM(decode(immediate_misses, 0, 1, immediate_misses)),0), 4) "SLEEPS/MISS"
            FROM   gv$latch
            WHERE  immediate_gets+immediate_misses>0
            GROUP  BY name)
        WHERE hit_ratio < 0.99
        ORDER  BY hit_ratio]']]
    },'-',{[[
       q'[/*grid={topic="GLOBAL CACHE CR PERFORMANCE "}*/
       SELECT * FROM TABLE(GV$(CURSOR(
           SELECT userenv('instance') inst_id,
                  b2.value "GCS CR BLOCKS RECEIVED",
                  b1.value "GCS CR BLOCK RECEIVE TIME",
                  round((b1.value / nullif(b2.value,0)) * 10000,2) "AVG TIME"
           FROM   v$sysstat b1, v$sysstat b2
           WHERE  b1.name = 'global cache cr block receive time'
           AND    b2.name = 'global cache cr blocks received'
           OR     b1.name = 'gc cr block receive time'
           AND    b2.name = 'gc cr blocks received')))]']],'|',
    [[q'[/*grid={topic="GLOBAL CACHE CURRENT PERFORMANCE "}*/
       SELECT * FROM TABLE(GV$(CURSOR(
           SELECT userenv('instance') inst_id,
                  b2.value "GCS CURRENT BLOCKS RECEIVED",
                  b1.value * 10000 "GCS CURRENT BLOCK RECEIVE TIME",
                  round((b1.value / nullif(b2.value,0)) * 10000,2) "AVG TIME"
           FROM   v$sysstat b1, v$sysstat b2
           WHERE  b1.name = 'global cache current block receive time'
           AND    b2.name = 'global cache current blocks received'
           OR     b1.name = 'gc current block receive time'
           AND    b2.name = 'gc current blocks received')))]']]
    },'-',{[[
       q'[/*grid={topic="GLOBAL CACHE LOCK PERFORMANCE"}*/
        SELECT * FROM TABLE(GV$(CURSOR(
           SELECT userenv('instance') inst_id,
                  (b1.value + b2.value) "GLOBAL LOCK GETS",
                  b3.value * 10000 "GLOBAL LOCK GET TIME",
                  round(b3.value / nullif(b1.value + b2.value,0) * 10000,2) "AVG TIME"
           FROM   v$sysstat b1, v$sysstat b2, v$sysstat b3
           WHERE  b1.name = 'global lock sync gets'
           AND    b2.name = 'global lock async gets'
           AND    b3.name = 'global lock get time'
           OR     b1.name = 'global enqueue gets sync'
           AND    b2.name = 'global enqueue gets async'
           AND    b3.name = 'global enqueue get time')))]']],'|',
    [[/*grid={topic="LOCK ACTIVITY"}*/
    select * from gv$lock_activity]]}
}
/*
PRO GES LOCK STATS: 
PRO ==================
SELECT * FROM TABLE(GV$(CURSOR(
    SELECT userenv('instance') inst_id,
           CASE WHEN dl.blocker>0 THEN 'BLOCKER ' END||CASE WHEN dl.blocked>0 THEN 'BLOCKED ' END typ,
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
                  dl.request_level) AS grant_level,
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
                  dl.request_level) AS request_level,
           decode(substr(dl.state, 1, 8),
                  'KJUSERGR',
                  'Granted',
                  'KJUSEROP',
                  'Opening',
                  'KJUSERCA',
                  'Canceling',
                  'KJUSERCV',
                  'Converting') AS state,
           sw.event,
           sw.seconds_in_wait sec
    FROM   v$ges_enqueue dl, v$process p, v$session s, v$session_wait sw
    WHERE  greatest(dl.blocker,dl.blocked) > 0
    AND    (dl.pid = p.spid)
    AND    (p.addr = s.paddr)
    AND    (s.sid = sw.sid))))
ORDER  BY sec DESC;*/