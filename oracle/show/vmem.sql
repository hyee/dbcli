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

var mempool refcursor;
var memsegs refcursor;
DECLARE
    mempool sys_refcursor;
    memsegs sys_refcursor;
BEGIN
    $IF dbms_db_version.version>=23 $THEN
        OPEN mempool for
            SELECT inst_id,con_id,
                   pool,
                   alloc_bytes,
                   used_bytes,
                   round(used_bytes/nullif(alloc_bytes,0),5) used,
                   alloc_bytes - used_bytes free_bytes
            FROM   gv$vector_memory_pool a
            WHERE  con_id=sys_context('userenv','con_id');
        OPEN memsegs for
            WITH objs AS (
                SELECT baseobj o,con_id cid,owner||'.'||object_name||nvl2(subobject_name,'['||subobject_name||']','') object_name
                FROM   (SELECT /*+no_merge*/ DISTINCT baseobj,con_id FROM gv$vector_mem_segments_detail) d,
                       xmltable('/ROWSET/ROW'
                              PASSING(dbms_xmlgen.getxmltype(q'~select /*+CURSOR_SHARING_FORCE*/ owner,object_name,subobject_name from &CHECK_ACCESS where object_id=~' || d.baseobj||' and con_id='||d.con_id))
                              COLUMNS owner VARCHAR2(128),
                                      object_name VARCHAR2(128),
                                      subobject_name VARCHAR2(128)) b
            )
            SELECT baseobj,
                   nvl(object_name,'--TOTAL--') object_name,
                   nvl(''||inst_id,'ALL INST') inst_id,
                   con_id,
                   sum(memextents) memextents,
                   sum(decode(affinedblocks,0,membytes)) "64K_POOL",
                   sum(decode(affinedblocks,0,0,membytes)) "1M_POOL",
                   decode(min(createtime),max(createtime),''||min(createtime),min(createtime)||' ~ '||max(createtime)) createtime,
                   status,
                   populate_status,
                   is_external
            FROM   gv$vector_mem_segments_detail a
            JOIN   objs o
            ON     a.baseobj=o.o AND a.con_id=o.cid
            GROUP  BY ROLLUP(inst_id,(con_id,baseobj,object_name,status,populate_status,is_external))
            ORDER  BY o.object_name,a.inst_id;
    $ELSE
        OPEN mempool for
            SELECT 'Vector pool statistics require Oracle Database 23ai or later.' message
            FROM   dual;
        OPEN memsegs for
            SELECT 'Vector index segment statistics require Oracle Database 23ai or later.' message
            FROM   dual;
    $END
    :mempool := mempool;
    :memsegs := memsegs;
END;
/