/*[[Library cache lock/pin holders/waiters. Usage: @@NAME [sid|object_name] 
    --[[
        @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
    --]]
]]*/
WITH ho AS
 (
    SELECT * FROM &GV
        SELECT /*+ordered use_hash(hl ho) no_merge(h)*/ DISTINCT 
                hl.*,
                ho.kglnaown ||nullif('.' || ho.kglnaobj,'.') object_name,
                h.sid || ',' || h.serial# || ',@' || ho.inst_id holder,
                h.sql_id sql_id,
                ho.inst_id,
                DECODE(GREATEST(MODE_REQ, MODE_HELD), 1, 'NULL', 2, 'SHARED', 3, 'EXCLUSIVE', 'NONE')||'('||GREATEST(MODE_REQ, MODE_HELD)||')' lock_mode,
                h.event  event
        FROM    v$session h,
               (SELECT kgllkuse saddr, kgllkhdl object_handle, kgllkmod mode_held, kgllkreq mode_req, 'Lock' TYPE
                FROM   x$kgllk
                UNION ALL
                SELECT kglpnuse, kglpnhdl, kglpnmod, kglpnreq, 'Pin'
                FROM   x$kglpn) hl,
               x$kglob ho
        WHERE  greatest(hl.mode_held,hl.mode_req) > 1
        AND    userenv('instance')=nvl(:instance,userenv('instance'))
        AND    nvl(upper(:V1),'_') in('_',upper(ho.kglnaobj),upper(trim('.' from ho.kglnaown ||'.' || ho.kglnaobj)),''||h.sid)
        AND    hl.object_handle = ho.kglhdadr
        AND    hl.saddr = h.saddr))))
SELECT /*+no_expand use_hash(ho wo)*/ distinct 
       h.type,
       h.object_handle,
       h.object_name,
       h.holder,
       h.lock_mode mode_held,
       h.sql_id holder_sql_id,
       h.event holder_event,
       w.holder waiter,
       w.lock_mode mode_req,
       w.sql_id waiter_sql_id,
       w.event waiter_event
FROM   ho h LEFT JOIN ho w 
ON     (h.type=w.type AND w.mode_req>1 and h.holder!= w.holder and
       ((h.inst_id = w.inst_id and h.object_handle  = w.object_handle) or
        (h.inst_id!= w.inst_id and h.object_name    = w.object_name)))
WHERE  h.mode_held > 1
AND    COALESCE(:V1,w.holder) IS NOT NULL