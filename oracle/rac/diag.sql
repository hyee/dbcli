/*[[
    Diag the RAC System (Doc ID 135714.1)
    =====================================
    Show the RAC diagnostics of the instance. The grid has 4 pairs of blocks:
    1) LOCAL ENQUEUES / LATCH HOLDERS     - the blocked-blocking local enqueues, and the holders
                                            of the latches
    2) LATCH STATS / NO WAIT LATCHES      - the latches whose hit ratio is below 0.98, and the
                                            no-wait(immediate) latches below 0.99
    3) GLOBAL CACHE CR / CURRENT PERF.    - the gc cr/current block counter, receive time and the
                                            average receive time of one block
    4) GLOBAL CACHE LOCK PERF. / LOCK ACT.- the global lock get counter/time and its average, plus
                                            the gv$lock_activity of the instance

    Usage: @@NAME

    Notes:
    ------
    - v$sysstat keeps the gc/lock time counters in centiseconds, so they are multiplied by 10000
      to be shown as us by the duration format usmhd2
]]*/
SET FEED OFF
COL "AVG TIME,GCS CURRENT BLOCK RECEIVE TIME,GCS CR BLOCK RECEIVE TIME" FOR usmhd2
COL "HIT_RATIO,SLEEPS/MISS" FOR pct
COL "gets,GCS CR BLOCKS RECEIVED,GCS CURRENT BLOCKS RECEIVED" FOR tmb

grid {
    {[[q'[ /*grid={topic="LOCAL ENQUEUES"}*/
        SELECT *
        FROM   TABLE(gv$(CURSOR(
                   SELECT userenv('instance') inst_id,
                          l.sid,
                          l.addr,
                          l.type,
                          l.id1,
                          l.id2,
                          decode(l.block, 0, 'blocked', 1, 'blocking', 2, 'global') block,
                          sw.event,
                          sw.seconds_in_wait sec
                   FROM   v$lock l, v$session_wait sw
                   WHERE  (l.sid = sw.sid)
                   AND    l.block IN (0, 1))))
        ORDER  BY 1, 4]']],'|',
    [[q'[/*grid={topic="LATCH HOLDERS"}*/
        SELECT *
        FROM   TABLE(gv$(CURSOR(
                   SELECT DISTINCT userenv('instance') inst_id, s.sid, s.username, p.username os_user, lh.name
                   FROM   v$latchholder lh, v$session s, v$process p
                   WHERE  (lh.sid = s.sid)
                   AND    (s.paddr = p.addr)
                   ORDER  BY s.sid)))
        ORDER  BY 1, 2]']]
    },'-',{[[
        q'[/*grid={topic="LATCH STATS"}*/
        SELECT *
        FROM   (SELECT name latch_name,
                       sum(gets) gets,
                       round(sum(gets - misses) / nullif(sum(decode(gets, 0, 1, gets)), 0), 4) hit_ratio,
                       round(sum(sleeps) / nullif(sum(decode(misses, 0, 1, misses)), 0), 4) "SLEEPS/MISS"
                FROM   gv$latch
                WHERE  gets > 0
                GROUP  BY name)
        WHERE  hit_ratio < 0.98
        ORDER  BY hit_ratio]']],'|',
    [[q'[/*grid={topic="NO WAIT LATCHES"}*/
        SELECT *
        FROM   (SELECT name latch_name,
                       sum(immediate_gets) gets,
                       round(sum(immediate_gets) / nullif(sum(immediate_gets + immediate_misses), 0), 4) hit_ratio,
                       round(sum(sleeps) / nullif(sum(decode(immediate_misses, 0, 1, immediate_misses)), 0), 4) "SLEEPS/MISS"
                FROM   gv$latch
                WHERE  immediate_gets + immediate_misses > 0
                GROUP  BY name)
        WHERE  hit_ratio < 0.99
        ORDER  BY hit_ratio]']]
    },'-',{[[
        q'[/*grid={topic="GLOBAL CACHE CR PERFORMANCE"}*/
        SELECT *
        FROM   TABLE(gv$(CURSOR(
                   SELECT userenv('instance') inst_id,
                          b2.value "GCS CR BLOCKS RECEIVED",
                          b1.value * 10000 "GCS CR BLOCK RECEIVE TIME",
                          round((b1.value / nullif(b2.value, 0)) * 10000, 2) "AVG TIME"
                   FROM   v$sysstat b1, v$sysstat b2
                   WHERE  b1.name = 'global cache cr block receive time'
                   AND    b2.name = 'global cache cr blocks received'
                   OR     b1.name = 'gc cr block receive time'
                   AND    b2.name = 'gc cr blocks received')))]']],'|',
    [[q'[/*grid={topic="GLOBAL CACHE CURRENT PERFORMANCE"}*/
        SELECT *
        FROM   TABLE(gv$(CURSOR(
                   SELECT userenv('instance') inst_id,
                          b2.value "GCS CURRENT BLOCKS RECEIVED",
                          b1.value * 10000 "GCS CURRENT BLOCK RECEIVE TIME",
                          round((b1.value / nullif(b2.value, 0)) * 10000, 2) "AVG TIME"
                   FROM   v$sysstat b1, v$sysstat b2
                   WHERE  b1.name = 'global cache current block receive time'
                   AND    b2.name = 'global cache current blocks received'
                   OR     b1.name = 'gc current block receive time'
                   AND    b2.name = 'gc current blocks received')))]']]
    },'-',{[[
        q'[/*grid={topic="GLOBAL CACHE LOCK PERFORMANCE"}*/
        SELECT *
        FROM   TABLE(gv$(CURSOR(
                   SELECT userenv('instance') inst_id,
                          (b1.value + b2.value) "GLOBAL LOCK GETS",
                          b3.value * 10000 "GLOBAL LOCK GET TIME",
                          round(b3.value / nullif(b1.value + b2.value, 0) * 10000, 2) "AVG TIME"
                   FROM   v$sysstat b1, v$sysstat b2, v$sysstat b3
                   WHERE  b1.name = 'global lock sync gets'
                   AND    b2.name = 'global lock async gets'
                   AND    b3.name = 'global lock get time'
                   OR     b1.name = 'global enqueue gets sync'
                   AND    b2.name = 'global enqueue gets async'
                   AND    b3.name = 'global enqueue get time')))]']],'|',
    [[/*grid={topic="LOCK ACTIVITY"}*/
        SELECT * FROM gv$lock_activity]]}
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
