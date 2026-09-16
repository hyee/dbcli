/*[[
    Show global enqueue locks
    =========================
    Show the GES enqueues(v$ges_enqueue) of the instance, joined with v$lock_type to get the id1/id2
    tag and the description of the lock type. Usage: @@NAME <sid|type|number> [instance] [-id1|-id2]

    Parameters:
    -----------
    <sid|type|number> : the value to filter on
    [instance]        : the instance number to look at, default is the connected instance
    -id1              : use this option to specify the number is id1 field
    -id2              : use this option to specify the number is id2 field

    Notes:
    ------
    - an enqueue is only listed when it is blocked or blocking, unless a value is passed
    - the type and the id1/id2 fields are all parsed out of resource_name2, whose format is
      <id1>,<id2>,<type>
    - v$lock_type is outer joined by the parsed type, so a type unknown to v$lock_type still shows
      up, with an empty id1_tag/id2_tag/description
    - the query could be very slow on a busy RAC database
    --[[
        &field: default={case when regexp_like(:V1,'^\d+$') then :V1 else regexp_substr(resource_name2,'[^,]+',1,3) end} id1={regexp_substr(resource_name2,'[^,]+',1,1)} id2={regexp_substr(resource_name2,'[^,]+',1,2)}
    --]]
]]*/
SELECT a.*, b.id1_tag, b.id2_tag, b.description
FROM   TABLE(gv$(CURSOR(
           SELECT /*+no_expand use_hash(dl s p) swap_join_inputs(s) swap_join_inputs(p)*/
                  userenv('instance') inst_id,
                  dl.owner_node owner#,
                  s.sid sid,
                  p.spid spid,
                  substr(resource_name2, instr(resource_name2, ',', 1, 3) + 1, 2) type,
                  substr(resource_name2, 1, instr(resource_name2, ',') - 1) id1,
                  substr(resource_name2, instr(resource_name2, ',') + 1, instr(resource_name2, ',', 1, 2) - instr(resource_name2, ',') - 1) id2,
                  blocked,
                  blocker,
                  decode(dl.which_queue, 0, 'NULL', 1, 'GRANTED', 'CONVERT') queue,
                  decode(substr(dl.grant_level, 1, 8),
                         'KJUSERNL', 'Null',
                         'KJUSERCR', 'Row-S (SS)',
                         'KJUSERCW', 'Row-X (SX)',
                         'KJUSERPR', 'Share',
                         'KJUSERPW', 'S/Row-X (SSX)',
                         'KJUSEREX', 'Exclusive',
                         grant_level) grant_lvl,
                  decode(substr(dl.request_level, 1, 8),
                         'KJUSERNL', 'Null',
                         'KJUSERCR', 'Row-S (SS)',
                         'KJUSERCW', 'Row-X (SX)',
                         'KJUSERPR', 'Share',
                         'KJUSERPW', 'S/Row-X (SSX)',
                         'KJUSEREX', 'Exclusive',
                         request_level) req_lvl,
                  decode(substr(dl.state, 1, 8),
                         'KJUSERGR', 'Granted',
                         'KJUSEROP', 'Opening',
                         'KJUSERCA', 'Cancelling',
                         'KJUSERCV', 'Converting',
                         dl.state) lock_state,
                  s.event event,
                  s.seconds_in_wait wait_secs
           FROM   v$ges_enqueue dl, v$process p, v$session s
           WHERE  dl.pid = p.spid
           AND    p.addr = s.paddr
           AND    userenv('instance') = coalesce(:V2, '' || :instance, '' || userenv('instance'))
           AND    (:V1 IS NULL AND greatest(blocked, blocker) > 0 OR
                   :V1 IS NOT NULL AND &field = upper(:V1) AND (substr(dl.request_level, 1, 8) != 'KJUSERNL' OR dl.which_queue > 0 OR substr(dl.grant_level, 1, 8) != 'KJUSERNL'))))) a
LEFT   JOIN v$lock_type b
ON     a.type = b.type(+)
ORDER  BY wait_secs DESC;
