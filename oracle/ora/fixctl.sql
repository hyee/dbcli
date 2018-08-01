/*[[Query optimizer fixed controls. Usage: @@NAME {[keyword] [sid] [inst_id]} [-f"filter"]
   --[[
       @CHECK_ACCESS_CTL: gv$session_fix_control={gv$session_fix_control}, default={(select userenv('instance') inst_id, a.* from v$session_fix_control a)}
       &FILTER: default={1=1}, f={}
   --]]
]]*/
select * from &CHECK_ACCESS_CTL
where ((:V1 IS NULL and value=0)
  or   (:V1 IS NOT NULL and lower(BUGNO||DESCRIPTION||SQL_FEATURE||event||OPTIMIZER_FEATURE_ENABLE) like lower(q'[%&V1%]')))
AND    inst_id=nvl(:V3,userenv('instance'))
and    session_id=nvl(:V2,userenv('sid')) 
AND    &filter
order by 1