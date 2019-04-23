/*[[Summarize the global enqueue locks. Usage: @@NAME <instance>]]*/
SELECT TYPE, nvl(GRANT_LVL, '--TOTAL--') GRANT_LVL, REQ_LVL, LOCK_STATE, SUM(blocked) blockeds, SUM(blocker) blockers, SUM(cnt) cnt
FROM   (SELECT regexp_substr(resource_name2, '[^,]+', 1, 3) TYPE,
               decode(substr(grant_level, 1, 8),
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
                      grant_level) AS GRANT_LVL,
               decode(substr(request_level, 1, 8),
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
                      request_level) AS REQ_LVL,
               decode(substr(state, 1, 8), 'KJUSERGR', 'Granted', 'KJUSEROP', 'Opening', 'KJUSERCA', 'Cancelling', 'KJUSERCV', 'Converting', state) AS LOCK_STATE,
               SUM(decode(blocked, 0, 0, 1)) blocked,
               SUM(decode(blocker, 0, 0, 1)) blocker,
               COUNT(1) cnt
        FROM   v$ges_enqueue
        WHERE  resource_name2 NOT LIKE '%BL'
        AND    USERENV('instance')=coalesce(0+:V1,0+:instance,USERENV('instance'))
        GROUP  BY regexp_substr(resource_name2, '[^,]+', 1, 3), grant_level, request_level, state) a
GROUP  BY TYPE, ROLLUP((GRANT_LVL, REQ_LVL, LOCK_STATE))
order by nvl2(a.GRANT_LVL,2,1), cnt desc;
