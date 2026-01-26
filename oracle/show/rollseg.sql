/*[[Show Rollback Segment Usages]]*/
col "USED|BYTES,SEG|BYTES,FILE|BYTES,MAX|BYTES,INCREMENT|BYTES,Undo|Size" for kmg2
col "SEG|BLOCKS,FILE|BLOCKS,MAX|BLOCKS,SEG|EXTENTS,Undo|ROWS,Undo|BLOCKS" for TMB2
col "Used|Rate" for pct2

PRO TOP 50 SEGMENTS BY SEGMENT BYTES:
PRO =================================
SELECT * 
FROM (
    SELECT /*+OUTLINE_LEAF USE_HASH(s f e t)
            opt_param('_optimizer_sortmerge_join_enabled','false') 
            opt_param('optimizer_index_cost_adj' 1000)
            table_stats(SYS.X$KTFBFE SAMPLE BLOCKS=512)
            table_stats(SYS.X$KTFBUE SAMPLE BLOCKS=512) 
            table_stats(SYS.SEG$ SAMPLE BLOCKS=1024)*/
            segment_name "SEGMENT|NAME",
            tablespace_name "TABLESPACE|NAME",
            file_id "FILE|ID",
            relative_fno "RELATIVE|FILE#",
            s.status "SEG|STATUS",
            e.bytes "SEG|BYTES",
            e.blocks "SEG|BLOCKS",
            e.extents "SEG|EXTENTS",
            '|' "|",
            t.inst_id "Txn|Inst",
            t.xacts "Txn|Count",
            t.rssize "Undo|Size",
            t.used_urec "Undo|ROWS",
            t.used_ublk "Undo|BLOCKS",
            '||' "||",
            f.bytes "FILE|BYTES",
            e.file_bytes "USED|BYTES",
            round(e.file_bytes/f.bytes,4) "Used|Rate",
            f.autoextensible "AUTO|EXTEND",
            decode(f.autoextensible, 'YES', f.maxbytes, f.bytes) "MAX|BYTES",
            f.blocks "FILE|BLOCKS",
            decode(f.autoextensible, 'YES', f.maxblocks, f.blocks) "MAX|BLOCKS",
            decode(f.autoextensible, 'YES', f.increment_by, 0) "INCREMENT|BYTES"
    FROM (
        SELECT /*+no_merge*/
                segment_name,
                tablespace_name,
                file_id,
                relative_fno,
                SUM(bytes) bytes,
                SUM(SUM(bytes)) over (partition by tablespace_name, file_id, relative_fno) file_bytes,
                SUM(blocks) blocks,
                COUNT(file_id) extents
        FROM   dba_undo_extents
        GROUP  BY segment_name, tablespace_name, file_id, relative_fno) e
    JOIN   dba_data_files f
    USING  (tablespace_name, file_id, relative_fno)
    FULL JOIN  (select segment_name,tablespace_name,status from dba_rollback_segs) s
    USING  (segment_name, tablespace_name) 
    LEFT JOIN (
        SELECT r.inst_id,
               greatest(count(t.xidusn),max(r.xacts)) xacts,
               u.name segment_name,
               max(r.rssize) rssize,
               sum(t.used_urec) used_urec,
               sum(t.used_ublk) used_ublk 
        FROM   gv$rollstat r 
        JOIN   v$rollname u 
        ON     r.usn = u.usn
        LEFT JOIN   gv$transaction t 
        ON     t.xidusn = r.usn and t.inst_id=r.inst_id
        GROUP  BY r.inst_id,u.name) t 
    USING(segment_name)
    ORDER BY "SEG|BYTES" DESC NULLS LAST)
WHERE rownum<=50;

