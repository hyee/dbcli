/*[[List cached block by a specific segment. Usage: @@NAME [<owner>.]<segment_name>
  --[[
    @GV: 11.1={TABLE(GV$(CURSOR(} default={(((}
  --]]
]]*/

ora _find_object &V1

SELECT a.owner||'.'||a.object_name||nvl2(a.subobject_name,'['||a.subobject_name||']','') object_name,
       b.objd,
       b.subcache,
       inst_id,
       SUM(blocks) blocks
FROM    dba_objects a,&gv
            SELECT bh.inst_id,
                   decode(pd.bp_id, 1, 'KEEP', 2, 'RECYCLE', 3, 'DEFAULT', 4, '2K SUBCACHE', 5, '4K SUBCACHE', 6, '8K SUBCACHE', 7, '16K SUBCACHE', 8,'32K SUBCACHE', 'UNKNOWN') subcache,
                   bh.blocks blocks,
                   bh.obj objd
            FROM   x$kcbwds ds,
                   x$kcbwbpd pd,
                   (SELECT set_ds,inst_id,obj,count(1) blocks from x$bh group by set_ds,inst_id,obj) bh
            WHERE  ds.set_id >= pd.bp_lo_sid
            AND    ds.set_id <= pd.bp_hi_sid
            AND    pd.bp_size != 0
            AND    ds.addr = bh.set_ds
            AND    ds.inst_id=bh.inst_id
            AND    pd.inst_id=bh.inst_id
            AND    ds.inst_id=nvl(:instance,ds.inst_id)
        ))) b
WHERE a.data_object_id=b.objd
AND   a.owner=:object_owner
AND   a.object_name=:object_name
GROUP BY a.owner||'.'||a.object_name,
       b.objd,
       b.subcache,
       inst_id,
       a.subobject_name
ORDER BY blocks desc;
