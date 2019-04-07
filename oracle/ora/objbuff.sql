/*[[
    Get the buffer cache info for a specific object. Usage: @@NAME [owner.]<table|index>[.<partition>] [inst]
    --[[
        &obj: dba_objects={dba_objects}, default={all_objects}
        @ARGS: 1
    --]]
]]*/

ora _find_object &V1
select /*+leading(b) use_hash(a)*/ 
      inst,
      nvl(a.status,'-total-') status,
      count(1) blocks,
      sum(FORCED_READS) FORCED_READS,
      sum(FORCED_WRITES) FORCED_WRITES,
      COUNT(decode(DIRTY,'Y',1)) DIRTIES,
      COUNT(decode(TEMP,'Y',1)) TEMPS,
      COUNT(decode(PING,'Y',1)) PINGS,
      COUNT(decode(STALE,'Y',1)) STALES,
      COUNT(decode(DIRECT,'Y',1)) DIRECTS
from &obj b,(select a.*,case when :V2='0' then to_char(inst_id) else 'A' end inst from gv$bh a where nullif(:V2,'0') is null or inst_id=:V2) a 
where a.objd=b.data_object_id
and   b.owner=:object_owner
and   b.object_name=:object_name
and   nvl(b.subobject_name,' ') like :object_subname||'%'
GROUP BY GROUPING SETS((inst,a.status),inst);