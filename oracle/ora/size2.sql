/*[[
    Show object space usage and relative Exadata FlashCache size. Usage: @@NAME [owner.]object_name[.PARTITION_NAME] [-d]
    If EXA$CACHED_OBJECTS does not exist(refer to script oracle/shell/create_exa_external_tables.sh) then the relative FlashCache info will not be shown
    
    Option:
    ======
        -d    : used to detail in segment level, otherwise in object name level
        -flash: also check flashcache usage when view EXA$CACHED_OBJECTS is available

    Sample Output:
    ==============
      OBJECT_NAME      OBJECT_TYPE TABLESPACE SEGS EXTENTS  BLOCKS   BYTES    INI_EXT NEXT_EXT|FC_CELLS FC_SEGS FC_REQS FC_HIT% FC_CACHED  FC_CC% FC_WRITE FC_KEEP FC_CCKEEP
    ------------------ ----------- ---------- ---- ------- -------- -------- -------- --------+-------- ------- ------- ------- --------- ------- -------- ------- ---------
    TOTAL                          TS_SSB        7  1.01 K   8.25 M 62.94 GB 64.00 MB 64.00 MB|       6       6 51.95 K 100.00%  11.10 GB 100.00%     0  B    0  B      0  B
    SSB.LINEORDER      TABLE       TS_SSB        1   476     3.90 M 29.75 GB 64.00 MB 64.00 MB|       6       6 51.95 K 100.00%  11.10 GB 100.00%     0  B    0  B      0  B
      SSB.LINEORDER_N1 INDEX       TS_SSB        1    98   802.82 K  6.12 GB 64.00 MB 64.00 MB|
      SSB.LINEORDER_N2 INDEX       TS_SSB        1    82   671.74 K  5.12 GB 64.00 MB 64.00 MB|
      SSB.LINEORDER_N3 INDEX       TS_SSB        1    84   688.13 K  5.25 GB 64.00 MB 64.00 MB|
      SSB.LINEORDER_N4 INDEX       TS_SSB        1    82   671.74 K  5.12 GB 64.00 MB 64.00 MB|
      SSB.LINEORDER_N5 INDEX       TS_SSB        1    84   688.13 K  5.25 GB 64.00 MB 64.00 MB|
      SSB.LINEORDER_N6 INDEX       TS_SSB        1   101   827.39 K  6.31 GB 64.00 MB 64.00 MB|

    --[[
        @ARGS: 1
        &OPT2: default={}, d={1}
        @check_access_dba: dba_objects={dba_} default={_all}
        @check_access_segs: dba_segments={dba_segments} default={(select user owner,a.* from user_segments)}
        &check_access_exa1: {
          default={(select ' ' owner,' ' object_name,' ' subobject_name,' ' object_type,
                            0 object_id,
                            0 data_object_id,
                            0 cells,
                            0 pieces,
                            0 hits,
                            0 misses,
                            0 CACHEDSIZE,
                            0 cachedwrite,
                            0 columnarcache,
                            0 cachedkeep,
                            0 columnarkeep
                    from dual
                    where 1=2)},
          flash={(
                    SELECT owner, object_name, subobject_name, object_type, object_id, b.*
                    FROM   (SELECT objectnumber data_object_id,
                                   count(distinct cellnode) cells,
                                   count(1) pieces,
                                   SUM(hitcount) hits,
                                   SUM(misscount) misses,
                                   SUM(CACHEDSIZE) CACHEDSIZE,
                                   SUM(CACHEDWRITESIZE) cachedwrite,
                                   SUM(COLUMNARCACHESIZE) columnarcache,
                                   SUM(CACHEDKEEPSIZE) cachedkeep,
                                   SUM(COLUMNARKEEPSIZE) columnarkeep
                            FROM   EXA$CACHED_OBJECTS
                            WHERE  regexp_replace(upper(dbuniquename),':.*') = upper(sys_context('userenv','db_unique_name'))
                            GROUP  BY objectnumber) b,
                           &check_access_dba.objects a
                    WHERE  b.data_object_id = a.data_object_id)} 
        }
        &check_access_exa2: default={--} flash={,'|' "|",} 
    --]] 
]]*/

findobj "&V1" "" 1
COL BYTES,INI_EXT,NEXT_EXT,FC_CACHED,FC_CCCACHED,FC_WRITE,FC_KEEP,FC_CCKEEP FOR KMG
COL BLOCKS,EXTENTS,fc_reqs FOR TMB
COL "fc_hit%,fc_cc%" for pct
WITH objs AS(
    SELECT /*+ordered use_hash(objs lobs parts subs) opt_param('optimizer_dynamic_sampling' 11)*/
            objs.segment_owner,
            coalesce(subs.lob_name,parts.lob_name,lobs.segment_name,objs.segment_name) segment_name,
            coalesce(subs.lob_subpartition_name,parts.lob_partition_name,objs.partition_name) partition_name,
            objs.segment_type segment_type,
            coalesce(lobs.tablespace_name,objs.tablespace_name) tablespace_name,
            objs.lob_column_name,
            lobs.index_name index_name,
            nvl(subs.lob_indsubpart_name,parts.lob_indpart_name) index_part
    FROM    TABLE(DBMS_SPACE.OBJECT_DEPENDENT_SEGMENTS(
                '&object_owner', --objowner
                '&object_name', --objname
                NULL, --partname
                CASE regexp_substr('&object_type', '[^ ]+')
                    WHEN 'TABLE' THEN 1
                    WHEN 'TABLE PARTITION' THEN 7
                    WHEN 'TABLE SUBPARTITION' THEN 9
                    WHEN 'INDEX' THEN 3
                    WHEN 'INDEX PARTITION' THEN 8
                    WHEN 'INDEX SUBPARTITION' THEN 10
                    WHEN 'CLUSTER' THEN 4
                    WHEN 'NESTED_TABLE' THEN 2
                    WHEN 'MATERIALIZED VIEW' THEN 13
                    WHEN 'MATERIALIZED VIEW LOG' THEN 14
                    WHEN 'MATERIALIZED ZONEMAP' THEN 1
                    WHEN 'LOB' THEN 21
                    WHEN 'LOB PARTITION' THEN 40
                    WHEN 'LOB SUBPARTITION' THEN 41
                END)) objs,
           &check_access_dba.lobs lobs,
           &check_access_dba.lob_partitions parts,
           &check_access_dba.lob_subpartitions subs
    WHERE  '&object_owner' = lobs.owner(+)
    AND    '&object_name' = lobs.table_name(+)
    AND    objs.lob_column_name = lobs.column_name(+)
    AND    '&object_owner' = parts.table_owner(+)
    AND    '&object_name' = parts.table_name(+)
    AND    objs.lob_column_name = parts.column_name(+)
    AND    objs.partition_name=parts.partition_name(+)
    AND    '&object_owner' = subs.table_owner(+)
    AND    '&object_name' = subs.table_name(+)
    AND    objs.lob_column_name = subs.column_name(+)
    AND    objs.partition_name=subs.subpartition_name(+)
    AND    nvl(objs.partition_name, ' ') LIKE :object_subname || '%')
SELECT nvl(decode(lv, null,'', 1, '', '  ') || object_name,'--TOTAL--') object_name,
       object_type,
       max(TABLESPACE) keep(dense_rank last order by bytes) TABLESPACE,
       MAX(segment_subtype) keep(dense_rank last order by bytes) tbstype,
       COUNT(1) segs,
       SUM(extents) extents,
       SUM(blocks) blocks,
       SUM(BYTES) BYTES,
       MAX(INI_EXT) INI_EXT,
       MAX(NEXT_EXT) NEXT_EXT
       &check_access_exa2 max(cells) fc_cells,sum(pieces) fc_segs,sum(hits+misses) fc_reqs,sum(hits)/nullif(sum(hits+misses),0) "FC_HIT%",sum(cachedsize) fc_cached,sum(columnarcache)/nullif(sum(cachedsize),0) "FC_CC%",sum(cachedwrite) fc_write,sum(cachedkeep) FC_KEEP,sum(columnarkeep) FC_CCKEEP
FROM   (SELECT /*+ordered use_hash(segs objs) use_hash(exa) no_merge(objs) NO_EXPAND_GSET_TO_UNION*/
        DISTINCT decode('&object_name'||:OPT2, objs.segment_name, 1, 2) lv,
                 NVL2(objs.lob_column_name,'['||objs.lob_column_name||'] ','')||objs.segment_owner || '.' || objs.segment_name || 
                 decode(:object_subname||:OPT2, '', '', nvl2(objs.partition_name, '.' || objs.partition_name, '')) object_name,
                 trim('%' from decode(:object_subname||:OPT2, '', regexp_substr(nvl(segs.segment_type,objs.segment_type), '^\S+'), nvl(segs.segment_type,objs.segment_type))) object_type,
                 nvl(segs.TABLESPACE_NAME,objs.TABLESPACE_NAME) TABLESPACE,
                 nvl(segs.partition_name,objs.partition_name) partition_name,
                 segs.segment_subtype,
                 BLOCKS,
                 BYTES,
                 EXTENTS,
                 INITIAL_EXTENT INI_EXT,
                 NEXT_EXTENT NEXT_EXT,
                 exa.cells,
                 exa.pieces,
                 exa.hits,
                 exa.misses,
                 exa.cachedsize,
                 exa.cachedwrite,
                 exa.columnarcache,
                 exa.cachedkeep,
                 exa.columnarkeep
        FROM   (SELECT segment_owner,segment_name,lob_column_name,segment_type,partition_name,tablespace_name from objs
                UNION  ALL
                SELECT segment_owner,index_name,lob_column_name,'INDEX',INDEX_PART,tablespace_name from objs where index_name is not null) objs,
               &check_access_segs segs,
               &check_access_exa1 exa
        WHERE  objs.segment_owner = segs.owner(+)
        AND    objs.segment_name = segs.segment_name(+)
        AND    segs.segment_subtype(+) IS NOT NULL
        AND    objs.segment_owner = exa.owner(+)
        AND    objs.segment_name = exa.object_name(+)
        AND    nvl(objs.partition_name, ' ') = nvl2(exa.owner,nvl(exa.subobject_name, ' '),nvl(objs.partition_name, ' '))
        AND    nvl(objs.partition_name, ' ') = nvl2(segs.owner,nvl(segs.partition_name, ' '),nvl(objs.partition_name, ' '))) a
GROUP  BY rollup((object_name, object_type, lv)) 
ORDER  BY lv nulls first,a.object_name
