/*[[Library cache lock/pin holders/waiters. Usage: @@NAME [all|sid|object_name] 
    --[[
        @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
        @typ: 11.1={kglobtyd} default={kglobtyp}
    --]]
]]*/
WITH ho AS
 (
    SELECT /*+materialize*/ * 
    FROM &GV
        SELECT /*+ordered use_hash(hl h) use_nl(ho hv) no_merge(h)*/ DISTINCT 
                hl.*,
                trim('.'  from ho.kglnaown || '.' || ho.kglnaobj) object_name,
                h.sid || ',' || h.serial# || ',@' || ho.inst_id holder,
                nvl(hl.sq_id,h.sql_id) sql_id,
                ho.inst_id,
                DECODE(MODE_HELD, 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE')||'('||MODE_HELD||')' held_mode,
                DECODE(MODE_REQ, 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE')||'('||MODE_REQ||')' req_mode,
                h.event  event,
                ho.&TYP kglobtyp
        FROM   v$session h,
               (SELECT INST_ID inst,kgllkuse saddr, kgllkhdl object_handle, kgllkmod mode_held, kgllkreq mode_req, 'Lock' TYPE,KGLNAHSH,decode(KGLHDNSP,0,KGLLKSQLID) sq_id
                FROM   x$kgllk
                UNION ALL
                SELECT INST_ID,KGLPNHDL, kglpnhdl, kglpnmod, kglpnreq, 'Pin',KGLNAHSH,null
                FROM   x$kglpn) hl, 
               x$kglob ho--,X$KGLCURSOR_CHILD_SQLIDPH hv
        WHERE  (hl.mode_held > 1 or hl.mode_req>1)
        AND    hl.inst=nvl(:instance,hl.inst)
        AND    nvl(upper(:V1),'_') in('ALL','_',upper(ho.kglnaobj),upper(trim('.' from ho.kglnaown ||'.' || ho.kglnaobj)),''||h.sid)
        AND    hl.KGLNAHSH = ho.kglnahsh
        AND    hl.object_handle = ho.kglhdadr
        --AND    ho.kglnahsh=hv.kglnahsh(+)
        AND    hl.saddr = h.saddr))))
SELECT /*+no_expand use_hash(ho wo)*/ distinct 
       nvl(h.type,w.type) type,
       nvl(h.object_handle,w.object_handle) object_handle, 
       nvl(h.object_name,w.object_name) object_name,
       nvl(h.kglobtyp,w.kglobtyp) object_type,
       h.holder holder,
       h.held_mode mode_held,
       h.sql_id holder_sql_id,
       h.event holder_event,
       w.holder waiter,
       w.req_mode mode_req,
       w.sql_id waiter_sql_id,
       w.event waiter_event
FROM   ho h FULL JOIN ho w 
ON     (h.type=w.type AND h.mode_held > 1 AND w.mode_req>1 and h.holder!= w.holder and h.kglobtyp=w.kglobtyp and
        ((h.inst_id = w.inst_id and h.object_handle  = w.object_handle) or
        (h.inst_id!= w.inst_id and h.object_name    = w.object_name)))
WHERE  (h.mode_held>1 or w.mode_req>1)
AND    COALESCE(:V1,w.holder) IS NOT NULL
ORDER  BY OBJECT_NAME,TYPE,WAITER,HOLDER;