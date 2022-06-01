/*[[Show inmemory stats. Usage: @@NAME [-u]
    --[[
        &filter: default={1=1}, u={owner=nvl('&0',sys_context('userenv','current_schema'))}
        @check_access_dba: dba_tab_partitions={dba_} default={all_}
        @VER: 12.2={,regexp_replace(listagg(INMEMORY_SERVICE,'/') WITHIN GROUP(ORDER BY INMEMORY_SERVICE),'([^/]+)(/\1)+','\1') IM_SERVICE}, 12.1={}
        @VER1: 12.2={,INMEMORY_SERVICE} default={}
        @check_access_x: {
            x$imcsegments={SELECT INST_ID,
                       NVL(UNAME, 'SYS') OWNER,
                       ONAME SEGMENT_NAME,
                       SNAME PARTITION_NAME,
                       decode(OBJTYPE, 2, 'TABLE', 19, 'TABLE PARTITION', 34, 'TABLE SUBPARTITION') SEGMENT_TYPE,
                       tsname TABLESPACE_NAME,
                       membytes INMEMORY_SIZE,
                       databytes BYTES,
                       DATABYTES - BYTESINMEM BYTES_NOT_POPULATED,
                       CASE
                           WHEN (POPULATE_STATUS = 0) THEN
                            'COMPLETED'
                           WHEN (POPULATE_STATUS = 1) THEN
                            'STARTED'
                           WHEN (POPULATE_STATUS = 2) THEN
                            'OUT OF MEMORY'
                           ELSE
                            NULL
                       END POPULATE_STATUS,
                       decode(bitand(segflag, 4294967296),
                              4294967296,
                              decode(bitand(segflag, 34359738368),
                                     34359738368,
                                     decode(bitand(segflag, 61572651155456),
                                            8796093022208,
                                            'LOW',
                                            17592186044416,
                                            'MEDIUM',
                                            35184372088832,
                                            'HIGH',
                                            52776558133248,
                                            'CRITICAL',
                                            'NONE'),
                                     'NONE'),
                              NULL) INMEMORY_PRIORITY,
                       decode(bitand(segflag, 4294967296),
                              4294967296,
                              decode(bitand(segflag, 8589934592),
                                     8589934592,
                                     decode(bitand(segflag, 206158430208),
                                            68719476736,
                                            'BY ROWID RANGE',
                                            137438953472,
                                            'BY PARTITION',
                                            206158430208,
                                            'BY SUBPARTITION',
                                            0,
                                            'AUTO'),
                                     'UNKNOWN'),
                              NULL) INMEMORY_DISTRIBUTE,
                       decode(bitand(imcs.segflag, 4294967296),
                              4294967296,
                              decode(bitand(imcs.segflag, 6597069766656),
                                     2199023255552,'NO DUPLICATE',
                                     4398046511104,'DUPLICATE',
                                     6597069766656,'DUPLICATE ALL',
                                     'UNKNOWN'),
                              NULL) INMEMORY_DUPLICATE,
                       decode(bitand(imcs.segflag, 4294967296),
                              4294967296,
                              decode(bitand(imcs.segflag, 841813590016),
                                     17179869184,'NO MEMCOMPRESS',
                                     274877906944,'FOR DML',
                                     292057776128,'FOR QUERY LOW',
                                     549755813888,'FOR QUERY HIGH',
                                     566935683072,'FOR CAPACITY LOW',
                                     824633720832,'FOR CAPACITY HIGH',
                                     'UNKNOWN'),
                              NULL) INMEMORY_COMPRESSION,
                       decode(bitand(imcs.segflag, 4294967296),
                              4294967296,
                              decode(bitand(imcs.segflag, 9007199254740992),
                                     9007199254740992,
                                     decode(bitand(imcs.svcflag, 7),
                                            0,NULL,
                                            1,'DEFAULT',
                                            2,'NONE',
                                            3,'ALL',
                                            4,'USER_DEFINED',
                                            'UNKNOWN'),
                                     'DEFAULT'),
                              NULL) INMEMORY_SERVICE,
                       decode(bitand(imcs.segflag, 4294967296),
                              4294967296,
                              decode(bitand(imcs.svcflag, 7), 4, imcs.svcname, NULL),
                              NULL) INMEMORY_SERVICE_NAME,
                       imcs.con_id,
                       BLOCKSINMEM,
                       extents,
                       MEMEXTENTS,
                       IMCUSINMEM,
                       BLOCKS
                FROM   gv$(cursor(select * from x$imcsegments)) imcs
                WHERE  imcs.segtype = 0}
                
            default={SELECT b.*, BLOCKSINMEM, d.extents, MEMEXTENTS, IMCUSINMEM,BLOCKS
                     FROM   gv$im_segments b,
                            (SELECT o.owner, o.object_name, o.subobject_name, d.*
                             FROM   &check_access_dba.objects o, gv$im_segments_detail d
                             WHERE  o.object_id = d.obj) d
                     WHERE  b.owner = d.owner
                     AND    b.segment_name = d.object_name
                     AND    b.inst_id=d.inst_id
                     AND    nvl(b.partition_name, '_') = nvl(d.subobject_name, '_')}
        }
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

SELECT /*+monitor no_merge(a)*/ inst_id,
       a.owner,
       a.segment_name,
       lpad(nvl(sum(b.segs),0),4)  || '|' || MAX(a.segs) segments,
       nullif(lpad(trim(dbms_xplan.format_number(SUM(MEMEXTENTS))),6) || '|','|') || dbms_xplan.format_number(SUM(extents)) extents,
       lpad(trim(dbms_xplan.format_number(nvl(SUM(BLOCKSINMEM),0))),6)|| '|' || dbms_xplan.format_number(SUM(blocks)) blocks,
       SUM(IMCUSINMEM) "IMCUs",
       round(SUM(BLOCKSINMEM)/nullif(SUM(IMCUSINMEM),0)) "Blk/CU",
       (SELECT COUNT(1)
        FROM   gv$im_column_level c
        WHERE  c.inst_id = b.inst_id
        AND    c.owner = a.owner
        AND    c.inmemory_compression!='NO INMEMORY'
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
FROM   (SELECT owner, segment_name, COUNT(1) segs
        FROM   (SELECT owner, table_name segment_name
                FROM   &check_access_dba.tables
                WHERE  inmemory = 'ENABLED'
                UNION ALL
                SELECT table_owner, table_name
                FROM   &check_access_dba.tab_partitions
                WHERE  inmemory = 'ENABLED'
                UNION ALL
                SELECT table_owner, table_name
                FROM   &check_access_dba.tab_subpartitions
                WHERE  inmemory = 'ENABLED')
        GROUP  BY owner, segment_name) a
LEFT   JOIN (
    SELECT inst_id,owner,segment_name,
           INMEMORY_COMPRESSION,POPULATE_STATUS,inmemory_priority,INMEMORY_DISTRIBUTE,INMEMORY_DUPLICATE &ver1,
           COUNT(DISTINCT nvl(b.partition_name, b.segment_name)) segs,
           SUM(MEMEXTENTS) MEMEXTENTS,
           SUM(extents) extents,
           SUM(BLOCKSINMEM) BLOCKSINMEM,
           SUM(blocks) blocks,
           SUM(IMCUSINMEM) IMCUSINMEM,
           SUM(inmemory_size) inmemory_size,
           SUM(bytes) bytes,
           SUM(BYTES_NOT_POPULATED) BYTES_NOT_POPULATED
    from  (&check_access_x) b
    group  by inst_id,owner,segment_name,
              INMEMORY_COMPRESSION,POPULATE_STATUS,inmemory_priority,INMEMORY_DISTRIBUTE,INMEMORY_DUPLICATE &ver1
) b
ON     (a.owner = b.owner AND a.segment_name = b.segment_name)
GROUP  BY inst_id, a.owner, a.segment_name
ORDER  BY a.owner, a.segment_name,inst_id
