/*[[
Check the holder of library cache objects. Usage: @@NAME {[<sid>|<object_name>] [inst_id]} [-u] [-w]
    -u: only show locked/pin objects within current_schema
    --[[
        &FILTER:  default={1=1}, u={h.object_name||'.' like nvl('&0',sys_context('userenv','current_schema'))||'.%'}
        &FILTER2: default={1=1}, w={w.sid is not null}
        @CHECK_ACCESS: gv$libcache_locks={gv$libcache_locks},Dba_Kgllock={(SELECT NULL inst_id,KGLLKTYPE TYPE,KGLLKUSE HOLDING_USER_SESSION,KGLLKHDL OBJECT_HANDLE,KGLLKMOD MODE_HELD,KGLLKREQ MODE_REQUESTED FROM Dba_Kgllock)}
    --]]    
]]*/
set feed off verify on
var cur refcursor;
begin
    if dbms_db_version.version>10 then
        open :cur for q'{
            WITH LP AS (
                SELECT * FROM TABLE(gv$(CURSOR(
                    SELECT /*+ordered*/DISTINCT 
                             l.type lock_type,
                             OBJECT_HANDLE handler,
                             CASE WHEN MODE_REQUESTED > 1 THEN 'WAIT' ELSE 'HOLD' END TYPE,
                             DECODE(GREATEST(MODE_REQUESTED, MODE_HELD), 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE') lock_mode,
                             nullif(d.to_owner || '.', '.') || d.to_name object_name,
                             h.sid || ',' || h.serial# || ',@' || USERENV('instance') session#,
                             h.event,
                             h.sid,d.to_name obj, USERENV('instance') inst_id
                    FROM   v$object_dependency d
                    JOIN   (SELECT KGLLKTYPE TYPE,
                                   KGLLKUSE  HOLDING_USER_SESSION,
                                   KGLLKHDL  OBJECT_HANDLE,
                                   KGLLKMOD  MODE_HELD,
                                   KGLLKREQ  MODE_REQUESTED
                            FROM   Dba_Kgllock) l
                    ON     l.object_handle = d.to_address
                    JOIN   v$session h
                    ON     l.holding_user_session = h.saddr
                    WHERE  greatest(mode_held, mode_requested) > 1))))
            SELECT /*+no_expand*/
                   h.lock_type, nvl(h.object_name,'Handler: '||h.handler) object_name, 
                   h.session# holding_session, h.lock_mode hold_mode, 
                   w.session# waiting_session, w.lock_mode wait_mode,
                   w.event wait_event
            FROM   lp h LEFT JOIN lp w
            ON    (h.lock_type = w.lock_type AND w.type = 'WAIT' AND
                  (h.object_name = w.object_name OR nvl(h.object_name, w.object_name) IS NULL AND h.inst_id = w.inst_id AND h.handler = w.handler))
            WHERE nvl(''||:1,'0') in(''||h.sid,''||w.sid,'0',h.obj)
            AND   nvl(:2,0) IN (h.inst_id,w.inst_id,0)
            AND  (&filter) AND (&FILTER2)
            AND   h.type = 'HOLD' 
            ORDER BY object_name,holding_session,waiting_session
        }' USING :V1, regexp_substr(:V2,'^\d+$')+0;
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
            ON    (h.lock_type = w.lock_type AND w.type = 'WAIT' AND
                  (h.object_name = w.object_name OR nvl(h.object_name, w.object_name) IS NULL AND h.inst_id = w.inst_id AND h.handler = w.handler))
            WHERE nvl(''||:V1,'0') in(''||h.sid,''||w.sid,'0',h.obj)
            AND   NVL(:V2,0) IN (h.inst_id,w.inst_id,0)
            AND   (&filter) and (&filter2)
            AND    h.type = 'HOLD' 
            ORDER  BY object_name,holding_session,waiting_session;
    end if;
end;
/