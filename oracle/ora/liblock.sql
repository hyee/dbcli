/*[[
Check the holder of library cache objects. Usage: @@NAME {[<sid>|<object_name>] [inst_id]} [-u] [-w]
    -u: only show locked/pin objects within current_schema
    --[[
        &FILTER:  default={1=1}, u={h.object_name||'.' like nvl('&0',sys_context('userenv','current_schema'))||'.%'}
        &FILTER2: default={1=1}, w={w.sid is not null}
        @CHECK_ACCESS: gv$libcache_locks={gv$libcache_locks},Dba_Kgllock={(SELECT NULL inst_id,KGLLKTYPE TYPE,KGLLKUSE HOLDING_USER_SESSION,KGLLKHDL OBJECT_HANDLE,KGLLKMOD MODE_HELD,KGLLKREQ MODE_REQUESTED FROM Dba_Kgllock)}
        @OBJ_CACHE: 12.1={(select owner to_owner,name to_name,addr to_address from v$db_object_cache)} default={v$object_dependency} 
        @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
    --]]    
]]*/
set feed off verify on

WITH LP AS (
    SELECT * FROM &GV
        SELECT /*+ordered no_merge(h) use_hash(l d)*/DISTINCT 
                 l.type lock_type,
                 OBJECT_HANDLE handler,
                 CASE WHEN MODE_REQUESTED > 1 THEN 'WAIT' ELSE 'HOLD' END TYPE,
                 DECODE(GREATEST(MODE_REQUESTED, MODE_HELD), 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE') lock_mode,
                 nullif(d.to_owner || '.', '.') || d.to_name object_name,
                 h.sid || ',' || h.serial# || ',@' || USERENV('instance') session#,
                 h.event,
                 h.sql_id,
                 h.sid,d.to_name obj, USERENV('instance') inst_id
        FROM    v$session h
        JOIN   (SELECT KGLLKTYPE TYPE,
                       KGLLKUSE  HOLDING_USER_SESSION,
                       KGLLKHDL  OBJECT_HANDLE,
                       KGLLKMOD  MODE_HELD,
                       KGLLKREQ  MODE_REQUESTED
                FROM   Dba_Kgllock) l
        ON     l.holding_user_session = h.saddr
        JOIN   &OBJ_CACHE d
        ON     l.object_handle = d.to_address
        WHERE  greatest(mode_held, mode_requested) > 1
        AND    d.to_owner IS NOT NULL
        AND    userenv('instance')=nvl(:instance,userenv('instance'))
        AND    nvl(upper(:V1),'0') in(''||h.sid,'0',d.to_name,NULLIF(d.to_owner||'.','.')||d.to_name))
        )))
SELECT /*+no_expand*/distinct
       h.lock_type,h.handler object_handle, h.object_name,
       h.session# holding_session, h.lock_mode hold_mode,  
       h.event holder_event, h.sql_id holder_sql_id,
       w.session# waiting_session, w.lock_mode wait_mode,
       w.event waiter_event, w.sql_id waiter_sql_id
FROM   lp h LEFT JOIN lp w
ON     h.lock_type = w.lock_type and w.type      = 'WAIT' and
      ((h.inst_id  = w.inst_id and h.handler     = w.handler) or
       (h.inst_id != w.inst_id and h.object_name = w.object_name))
WHERE  h.type='HOLD'
AND   nvl(regexp_substr(:V2,'^\d+$')+0,0) IN (h.inst_id,w.inst_id,0)
AND  (&filter) AND (&FILTER2)
AND   h.type = 'HOLD' 
ORDER BY object_name,holding_session,waiting_session;