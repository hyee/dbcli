/*[[Show global enqueue locks, the query could be very slow. Usage: @@NAME <sid|type|number> [instance] [-id1|-id2]
    -id1: use this option to specify the number is id1 field
    -id2: use this option to specify the number is id2 field
    --[[
        &field: default={case when regexp_like(:V1,'^\d+$') then :V1 else regexp_substr(resource_name2,'[^,]+',1,3) end} id1={regexp_substr(resource_name2,'[^,]+',1,1)} id2={regexp_substr(resource_name2,'[^,]+',1,2)}
    --]]
]]*/
SELECT a.*,b.id1_tag,b.id2_tag,b.description
FROM TABLE(gv$(CURSOR(
    SELECT /*+no_expand use_hash(dl s p) swap_join_inputs(s) swap_join_inputs(p)*/
           USERENV('instance') inst_id,
           dl.owner_node owner#,
           s.SID SID,
           p.spid SPID,
           substr(resource_name2,instr(resource_name2,',',1,3)+1,2) type,
           substr(resource_name2,1,instr(resource_name2,',')-1) id1,
           substr(resource_name2,instr(resource_name2,',')+1,instr(resource_name2,',',1,2)-instr(resource_name2,',')-1) id2,
           blocked,blocker,
           decode(dl.which_queue,0,'NULL',1,'GRANTED','CONVERT') QUEUE,
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
                  grant_level) AS GRANT_LVL,
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
                  request_level) AS REQ_LVL,
           decode(substr(dl.state, 1, 8),
                  'KJUSERGR',
                  'Granted',
                  'KJUSEROP',
                  'Opening',
                  'KJUSERCA',
                  'Cancelling',
                  'KJUSERCV',
                  'Converting',
                  dl.state) AS LOCK_STATE,
           s.event EVENT,
           s.seconds_in_wait wait_secs
    FROM   v$ges_enqueue dl,v$process p,v$session s
    WHERE  dl.pid = p.spid 
    AND    p.addr = s.paddr
    AND    USERENV('instance')=coalesce(:V2,''||:instance,''||USERENV('instance'))
    AND   (:V1 IS NULL AND GREATEST(blocked,blocker)>0 OR 
           :V1 IS NOT NULL AND &field=UPPER(:V1) AND (substr(dl.request_level, 1, 8)!='KJUSERNL' or dl.which_queue>0 or substr(dl.grant_level, 1, 8)!='KJUSERNL'))
))) a
LEFT JOIN v$lock_type b ON a.type=b.type(+)
ORDER  BY wait_secs DESC;