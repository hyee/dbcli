/*[[Show latch objects in object cache. Usage: @@NAME [<object_name>|<sid>] [instance] 
  --[[
        &V2: default={&instance}
  --]]
]]*/
SELECT * FROM table(gv$(cursor(
	SELECT /*+swap_join_inputs(c) swap_join_inputs(d) use_hash(a b c d) no_merge(c)*/
	       a.addr, a.name latch_name, b.locks, b.pins, b.lock_mode, b.pin_mode, 
	       nvl2(c.sid,c.sid||'@'||userenv('instance'),'') holder_sid, 
	       nvl2(d.sid,d.sid||'@'||userenv('instance'),'') waiter_sid, 
	       d.sql_id waiter_sql_id,
	       d.event waiter_event, b.type,trim('.' from b.owner||'.'||b.name) name
	FROM   v$latch_children a, v$db_object_cache b, v$latchholder c, v$session d
	WHERE  a.child# = b.child_latch(+)
	AND    a.addr = c.laddr(+)
	AND    a.addr = d.p1raw(+)
	AND    d.p1text(+)='address'
	AND    a.child# > 0
	AND    userenv('instance')=nvl(:V2,userenv('instance'))
	AND    (
		(:V1 IS NULL AND NVL(c.sid, d.sid) IS NOT NULL) or
		(upper(:V1) IN (''||d.sid,''||c.sid,B.NAME,trim('.' from b.owner||'.'||b.name)))
	)
)))