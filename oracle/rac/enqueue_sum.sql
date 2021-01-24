/*[[Summarize the global enqueue locks. Usage: @@NAME <instance>]]*/
SELECT * FROM (
    SELECT master#,TYPE, 
           nvl(GRANT_LVL, '--TOTAL--') GRANT_LVL, REQ_LVL, LOCK_STATE, 
           SUM(blocked) blockeds, 
           SUM(blocker) blockers, 
           SUM(cnt) cnt,
           Round(100 * ratio_to_report(SUM(cnt)) OVER(), 4) pct
    FROM   TABLE(GV$(CURSOR(
            SELECT owner_node master#,
                   substr(resource_name2,instr(resource_name2,',',1,2)+1) TYPE,
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
            WHERE  USERENV('instance')=coalesce(0+:V1,0+:instance,USERENV('instance'))
            GROUP  BY owner_node,substr(resource_name2,instr(resource_name2,',',1,2)+1), grant_level, request_level, state))) a
    GROUP  BY master#,TYPE, ROLLUP((GRANT_LVL, REQ_LVL, LOCK_STATE))
    order by pct DESC)
WHERE ROWNUM<=100;