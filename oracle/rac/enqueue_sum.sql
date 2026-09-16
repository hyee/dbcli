/*[[
    Summarize the global enqueue locks
    ==================================
    Summarize the GES enqueues(v$ges_enqueue) of the instance by master node, resource type, grant
    level, request level and lock state, showing the number of blocked/blocking sessions and the
    percentage of each group, top 100. Usage: @@NAME <instance>

    Notes:
    ------
    - ROLLUP((grant_lvl, req_lvl, lock_state)) is a composite rollup, so it only produces 2
      levels: the detail rows and the total of each master#/type, the latter being labelled
      with '--TOTAL--'
    - pct is the share of the detail rows only(grouping_id = 0), so the details of all groups
      add up to 100% and each '--TOTAL--' row shows the sum of its own children
    - an empty result is normal when no enqueue exists at the moment
]]*/
COL gid NOPRINT
SELECT *
FROM   (SELECT b.*,
               round(100 * cnt / nullif(sum(case when gid = 0 then cnt end) over (), 0), 4) pct
        FROM   (SELECT master#,
                       type,
                       nvl(grant_lvl, '--TOTAL--') grant_lvl,
                       req_lvl,
                       lock_state,
                       sum(blocked) blockeds,
                       sum(blocker) blockers,
                       sum(cnt) cnt,
                       grouping_id(grant_lvl, req_lvl, lock_state) gid
                FROM   TABLE(gv$(CURSOR(
                                  SELECT owner_node master#,
                                         substr(resource_name2, instr(resource_name2, ',', 1, 2) + 1) type,
                                         decode(substr(grant_level, 1, 8),
                                                'KJUSERNL', 'Null',
                                                'KJUSERCR', 'Row-S (SS)',
                                                'KJUSERCW', 'Row-X (SX)',
                                                'KJUSERPR', 'Share',
                                                'KJUSERPW', 'S/Row-X (SSX)',
                                                'KJUSEREX', 'Exclusive',
                                                grant_level) grant_lvl,
                                         decode(substr(request_level, 1, 8),
                                                'KJUSERNL', 'Null',
                                                'KJUSERCR', 'Row-S (SS)',
                                                'KJUSERCW', 'Row-X (SX)',
                                                'KJUSERPR', 'Share',
                                                'KJUSERPW', 'S/Row-X (SSX)',
                                                'KJUSEREX', 'Exclusive',
                                                request_level) req_lvl,
                                         decode(substr(state, 1, 8), 'KJUSERGR', 'Granted', 'KJUSEROP', 'Opening', 'KJUSERCA', 'Cancelling', 'KJUSERCV', 'Converting', state) lock_state,
                                         sum(decode(blocked, 0, 0, 1)) blocked,
                                         sum(decode(blocker, 0, 0, 1)) blocker,
                                         count(1) cnt
                                  FROM   v$ges_enqueue
                                  WHERE  userenv('instance') = coalesce(0 + :V1, 0 + :instance, userenv('instance'))
                                  GROUP  BY owner_node,
                                         substr(resource_name2, instr(resource_name2, ',', 1, 2) + 1),
                                         grant_level,
                                         request_level,
                                         state))) a
                GROUP  BY master#, type, ROLLUP((grant_lvl, req_lvl, lock_state))) b
        ORDER  BY pct DESC)
WHERE  ROWNUM <= 100;
