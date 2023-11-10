/*[[
Get the buffer cache info for a specific object. Usage: @@NAME [owner.]<table|index>[.<partition>] [inst]
inst: A to group across instance, or other values to query the specific instance

Sample Output:
==============
ORCL> ora OBJBUFF seg$
    INST STATUS  BLOCKS FORCED_READS FORCED_WRITES DIRTIES TEMPS PINGS STALES DIRECTS
    ---- ------- ------ ------------ ------------- ------- ----- ----- ------ -------
    A    cr           4            0             0       0     0     0      0       0
    A    xcur       134            0             0       0     0     0      0       0
    A    -total-    138            0             0       0     0     0      0       0
    --[[
        &obj: dba_objects={dba_objects}, default={all_objects}
        @ARGS: 1
    --]]
]]*/

ora _find_object &V1
select /*+leading(b) use_hash(a)*/ 
      inst,
      nvl(a.status,'-total-') status,
      sum(blocks) blocks,
      sum(FORCED_READS) FORCED_READS,
      sum(FORCED_WRITES) FORCED_WRITES,
      sum(DIRTIES) DIRTIES,
      sum(TEMPS) TEMPS,
      sum(PINGS) PINGS,
      sum(STALES) STALES,
      sum(DIRECTS) DIRECTS
from &obj b,table(gv$(cursor(
     select inst,status,objd,
            count(1) blocks,
            sum(FORCED_READS) FORCED_READS,
            sum(FORCED_WRITES) FORCED_WRITES,
            COUNT(decode(DIRTY,'Y',1)) DIRTIES,
            COUNT(decode(TEMP,'Y',1)) TEMPS,
            COUNT(decode(PING,'Y',1)) PINGS,
            COUNT(decode(STALE,'Y',1)) STALES,
            COUNT(decode(DIRECT,'Y',1)) DIRECTS
     from (
         select a.*,case when :V2='A' then 'A' ELSE to_char(userenv('instance')) end inst 
         from  v$bh a 
         where (nullif(:V2,'0') is null or userenv('instance')=:V2)
         and   objd=nvl(:object_data_id,objd)) 
     group by inst,status,objd))) a 
where a.objd=b.data_object_id
and   b.owner=:object_owner
and   b.object_name=:object_name
and   nvl(b.subobject_name,' ') = coalesce(:object_subname,b.subobject_name,' ')
GROUP BY GROUPING SETS((inst,a.status),inst)
ORDER BY 1,2;