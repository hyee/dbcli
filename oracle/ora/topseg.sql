/*[[
    Show top segments, default sort by logical reads. Usage: @@NAME {[<owner>|<object_name>[.<partition_name>]] [<sort_by_field>]} [-a] [-d]
    Options:
        -d      :  Show the detail segment, instead of grouping by object name
        -u      :  Only show the segment statistics of current schema
        -a      :  Group the segments by schema
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
        &V2     : default={'0'}
        &Filter : default={UPPER('.'||owner||'.'||object_name||'.'||subobject_name||'.') LIKE upper('%&V1%')}, u={owner=nvl('&0',sys_context('userenv','current_schema'))}
        @IM     : 12.2={} default={--}
    --]]
]]*/
set rownum on sqltimeout 1800 sep4k on AUTOHIDE COL
col space for kmg
SELECT * FROM (
    SELECT /*+NO_EXPAND MONITOR opt_param('optimizer_dynamic_sampling' 6) opt_param('_optimizer_sortmerge_join_enabled','false') */ 
            min(obj#) obj#,owner,  &cols object_type,
            nullif(SUM(DECODE(statistic_name, 'space used', VALUE)),0) space,
            nullif(SUM(DECODE(statistic_name, 'logical reads', VALUE)),0) logi_reads,
            nullif(SUM(DECODE(statistic_name, 'physical reads', VALUE)),0) phy_reads,
            nullif(SUM(DECODE(statistic_name, 'physical writes', VALUE)),0) phy_writes,
            nullif(SUM(DECODE(statistic_name, 'segment scans', VALUE)),0) scans,
            &im nullif(SUM(DECODE(statistic_name, 'IM scans', VALUE)),0) IMSCANS,
            nullif(SUM(DECODE(statistic_name, 'physical reads direct', VALUE)),0) dx_reads,
            nullif(SUM(DECODE(statistic_name, 'physical writes direct', VALUE)),0) dx_writes,
            nullif(SUM(DECODE(statistic_name, 'db block changes', VALUE)),0) block_chgs,
            nullif(SUM(DECODE(statistic_name, 'buffer busy waits', VALUE)),0) busy_waits,
            nullif(SUM(DECODE(statistic_name, 'ITL waits', VALUE)),0) itl_waits,
            nullif(SUM(DECODE(statistic_name, 'row lock waits', VALUE)),0) lock_waits,
            nullif(SUM(DECODE(statistic_name, 'gc buffer busy', VALUE)),0) gc_busy,
            nullif(SUM(DECODE(statistic_name, 'gc remote grants', VALUE)),0) gc_grants,
            nullif(SUM(DECODE(statistic_name, 'gc cr blocks received', VALUE)),0) cr_blocks,
            nullif(SUM(DECODE(statistic_name, 'gc current blocks received', VALUE)),0) cu_blocks
    FROM   GV$SEGMENT_STATISTICS
    WHERE  (&filter)
    GROUP  BY owner,  &cols
    ORDER  BY  &v2 desc nulls last,nvl(logi_reads,0)/15+nvl(phy_reads,0)+nvl(phy_writes,0) DESC)
WHERE ROWNUM<=50;