/*[[
Check the holder of library cache objects, only support situation where holder and waiter are of the same instance. Usage: @@NAME [<sid>|<object_name>]
    --[[
        @CHECK_ACCESS: gv$db_object_cache/gv$object_Dependency={}
    --]]
]]*/
WITH r AS
 (SELECT /*+materialize no_expand leading(o d) use_hash(o d) use_hash(@SEL$5 o) use_hash(@SEL$3 o)*/
  DISTINCT d.*
  FROM   gv$db_object_cache o,gv$object_Dependency d
  WHERE  d.to_owner = o.owner
  AND    d.to_name = o.name
  AND    d.inst_id = o.inst_id
  AND    (:V1 IS NULL OR regexp_like(:V1,'^\d+$') or o.name=UPPER(:V1))
  AND    nvl(o.name, 'SYS') != 'SYS'
  AND    (o.locks > 0 OR o.pins > 0))
SELECT /*+ordered use_hash(r1 h w) no_merge(w) no_expand*/
       DISTINCT r1.to_owner || '.' || r1.to_name object_name,
                h.sid || ',@' || h.inst_id holder,
                h.sql_id holder_sql_id,
                NVL2(w.sid, w.sid || ',@' || w.inst_id, NULL) waiter,
                w.sql_id waiter_sql_id,
                w.event waiter_event,
                w.wait_Time wtime,
                w.seconds_in_Wait secs
FROM   r r1, gv$open_cursor h,  gv$session w
WHERE  r1.inst_id = h.inst_id
AND    r1.from_address = h.address
AND    r1.to_address=w.p1raw(+)
AND    r1.inst_id=w.inst_id(+)
AND   (UPPER(:V1) IN(''||h.sid,''||w.sid,r1.to_name) or w.sid is not null)