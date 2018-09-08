/*[[Show inmemory stats. Usage: @@NAME [-u]
    --[[
        &filter: default={1=1}, u={owner=nvl('&0',sys_context('userenv','current_schema'))}
        @check_access_dba: dba_tab_partitions={dba_} default={all_}
        @VER: 12.2={,regexp_replace(listagg(INMEMORY_SERVICE,'/') WITHIN GROUP(ORDER BY INMEMORY_SERVICE),'([^/]+)(/\1)+','\1') IM_SERVICE}, 12.1={}
    --]]
]]*/


set feed off
col ALLOC_BYTES format kmg
col USED_BYTES format kmg
col remaining_bytes format kmg
col IM_SIZE format kmg
col total_size format kmg
col UN_POP format kmg
col "Used %" format %.2f%%
col "IM %" format %.2f%%

select INST_ID,POOL,POPULATE_STATUS, ALLOC_BYTES,USED_BYTES,
       round(USED_BYTES*100/nullif(ALLOC_BYTES,0),2) "Used %",ALLOC_BYTES-USED_BYTES remaining_bytes  
from  gv$inmemory_area
order by 1;

SELECT inst_id,
       a.owner,
       a.segment_name,
       lpad(COUNT(DISTINCT nvl(b.partition_name, b.segment_name)),4)  || '|' || MAX(segs) segments,
       nullif(lpad(trim(dbms_xplan.format_number(SUM(MEMEXTENTS))),6) || '|','|') || dbms_xplan.format_number(SUM(extents)) extents,
       lpad(trim(dbms_xplan.format_number(nvl(SUM(BLOCKSINMEM),0))),6)|| '|' || dbms_xplan.format_number(max(blocks)) blocks,
       SUM(IMCUSINMEM) "IMCUs",
       round(SUM(BLOCKSINMEM)/nullif(SUM(IMCUSINMEM),0)) "Blk/CU",
       (SELECT COUNT(1)
        FROM   gv$im_column_level c
        WHERE  c.inst_id = b.inst_id
        AND    c.owner = a.owner
        AND    c.table_name = a.segment_name) im_cols,
       SUM(inmemory_size) im_size,
       SUM(bytes) total_size,
       round(SUM(inmemory_size) * 100 / nullif(SUM(bytes), 0), 2) "IM %",
       SUM(BYTES_NOT_POPULATED) UN_POP,
       '|' "|",
       regexp_replace(listagg(INMEMORY_COMPRESSION, '/') WITHIN GROUP(ORDER BY INMEMORY_COMPRESSION),
              '([^/]+)(/\1)+','\1') IM_COMPRESSION,
       regexp_replace(listagg(POPULATE_STATUS, '/') WITHIN GROUP(ORDER BY POPULATE_STATUS), '([^/]+)(/\1)+', '\1') status,
       regexp_replace(listagg(inmemory_priority, '/') WITHIN GROUP(ORDER BY inmemory_priority), '([^/]+)(/\1)+', '\1') priority,
       regexp_replace(listagg(INMEMORY_DISTRIBUTE, '/') WITHIN GROUP(ORDER BY INMEMORY_DISTRIBUTE),
                      '([^/]+)(/\1)+',
                      '\1') DISTRIBUTE,
       regexp_replace(listagg(INMEMORY_DUPLICATE, '/') WITHIN GROUP(ORDER BY INMEMORY_DUPLICATE), '([^/]+)(/\1)+', '\1') DUPLICATE
       &ver
FROM   (SELECT owner, segment_name, COUNT(1) segs,sum(blocks) blocks
        FROM   (SELECT owner, table_name segment_name,blocks
                FROM   &check_access_dba.tables
                WHERE  inmemory = 'ENABLED'
                UNION ALL
                SELECT table_owner, table_name,blocks
                FROM   &check_access_dba.tab_partitions
                WHERE  inmemory = 'ENABLED'
                UNION ALL
                SELECT table_owner, table_name,blocks
                FROM   &check_access_dba.tab_subpartitions
                WHERE  inmemory = 'ENABLED')
        GROUP  BY owner, segment_name) a
LEFT   JOIN (SELECT b.*, BLOCKSINMEM, d.extents, MEMEXTENTS, IMCUSINMEM
             FROM   gv$im_segments b,
                    (SELECT o.owner, o.object_name, o.subobject_name, d.*
                     FROM   &check_access_dba.objects o, gv$im_segments_detail d
                     WHERE  o.object_id = d.obj) d
             WHERE  b.owner = d.owner
             AND    b.segment_name = d.object_name
             AND    b.inst_id=d.inst_id
             AND    nvl(b.partition_name, '_') = nvl(d.subobject_name, '_')) b
ON     (a.owner = b.owner AND a.segment_name = b.segment_name)
GROUP  BY inst_id, a.owner, a.segment_name
ORDER  BY im_size DESC;
