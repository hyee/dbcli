/*[[
Check the holder of library cache objects. Usage: @@NAME {[<sid>|<object_name>] [inst_id]} [-u] [-w]
    -u: only show locked/pin objects within current_schema
    --[[
        &FILTER:  default={1=1}, u={h.object_name||'.' like nvl('&0',sys_context('userenv','current_schema'))||'.%'}
        &FILTER2: default={1=1}, w={w.sid is not null}
        @CHECK_ACCESS: gv$libcache_locks={gv$libcache_locks},Dba_Kgllock={(SELECT NULL inst_id,KGLLKTYPE TYPE,KGLLKUSE HOLDING_USER_SESSION,KGLLKHDL OBJECT_HANDLE,KGLLKMOD MODE_HELD,KGLLKREQ MODE_REQUESTED FROM Dba_Kgllock)}
        @OBJ_CACHE: 12.1={(select owner to_owner,name to_name,addr to_address from v$db_object_cache)} default={v$object_dependency} 
    --]]    
]]*/
set feed off verify on
var cur refcursor;
begin
    if dbms_db_version.version>10 then
        open :cur for q'{
            WITH LP AS (
                SELECT * FROM TABLE(gv$(CURSOR(
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
                    AND    nvl(upper(:1),'0') in(''||h.sid,'0',d.to_name)))))
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
            WHERE (:1 IS NOT NULL OR w.session# IS NOT NULL)
            AND    h.type='HOLD'
            AND   nvl(:2,0) IN (h.inst_id,w.inst_id,0)
            AND  (&filter) AND (&FILTER2)
            AND   h.type = 'HOLD' 
            ORDER BY object_name,holding_session,waiting_session
        }' USING :V1,:V1, regexp_substr(:V2,'^\d+$')+0;
    ELSE
        open :cur for 
            WITH sess as(select /*+materialize*/ * from gv$session),
            lp AS(SELECT /*+materialize no_expand ordered no_merge(d) no_merge(l) use_hash(l h d)*/DISTINCT 
                        l.type lock_type, OBJECT_HANDLE handler,
                        CASE WHEN MODE_REQUESTED > 1 THEN 'WAIT' ELSE 'HOLD' END TYPE, 
                        DECODE(GREATEST(MODE_REQUESTED, MODE_HELD), 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE') lock_mode,
                        nullif(d.to_owner || '.', '.') || d.to_name object_name, 
                        h.sid || ',' || h.serial# || ',@' || h.inst_id session#, 
                        h.event, h.inst_id,h.sid,d.to_name obj
                  FROM  ((select * from &CHECK_ACCESS where greatest(MODE_HELD,MODE_REQUESTED) > 1) l JOIN sess h ON (l.HOLDING_USER_SESSION = h.saddr and (l.inst_id is null or l.inst_id=h.inst_id))) 
                  LEFT  JOIN (select distinct to_address,to_owner,to_name,inst_id from gv$object_dependency where to_name is not null) d 
                  ON    (l.OBJECT_HANDLE = d.to_address AND h.inst_id = d.inst_id))
            SELECT /*+no_expand*/
                   h.lock_type, nvl(h.object_name,'Handler: '||h.handler) object_name, 
                   h.session# holding_session, h.lock_mode hold_mode, 
                   w.session# waiting_session, w.lock_mode wait_mode,
                   w.event wait_event
            FROM   lp h LEFT JOIN lp w
             ON    h.lock_type = w.lock_type and w.type      = 'WAIT' and
                  ((h.inst_id  = w.inst_id and h.handler     = w.handler) or
                   (h.inst_id != w.inst_id and h.object_name = w.object_name))
            WHERE nvl(upper(:V1),'0') in(''||h.sid,''||w.sid,'0',h.obj)
            AND   NVL(:V2,0) IN (h.inst_id,w.inst_id,0)
            AND   (:V1 IS NOT NULL OR h.object_name not like 'SYS%.') 
            AND   (&filter) and (&filter2)
            AND    h.type = 'HOLD' 
            ORDER  BY object_name,holding_session,waiting_session;
    end if;
end;
/