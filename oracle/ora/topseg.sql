/*[[Show top segments, default sort by logical reads. Usage: @@NAME {[-u|<owner>|<object_name>[.<partition_name>]]] [<sort_by_field>]} [-a] [-d]
    Options:
        -d      :  Show the detail segment, instead of grouping by object name
        -u      :  Only show the segment statistics of current schema
        -a      :  Group the segments  by schema
    Tips:
        The query is based on GV$SEGMENT_STATISTICS which can be very slow. Use 'set instance' to limit the target instance.
    --[[
        &cols   : default={object_name,regexp_substr(object_type,'^[^ ]+')}, d={object_name,subobject_name,object_type}, a={'ALL'}
        &V2     : default={logi_reads}
        &Filter : default={instr('.'||owner||'.'||object_name||'.'||subobject_name||'.',upper('.'||:V1||'.'))>0}, u={owner=nvl('&0',sys_context('userenv','current_schema'))}
    --]]
]]*/
set rownum on sqltimeout 1800
SELECT /*+NO_EXPAND MONITOR opt_param('_optimizer_sortmerge_join_enabled','false') */ 
       min(obj#) obj#,owner,  &cols object_type,
       SUM(DECODE(statistic_name, 'logical reads', VALUE)) logi_reads,
       SUM(DECODE(statistic_name, 'physical reads', VALUE)) phy_reads,
       SUM(DECODE(statistic_name, 'physical writes', VALUE)) phy_writes,
       SUM(DECODE(statistic_name, 'physical reads direct', VALUE)) direct_reads,
       SUM(DECODE(statistic_name, 'physical writes direct', VALUE)) direct_writes,
       SUM(DECODE(statistic_name, 'db block changes', VALUE)) block_chgs,
       SUM(DECODE(statistic_name, 'buffer busy waits', VALUE)) busy_waits,
       SUM(DECODE(statistic_name, 'ITL waits', VALUE)) itl_waits,
       SUM(DECODE(statistic_name, 'gc cr blocks received', VALUE)) gc_cr_blocks,
       SUM(DECODE(statistic_name, 'gc current blocks received', VALUE)) gc_cu_blocks
FROM   GV$SEGMENT_STATISTICS
WHERE  (:V1 is null OR (&filter))
GROUP  BY owner,  &cols
ORDER  BY &V2 DESC