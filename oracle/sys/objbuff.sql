/*[[
    Get the buffer cache info for a specific object. Usage: @@NAME [owner.]<table|index>[.<partition>] [inst]
    Source table is x$bh, also available at X$KCBOQH where num_buf=number of scur
]]*/

ora _find_object &V1
select /*+leading(b) use_hash(a)*/ 
      inst,
      nvl(a.status,'-total-') status,
      count(1) blocks,
      SUM(tch) touchs,
      COUNT(decode(CUR,'Y',1)) cur,
      COUNT(decode(DIRTY,'Y',1)) DIRTIES,
      COUNT(decode(TEMP,'Y',1)) TEMPS,
      COUNT(decode(PING,'Y',1)) PINGS,
      COUNT(decode(STALE,'Y',1)) STALES,
      COUNT(decode(DIRECT,'Y',1)) DIRECTS
from dba_objects b,
     table(gv$(cursor(
        select case when :V2='0' then to_char(inst_id) else 'A' end inst,
               decode(state, 0, 'free', 1, 'xcur', 2, 'scur', 3, 'cr', 4, 'read', 5, 'mrec', 6, 'irec', 7, 'write', 8, 'pi', 9, 'memory', 10, 'mwrite', 11,
                     'donated', 12, 'protected', 13, 'securefile', 14, 'siop', 15, 'recckpt', 16, 'flashfree', 17, 'flashcur', 18, 'flashna') status,
               decode(bitand(flag, 1), 0, 'N', 'Y') dirty,
               decode(bitand(flag, 16), 0, 'N', 'Y') TEMP,
               decode(bitand(flag, 1536), 0, 'N', 'Y') PING, 
               decode(bitand(flag, 8192), 0, 'N', 'Y') CUR, 
               decode(bitand(flag, 16384), 0, 'N', 'Y') STALE, 
               decode(bitand(flag, 65536), 0, 'N', 'Y') DIRECT,
               tch,obj objd
               from x$bh a where nullif(:V2,'0') is null or inst_id=:V2))) a 
where a.objd=b.data_object_id
and   b.owner=:object_owner
and   b.object_name=:object_name
and   nvl(b.subobject_name,' ') = coalesce(:object_subname,b.subobject_name,' ')
GROUP BY GROUPING SETS((inst,a.status),inst);