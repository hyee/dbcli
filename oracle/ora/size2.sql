/*[[
    Show object space usage and relative Exadata FlashCache size. Usage: @@NAME [owner.]object_name[.PARTITION_NAME] [-d] [-flash]
    The --TOTAL-- row sums up the object itself and all of its dependent segments, including its indexes, LOB segments and LOB indexes.
    A LOB segment and its index segment are prefixed with the column name and are listed under the object that owns them.
    If the given subobject is a partition of a composite-partitioned object, its subpartition segments are merged
    into that partition, one row for each object, unless -d is given.
    A clustered table has no segment of its own, so its own row shows no bytes and the cluster segment is not counted.

    Option:
    =======
        -d    : used to detail in segment level, otherwise in object name level
        -flash: also check flashcache usage, which needs the external table EXA$CACHED_OBJECTS
                (refer to script oracle/shell/create_exadata_external_tables.sh). The FC_* columns are not shown
                without this option, and the query fails with ORA-00942 if the table does not exist

    Sample Output:
    ==============
    -- ora size2 dbcli_s2_c2.p1 , the three subpartitions of P1 are merged, one row for each object
    OBJECT_NAME                  OBJECT_TYPE     TABLESPACE TBSTYPE SEGS EXTENTS  BLOCKS   BYTES    INI_EXT NEXT_EXT
    --------------------------------------- ------------------ ---------- ------- ---- ------- ------- --------- -------- --------
    --TOTAL--                                                  SYSTEM     MSSM      12 12.00   96.00   768.00 KB 64.00 KB  1.00 MB
    SYS.DBCLI_S2_C2.P1                      TABLE SUBPARTITION SYSTEM     MSSM       3  3.00   24.00   192.00 KB 64.00 KB  1.00 MB
      SYS.DBCLI_S2_C2_IX.P1                 INDEX SUBPARTITION SYSTEM     MSSM       3  3.00   24.00   192.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_IL0000252124C00003$$.P1  INDEX SUBPARTITION SYSTEM     MSSM       3  3.00   24.00   192.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_LOB0000252124C00003$$.P1 LOB SUBPARTITION   SYSTEM     MSSM       3  3.00   24.00   192.00 KB 64.00 KB  1.00 MB

    -- ora size2 dbcli_s2_c2.p1 -d , one row for each segment
    OBJECT_NAME                                    OBJECT_TYPE     TABLESPACE TBSTYPE SEGS EXTENTS  BLOCKS   BYTES    INI_EXT NEXT_EXT
    -------------------------------------------- ------------------ ---------- ------- ---- ------- ------- --------- -------- --------
    --TOTAL--                                                       SYSTEM     MSSM      12 12.00   96.00   768.00 KB 64.00 KB  1.00 MB
    SYS.DBCLI_S2_C2.P1_SB                        TABLE SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
    SYS.DBCLI_S2_C2.P1_SA                        TABLE SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
    SYS.DBCLI_S2_C2.P1_SMAX                      TABLE SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      SYS.DBCLI_S2_C2_IX.P1_SA                   INDEX SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      SYS.DBCLI_S2_C2_IX.P1_SB                   INDEX SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      SYS.DBCLI_S2_C2_IX.P1_SMAX                 INDEX SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_IL0000252124C00003$$.P1_SMAX  INDEX SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_IL0000252124C00003$$.P1_SB    INDEX SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_IL0000252124C00003$$.P1_SA    INDEX SUBPARTITION SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_LOB0000252124C00003$$.P1_SB   LOB SUBPARTITION   SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_LOB0000252124C00003$$.P1_SMAX LOB SUBPARTITION   SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB
      [LB] SYS.SYS_LOB0000252124C00003$$.P1_SA   LOB SUBPARTITION   SYSTEM     MSSM       1  1.00    8.00    64.00 KB 64.00 KB  1.00 MB

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
COL BYTES,INI_EXT,NEXT_EXT,FC_CACHED,FC_WRITE,FC_KEEP,FC_CCKEEP FOR KMG
COL BLOCKS,EXTENTS,fc_reqs FOR TMB
COL "fc_hit%,fc_cc%" FOR pct
WITH objs AS(
    SELECT /*+outline_leaf use_hash(objs lobs parts subs subt) opt_param('optimizer_dynamic_sampling' 11)*/
            objs.segment_owner,
            coalesce(subs.lob_name,parts.lob_name,lobs.segment_name,objs.segment_name) segment_name,
            coalesce(subs.lob_subpartition_name,parts.lob_partition_name,objs.partition_name) partition_name,
            objs.partition_name obj_partition_name, --the object's own partition/subpartition name
            objs.segment_type segment_type,
            coalesce(lobs.tablespace_name,objs.tablespace_name) tablespace_name,
            objs.lob_column_name,
            lobs.index_name index_name,
            nvl(subs.lob_indsubpart_name,parts.lob_indpart_name) index_part
    FROM    TABLE(DBMS_SPACE.OBJECT_DEPENDENT_SEGMENTS(
                '&object_owner', --objowner
                '&object_name', --objname
                NULL, --partname
                CASE '&object_type' --only the whole-object codes are accepted by the function:
                    --passing a partition code with a NULL partname raises ORA-06502,
                    --so the requested partition/subpartition is filtered out in the WHERE clause below
                    WHEN 'TABLE' THEN 1 --TABLE / TABLE PARTITION / TABLE SUBPARTITION
                    WHEN 'TABLE PARTITION' THEN 1
                    WHEN 'TABLE SUBPARTITION' THEN 1
                    WHEN 'INDEX' THEN 3 --INDEX / INDEX PARTITION / INDEX SUBPARTITION
                    WHEN 'INDEX PARTITION' THEN 3
                    WHEN 'INDEX SUBPARTITION' THEN 3
                    WHEN 'MATERIALIZED VIEW' THEN 13
                    WHEN 'MATERIALIZED VIEW LOG' THEN 14
                --other object types(LOB segment, cluster, zonemap...) are rejected by the function
                END)) objs,
           &check_access_dba.lobs lobs,
           &check_access_dba.lob_partitions parts,
           &check_access_dba.lob_subpartitions subs,
           (SELECT subpartition_name
            FROM &check_access_dba.tab_subpartitions
            WHERE '&object_type' LIKE 'TABLE PAR%'
            AND   partition_name='&&object_subname'
            AND   '&object_owner' = table_owner
            AND   '&object_name' = table_name
            UNION ALL
            SELECT subpartition_name
            FROM &check_access_dba.ind_subpartitions
            WHERE '&object_type' LIKE 'INDEX PAR%'
            AND   partition_name='&&object_subname'
            AND   '&object_owner' = index_owner
            AND   '&object_name' = index_name) subt
    WHERE  '&object_owner' = lobs.owner(+)
    AND    '&object_name' = lobs.table_name(+)
    AND    objs.lob_column_name = lobs.column_name(+)
    AND    '&object_owner' = parts.table_owner(+)
    AND    '&object_name' = parts.table_name(+)
    AND    objs.lob_column_name = parts.column_name(+)
    AND    objs.partition_name=parts.partition_name(+)
    AND    '&object_owner' = subs.table_owner(+)
    AND    '&object_name' = subs.table_name(+)
    AND    objs.partition_name=subt.subpartition_name(+)
    AND    objs.lob_column_name = subs.column_name(+)
    AND    objs.partition_name=subs.subpartition_name(+)
    AND    ('&object_subname' IS NULL --match the subobject name exactly, a prefix would also pull in P10/P100 for P1
            OR nvl(objs.partition_name, ' ') = '&object_subname'
            OR subt.subpartition_name IS NOT NULL)) --subpartitions of the requested partition
SELECT nvl(decode(lv, null,'', 1, '', '  ') || object_name||nvl2(partition_name,'.'||partition_name,''),'--TOTAL--') object_name,
       object_type,
       max(TABLESPACE) keep(dense_rank last order by bytes) TABLESPACE,
       MAX(segment_subtype) keep(dense_rank last order by bytes) tbstype,
       COUNT(bytes) segs, --not COUNT(1): a cluster member or a deferred-creation table has no segment row to count
       SUM(extents) extents,
       SUM(blocks) blocks,
       SUM(BYTES) BYTES,
       MAX(INI_EXT) INI_EXT,
       MAX(NEXT_EXT) NEXT_EXT
       &check_access_exa2 max(cells) fc_cells,sum(pieces) fc_segs,sum(hits+misses) fc_reqs,sum(hits)/nullif(sum(hits+misses),0) "FC_HIT%",sum(cachedsize) fc_cached,sum(columnarcache)/nullif(sum(cachedsize),0) "FC_CC%",sum(cachedwrite) fc_write,sum(cachedkeep) FC_KEEP,sum(columnarkeep) FC_CCKEEP
FROM   (SELECT /*+ordered use_hash(segs objs) use_hash(exa) no_merge(objs) NO_EXPAND_GSET_TO_UNION*/
        DISTINCT decode('&object_name', objs.segment_name, 1, 2) lv,
                 NVL2(objs.lob_column_name,'['||objs.lob_column_name||'] ','')||objs.segment_owner || '.' || objs.segment_name object_name,
                 trim('%' from decode(:object_subname||:OPT2, '', regexp_substr(nvl(segs.segment_type,objs.segment_type), '^\S+'), nvl(segs.segment_type,objs.segment_type))) object_type,
                 nvl(segs.TABLESPACE_NAME,objs.TABLESPACE_NAME) TABLESPACE,
                 decode('&OPT2', '1', objs.obj_partition_name
                                , coalesce('&object_subname',segs.partition_name,objs.partition_name)) partition_name,
                 coalesce(segs.partition_name,objs.partition_name) obj_seg_part,
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
        FROM   (SELECT segment_owner,segment_name,lob_column_name,segment_type,partition_name,obj_partition_name,tablespace_name from objs
                UNION  ALL
                SELECT segment_owner,index_name,lob_column_name,'INDEX',INDEX_PART,obj_partition_name,tablespace_name from objs where index_name is not null) objs,
               &check_access_segs segs,
               &check_access_exa1 exa
        WHERE  objs.segment_owner = segs.owner(+)
        AND    objs.segment_name = segs.segment_name(+)
        AND    segs.segment_subtype(+) IS NOT NULL
        AND    objs.segment_owner = exa.owner(+)
        AND    objs.segment_name = exa.object_name(+)
        AND    nvl(objs.partition_name, ' ') = nvl2(exa.owner,nvl(exa.subobject_name, ' '),nvl(objs.partition_name, ' '))
        AND    nvl(objs.partition_name, ' ') = nvl2(segs.owner,nvl(segs.partition_name, ' '),nvl(objs.partition_name, ' '))) a
GROUP  BY rollup((object_name,partition_name, object_type, lv)) 
ORDER  BY lv nulls first,a.object_name
