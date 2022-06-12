/*[[
    Show top segments, default sort by logical reads. Usage: @@NAME {[-u|<owner>|<object_name>[.<partition_name>]]] [<sort_by_field>]} [-a] [-d]
    Options:
        -d      :  Show the detail segment, instead of grouping by object name
        -u      :  Only show the segment statistics of current schema
        -a      :  Group the segments  by schema
    Tips:
        The query is based on GV$SEGMENT_STATISTICS which can be very slow. Use 'set instance' to limit the target instance.

    Sample Output:
    =============
    #   OBJ#   OWNER           OBJECT_NAME           OBJECT_TYPE LOGI_READS PHY_READS PHY_WRITES DIRECT_READS ...
    --- ------- ------ ------------------------------ ----------- ---------- --------- ---------- ------------ ...
      1      20 SYS    ICOL$                          TABLE        6,853,824   468,575         91       36,754 ...
      2       3 SYS    I_OBJ#                         INDEX        5,883,664       340          5            0 ...
      3     483 SYS    OPTSTAT_HIST_CONTROL$          TABLE        2,993,920        31          7            0 ...
      4     485 SYS    I_USER_PREFS$                  INDEX        1,496,752         6          0            0 ...
      5      18 SYS    OBJ$                           TABLE        1,384,064 1,065,667        332      187,142 ...
      6      14 SYS    SEG$                           TABLE          855,760     9,864         29          855 ...
      7     580 SYS    TABSUBPART$                    TABLE          519,008   511,360          0       11,282 ...
    ...

    --[[
        &cols   : default={object_name,regexp_substr(object_type,'^[^ ]+')}, d={object_name,subobject_name,object_type}, a={'ALL'}
        &V2     : default={logi_reads}
        &Filter : default={instr('.'||owner||'.'||object_name||'.'||subobject_name||'.',upper('.'||:V1||'.'))>0}, u={owner=nvl('&0',sys_context('userenv','current_schema'))}
    --]]
]]*/
set rownum on sqltimeout 1800 sep4k on
SELECT * FROM (
    SELECT /*+NO_EXPAND MONITOR opt_param('optimizer_dynamic_sampling' 6) opt_param('_optimizer_sortmerge_join_enabled','false') */ 
            min(obj#) obj#,owner,  &cols object_type,
            SUM(DECODE(statistic_name, 'space used', VALUE)) space,
            SUM(DECODE(statistic_name, 'logical reads', VALUE)) logi_reads,
            SUM(DECODE(statistic_name, 'physical reads', VALUE)) phy_reads,
            SUM(DECODE(statistic_name, 'physical writes', VALUE)) phy_writes,
            SUM(DECODE(statistic_name, 'segment scans', VALUE)) scans,
            SUM(DECODE(statistic_name, 'physical reads direct', VALUE)) dx_reads,
            SUM(DECODE(statistic_name, 'physical writes direct', VALUE)) dx_writes,
            SUM(DECODE(statistic_name, 'db block changes', VALUE)) block_chgs,
            SUM(DECODE(statistic_name, 'buffer busy waits', VALUE)) busy_waits,
            SUM(DECODE(statistic_name, 'ITL waits', VALUE)) itl_waits,
            SUM(DECODE(statistic_name, 'row lock waits', VALUE)) row_lock_waits,
            SUM(DECODE(statistic_name, 'gc buffer busy', VALUE)) gc_buff_busy,
            SUM(DECODE(statistic_name, 'gc remote grants', VALUE)) gc_grants,
            SUM(DECODE(statistic_name, 'gc cr blocks received', VALUE)) gc_cr_blocks,
            SUM(DECODE(statistic_name, 'gc current blocks received', VALUE)) gc_cu_blocks
    FROM   GV$SEGMENT_STATISTICS
    WHERE  (:V1 is null OR (&filter))
    GROUP  BY owner,  &cols
    ORDER  BY &V2 DESC)
WHERE ROWNUM<=100;