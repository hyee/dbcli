/*[[Show inmemory stats. Usage: @@NAME [-u]
    --[[
        &filter: default={1=1}, u={owner=nvl('&0',sys_context('userenv','current_schema'))}
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
from  gv$inmemory_area;

SELECT inst_id,
       owner,
       segment_name,
       COUNT(1) segments,
       (SELECT COUNT(1) FROM gv$im_column_level a WHERE a.inst_id=b.inst_id AND a.owner=b.owner AND a.table_name=b.segment_name) im_cols,
       SUM(inmemory_size) im_size,
       SUM(bytes) total_size,
       round(SUM(inmemory_size)*100/nullif(SUM(bytes),0),2) "IM %",
       SUM(BYTES_NOT_POPULATED) UN_POP,
       regexp_replace(listagg(POPULATE_STATUS,'/') WITHIN GROUP(ORDER BY POPULATE_STATUS),'([^/]+)(/\1)+','\1') im_status,
       regexp_replace(listagg(inmemory_priority,'/') WITHIN GROUP(ORDER BY inmemory_priority),'([^/]+)(/\1)+','\1') im_priority,
       regexp_replace(listagg(INMEMORY_DISTRIBUTE,'/') WITHIN GROUP(ORDER BY INMEMORY_DISTRIBUTE),'([^/]+)(/\1)+','\1') IM_DISTRIBUTE,
       regexp_replace(listagg(INMEMORY_DUPLICATE,'/') WITHIN GROUP(ORDER BY INMEMORY_DUPLICATE),'([^/]+)(/\1)+','\1') im_DUPLICATE,
       regexp_replace(listagg(INMEMORY_COMPRESSION,'/') WITHIN GROUP(ORDER BY INMEMORY_COMPRESSION),'([^/]+)(/\1)+','\1') Im_COMPRESSION
       &ver
FROM   gv$im_segments b
GROUP BY inst_id,
       owner,
       segment_name
order by im_size desc;
