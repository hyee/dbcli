/*[[Check un-aligned tablespaces and extents that not uses 256K aligned, which could cause ORA-8103 error on HCC table
    Bug# 33384137/32838533
    Parameters db_lost_write_protect(typical)/_dbg_scan(128)
]]*/

/*
 A tablespace has multiple datafiles, some of which are marked as 256K 
 aligned and some of which are not. There are segments in this tablespace
 which have the segment header in an aligned datafile, but some 
 subsequent extents are in datafiles not marked as aligned. 

 tablespace with uniform size <8M could also lead to this issue for the segment with large extent enabled. 
 */

/*
FLAG:
1:RELOAD 2:INIT 4:FUTS  8:256K_ALIGNED 16:IGN
If flag includes 8 but extents don't then could cause ORA-8103 error
 */

findobj "&V1" 1 1
SET FEED OFF VERIFY OFF
VAR CUR1 REFCURSOR "List of tablespaces that un-aligned to 256K"
VAR CUR2 REFCURSOR "List of segments that LARGE_EXTENT_ENABLED"
col ALLOCATED_SPACE,FILE_SIZE,FILE_MAXSIZE for kmg
DECLARE
    own VARCHAR2(128):=:OBJECT_OWNER;
    nam VARCHAR2(128):=:OBJECT_NAME;
    sub VARCHAR2(128):=:OBJECT_SUBNAME;
    typ VARCHAR2(128):=:OBJECT_TYPE;
BEGIN
    IF own IS NULL THEN
        OPEN :cur1 FOR
            SELECT A.NAME,B.* FROM V$TABLESPACE A,GV$FILESPACE_USAGE B 
            WHERE BITAND(B.FLAG,8)!=8
            AND   B.TABLESPACE_ID=A.TS#;
        open :cur2 FOR
            SELECT /*+
                    opt_param('_optimizer_sortmerge_join_enabled','false') 
                     opt_param('optimizer_index_cost_adj' 1000)
                     table_stats(SYS.FILE$ set rows=100000)
                     table_stats(SYS.RECYCLEBIN$ set rows=100000)
                     table_stats(SYS.TS$ set rows=200)
                     table_stats(SYS.X$KTFBUE,scale,rows=10000 blocks=100)
                     table_stats(SYS.X$KTFBFE,scale,rows=10000 blocks=1000)
                     table_stats(SYS.SEG$ SAMPLE BLOCKS=1024) 
                     outline_leaf use_hash(t e s)
                     */
                   s.owner,
                   s.segment_name,
                   s.segment_type,
                   s.partition_name,
                   s.segment_flags,
                   e.block_id,
                   MOD(e.block_id, 262144 / t.block_size) mod_extent_start,
                   e.blocks,
                   MOD(e.blocks, 262144 / t.block_size) mod_extent_size
            FROM   sys.sys_dba_segs s, dba_extents e, dba_tablespaces t
            WHERE  bitand(segment_flags, 1073741824) = 1073741824 --LARGE_EXTENT_ENABLED
            AND    s.tablespace_name = t.tablespace_name
            AND    s.segment_name = e.segment_name
            AND    s.partition_name = e.partition_name
            AND    s.tablespace_name = e.tablespace_name
            AND    e.tablespace_name = t.tablespace_name
            AND    (MOD(e.blocks, 262144 / t.block_size) != 0 or mod(e.block_id, 262144 / t.block_size) != 0);
    ELSE
        open :cur2 FOR
            SELECT /*+table_stats(SYS.X$KTFBUE SAMPLE BLOCKS=512) table_stats(SYS.SEG$ SAMPLE BLOCKS=512) */
                   b.inst_id,
                   a.name tbs_name,
                   b.flag tbs_flag,
                   s.owner,
                   s.segment_name,
                   s.segment_type,
                   s.partition_name,
                   s.segment_flags,
                   e.block_id,
                   MOD(e.block_id, 262144 / t.block_size) mod_extent_start,
                   e.blocks,
                   MOD(e.blocks, 262144 / t.block_size) mod_extent_size
            FROM   sys.sys_dba_segs s, 
                   dba_extents e, 
                   dba_tablespaces t,
                   V$TABLESPACE A,
                   GV$FILESPACE_USAGE B
            WHERE  bitand(segment_flags, 1073741824) = 1073741824 --LARGE_EXTENT_ENABLED
            AND    s.tablespace_name = t.tablespace_name
            AND    s.segment_name = e.segment_name
            AND    nvl(s.partition_name,' ') = nvl(e.partition_name,' ')
            AND    (MOD(e.blocks, 262144 / t.block_size) != 0 or mod(e.block_id, 262144 / t.block_size) != 0)
            AND    s.owner=own
            AND    s.segment_name=nam
            AND    s.segment_type LIKE typ||'%'
            AND    nvl(s.partition_name,' ')=coalesce(sub,s.partition_name,' ')
            AND    e.owner=own
            AND    e.segment_name=nam
            AND    e.segment_type LIKE typ||'%'
            AND    nvl(e.partition_name,' ')=coalesce(sub,e.partition_name,' ')
            AND    s.tablespace_name=A.NAME
            AND    B.TABLESPACE_ID=A.TS#;
    END IF;
END;
/

print cur1;
print cur2;