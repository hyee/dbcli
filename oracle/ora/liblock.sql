/*[[
Check the holder of library cache objects. Usage: @@NAME {[<sid>|<object_name>] [inst_id]} [-u] [-w]
    -u: only show locked/pin objects within current_schema
    --[[
        &FILTER: default={1=1}, u={h.object_name||'.' like nvl('&0',sys_context('userenv','current_schema'))||'.%'}
        &FILTER2: default={1=1), w={w.sid is not null}
        @CHECK_ACCESS: gv$libcache_locks={gv$libcache_locks},Dba_Kgllock={(SELECT NULL inst_id,KGLLKTYPE TYPE,KGLLKUSE HOLDING_USER_SESSION,KGLLKHDL OBJECT_HANDLE,KGLLKMOD MODE_HELD,KGLLKREQ MODE_REQUESTED FROM Dba_Kgllock)}
    --]]    
]]*/
WITH sess as(select /*+materialize*/ * from gv$session),
lp AS(SELECT /*+materialize no_expand ordered no_merge(d) no_merge(l) use_hash(l h d)*/DISTINCT 
            l.type lock_type, OBJECT_HANDLE handler,
            CASE WHEN MODE_REQUESTED > 1 THEN 'WAIT' ELSE 'HOLD' END TYPE, 
            DECODE(GREATEST(MODE_REQUESTED, MODE_HELD), 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE') lock_mode,
            nullif(d.to_owner || '.', '.') || d.to_name object_name, h.sid || ',' || h.serial# || ',@' || h.inst_id session#, h.event, h.inst_id,h.sid
      FROM  ((select * from &CHECK_ACCESS where greatest(MODE_HELD,MODE_REQUESTED) > 1) l JOIN sess h ON (l.HOLDING_USER_SESSION = h.saddr and (l.inst_id is null or l.inst_id=h.inst_id))) 
      LEFT  JOIN (select distinct to_address,to_owner,to_name,inst_id from gv$object_dependency where to_name is not null) d 
      ON    (l.OBJECT_HANDLE = d.to_address AND h.inst_id = d.inst_id))
SELECT /*+no_expand*/
       h.lock_type, nvl(h.object_name,'Handler: '||h.handler) object_name, h.session# holding_session, h.lock_mode hold_mode, w.session# waiting_session, w.lock_mode wait_mode,
       w.event wait_event
FROM   lp h LEFT JOIN lp w
ON    (h.lock_type = w.lock_type AND w.type = 'WAIT' AND
      (h.object_name = w.object_name OR nvl(h.object_name, w.object_name) IS NULL AND h.inst_id = w.inst_id AND h.handler = w.handler))
WHERE (:V2 IS NULL OR :V2=h.inst_id OR :V2=w.inst_id)
AND   h.object_name like upper('%sys%')
AND   (&filter) and (&filter2)
AND    h.type = 'HOLD' 
ORDER  BY object_name,holding_session,waiting_session