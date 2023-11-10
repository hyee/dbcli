/*[[
    Get the buffer cache info for a specific object. Usage: @@NAME [owner.]<table|index>[.<partition>] [0|<inst>]
]]*/

ora _find_object &V1

set feed off
PRO X$KCBOQH:
PRO =========
select inst,
       count(distinct a.obj#) segs,
       sum(NUM_BUF) scur
from dba_objects b,
     table(gv$(cursor(
        select a.*,case when :V2='0' then to_char(inst_id) else 'A' end inst 
        from sys.X$KCBOQH a 
        where (nullif(:V2,'0') is null or inst_id=:V2)
        AND   obj#=nvl(:object_data_id,obj#)
        ))) a
where a.obj#=b.data_object_id
and   b.owner=:object_owner
and   b.object_name=:object_name
and   nvl(b.subobject_name,' ') = coalesce(:object_subname,b.subobject_name,' ')
GROUP BY inst
ORDER BY 1;

PRO X$BH:
PRO =====
select /*+leading(b) use_hash(a)*/ 
      inst,
      COUNT(DISTINCT A.OBJD) SEGS,
      nvl(a.status,'-total-') status,
      SUM(blocks) blocks,
      SUM(touchs) touchs,
      SUM(CUR) cur,
      SUM(DIRTIES) DIRTIES,
      SUM(TEMPS) TEMPS,
      SUM(PINGS) PINGS,
      SUM(STALES) STALES,
      SUM(DIRECTS) DIRECTS
from dba_objects b,
     table(gv$(cursor(
        select inst,
               objd,
               status,
               count(1) blocks,
               SUM(tch) touchs,
               COUNT(decode(CUR,'Y',1)) cur,
               COUNT(decode(DIRTY,'Y',1)) DIRTIES,
               COUNT(decode(TEMP,'Y',1)) TEMPS,
               COUNT(decode(PING,'Y',1)) PINGS,
               COUNT(decode(STALE,'Y',1)) STALES,
               COUNT(decode(DIRECT,'Y',1)) DIRECTS
        FROM (
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
            from   sys.x$bh a 
            where  (nullif(:V2,'0') is null OR inst_id=:V2)
            AND   obj=nvl(:object_data_id,obj)
            )
        GROUP  BY inst,objd,status))) a 
where a.objd=b.data_object_id
and   b.owner=:object_owner
and   b.object_name=:object_name
and   nvl(b.subobject_name,' ') = coalesce(:object_subname,b.subobject_name,' ')
GROUP BY GROUPING SETS((inst,a.status),inst)
ORDER BY 1,3;