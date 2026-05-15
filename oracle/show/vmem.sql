/*[[Show vector index memory usage
    --[[
        @CHECK_ACCESS: {
            CDB={cdb_objects} 
            dba_objects={(select sys_context('userenv','con_id') con_id, a.* from dba_objects a)}
            default={(select sys_context('userenv','con_id') con_id, a.* from all_objects a)}
        }
    --]]
]]*/
set feed off
col ALLOC_BYTES,USED_BYTES,free_bytes,64K_POOL,1M_POOL for kmg
col used for pct2
col BASEOBJ,object_name,segtype break skip -
SELECT inst_id,con_id,
       pool,
       ALLOC_BYTES,
       USED_BYTES,
       round(USED_BYTES/nullif(ALLOC_BYTES,0),5) Used,
       ALLOC_BYTES - USED_BYTES free_bytes
FROM   gv$vector_memory_pool a
WHERE  con_id=sys_context('userenv','con_id');

WITH objs AS (
  SELECT BASEOBJ o,con_id cid,owner||'.'||object_name||nvl2(subobject_name,'['||subobject_name||']','') object_name
  FROM   (select /*+no_merge*/ distinct BASEOBJ,con_id from gv$vector_mem_segments_detail) d,
         XMLTABLE('/ROWSET/ROW' 
                passing(dbms_xmlgen.getxmltype(q'~select /*+CURSOR_SHARING_FORCE*/ owner,object_name,subobject_name from &CHECK_ACCESS where object_id=~' || d.BASEOBJ||' and con_id='||d.con_id)) 
                columns owner VARCHAR2(128),
                        object_name VARCHAR2(128), 
                        subobject_name VARCHAR2(128)) b
)
SELECT BASEOBJ,
       nvl(object_name,'--TOTAL--') object_name,
       nvl(''||inst_id,'ALL INST') inst_id,
       con_id,
       SUM(MEMEXTENTS) MEMEXTENTS,
       SUM(decode(AFFINEDBLOCKS,0,MEMBYTES)) "64K_POOL",
       SUM(decode(AFFINEDBLOCKS,0,0,MEMBYTES)) "1M_POOL",
       DECODE(MIN(CREATETIME),MAX(CREATETIME),''||MIN(CREATETIME),MIN(CREATETIME)||' ~ '||MAX(CREATETIME)) CREATETIME,
       STATUS,
       POPULATE_STATUS,
       IS_EXTERNAL
FROM   gv$vector_mem_segments_detail a
JOIN   objs o
ON     a.BASEOBJ=o.o AND a.con_id=o.cid
GROUP BY rollup(inst_id,(con_id,BASEOBJ,object_name,STATUS,POPULATE_STATUS,IS_EXTERNAL))
ORDER BY o.object_name,a.inst_id;