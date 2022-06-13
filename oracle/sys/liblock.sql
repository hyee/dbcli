/*[[Library cache lock/pin holders/waiters. Usage: @@NAME [all|sid|object_name] [inst_id] [-u] [-w]
        -u: only show locked/pin objects within current_schema
        -w: only show the records that have waiters
    --[[
        @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
        @typ: 11.1={kglobtyd} default={kglobtyp}
        &V2    :  default={&instance}
        &FILTER:  default={1=1}, u={h.object_name||'.' like nvl('&0',sys_context('userenv','current_schema'))||'.%'}
        &FILTER2: default={1=1}, w={w.sid is not null}
    --]]
]]*/
WITH lp AS
 (
    SELECT /*+materialize opt_param('optimizer_dynamic_sampling' 5)*/ * 
    FROM &GV
        SELECT /*+ordered use_hash(hl h) use_nl(ho hv) no_merge(h)*/ DISTINCT 
                hl.*,
                trim('.'  from ho.kglnaown || '.' || ho.kglnaobj) object_name,
                h.sid || ',' || h.serial# || ',@' || ho.inst_id session#,
                H.sid,
                nvl(hl.sq_id,h.sql_id) sql_id,
                ho.inst_id,
                DECODE(mode_held, 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE')||'('||mode_held||')' held_mode,
                DECODE(mode_requested, 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE')||'('||mode_requested||')' req_mode,
                case when h.p1text='cache id' then (select parameter from v$rowcache where cache#=p1 and rownum<2) end cache_name,
                case when h.p3text='100*mode+namespace' then trunc(p3/power(16,8)) end object_id,
                case when h.p3text='100*mode+namespace' then nullif(trunc(mod(p3,power(16,8))/power(16,4)),0) end namespace,
                h.event  event,
                ho.&TYP object_type
        FROM   v$session h,
               (SELECT INST_ID inst,kgllkuse saddr, kgllkhdl handler, kgllkmod mode_held, kgllkreq mode_requested, 'Lock' LOCK_TYPE,KGLNAHSH,decode(KGLHDNSP,0,KGLLKSQLID) sq_id
                FROM   sys.x$kgllk
                UNION ALL
                SELECT INST_ID,kglpnuse, kglpnhdl, kglpnmod, kglpnreq, 'Pin',KGLNAHSH,null
                FROM   sys.x$kglpn) hl, 
               sys.x$kglob ho--,X$KGLCURSOR_CHILD_SQLIDPH hv
        WHERE  greatest(hl.mode_held,hl.mode_requested)>1
        AND    hl.inst=nvl(:V2,hl.inst)
        AND    nvl(upper(:V1),'0') in(''||h.sid,'0',ho.kglnaobj,NULLIF(ho.kglnaown||'.','.')||ho.kglnaobj)
        AND    hl.KGLNAHSH = ho.kglnahsh
        AND    hl.handler = ho.kglhdadr
        --AND    ho.kglnahsh=hv.kglnahsh(+)
        AND    hl.saddr = h.saddr))))
--SELECT * FROM lp
SELECT /*+no_expand*/distinct
       nvl(h.lock_type,w.lock_type) lock_type,
       nvl(h.handler,w.handler) object_handle,
       nvl(h.object_id,w.object_id) obj#,
       nvl(h.object_name,w.object_name) object_name,
       nvl(h.object_type,w.object_type) object_type,
       h.session# holder_session, nvl(h.held_mode,w.held_mode) hold_mode,  
       h.sql_id holder_sqlid,
       w.session# waiter_session, nvl(w.req_mode,h.req_mode) wait_mode,
       w.sql_id waiter_sqlid,
       coalesce(w.cache_name,h.cache_name,
               (select KGLSTDSC from sys.x$kglst where indx=nvl(w.namespace,h.namespace)),
               ''||w.namespace,''||h.namespace) namespace,
       h.event holder_event, w.event waiter_event
FROM   (select * from lp where mode_held>1) h 
FULL JOIN (select * from lp where mode_requested>1)  w
ON     h.lock_type = w.lock_type and h.object_type=w.object_type and h.mode_held>1 and w.mode_requested>1 and
      ((h.inst_id  = w.inst_id and h.handler     = w.handler) or
       (h.inst_id != w.inst_id and h.object_name = w.object_name))
WHERE  (&filter) AND (&FILTER2)
ORDER BY nvl2(waiter_session,0,1),holder_session,object_name,lock_type,waiter_session;