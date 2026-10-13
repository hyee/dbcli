/*[[
    Show or advice on object's space. Usage: @@NAME <[owner.]object_name[.partition_name]> [-dep] [advise]

    Option:
    =======
        advise: run segment space adviser and print the result
        -dep  : also analyze the depending objects which could be time-consuming

    A table, an index, a cluster, an index-organized table or a materialized view can be measured.
    Without -dep only the segments of that object itself are listed. The rows labelled
    'HWM: Last Used ...' hold an address instead of a counter, so they stay blank in the Total and
    DEP-OBJS columns, which stand for more than one segment.

    Sample Output:
    ==============
    -- ora space sys.obj$ -dep
    TABLE: SYS.OBJ$
    ==================================
              ITEM            Total THIS-OBJ DEP-OBJS * I_OBJ1  I_OBJ2  I_OBJ3 I_OBJ4  I_OBJ5
    ------------------------ ------ -------- -------- - ------ ------- ------- ------ -------
    ABOVE HWM: Unused Blocks    293       48      245 |     13      88       3     48      93
    ABOVE HWM: Unused MBytes   2.30     0.38     1.92 |   0.10    0.69    0.02   0.38    0.73
    HWM: * Total Blocks *     3,707    1,232    2,475 |    243     936      29    336     931
    HWM: * Total MBytes *     28.97     9.63    19.34 |   1.90    7.31    0.23   2.63    7.27
    HWM: Free Blocks             37        5       32 |      9       3       5     10       5
    HWM: Free MBytes(Est)      0.29     0.04     0.25 |   0.07    0.02    0.04   0.08    0.04
    HWM: Last Used Block#            105,344          | 73,856 109,824 132,776 92,416 110,848
    HWM: Last Used Blocks                 80          |    115      40       5     80      35
    HWM: Last Used File#                   1          |      1       1       1      1       1
    HWM: Unformatted Blocks       0        0        0 |      0       0       0      0       0
    Total: Blocks             4,000    1,280    2,720 |    256   1,024      32    384   1,024
    Total: KBytes            32,000   10,240   21,760 |  2,048   8,192     256  3,072   8,192
    Total: MBytes             31.25       10    21.25 |      2       8    0.25      3       8
    Total: Segments               6        1        5 |      1       1       1      1       1

    -- ora space sys.obj$ -dep advise
    TABLE: SYS.OBJ$
    ==================================
          NAM        OBJECT_TYPE OWNER SEGMENT_NAME PARTITION_NAME ALLOCATED_KBYTES USED_KBYTES RECLAIMABLE_KBYTES COMMAND ATTR1 ATTR2
    ---------------- ----------- ----- ------------ -------------- ---------------- ----------- ------------------ ------- ----- -----
    Object: SYS.OBJ$ --total--   SYS   OBJ$                                  32,000      24,170              7,830
        SYS.OBJ$     TABLE       SYS   OBJ$                                  10,240       9,723                517
        SYS.I_OBJ5   INDEX       SYS   I_OBJ5                                 8,192       5,531              2,661
        SYS.I_OBJ1   INDEX       SYS   I_OBJ1                                 2,048       1,587                461
        SYS.I_OBJ4   INDEX       SYS   I_OBJ4                                 3,072       1,635              1,437
        SYS.I_OBJ3   INDEX       SYS   I_OBJ3                                   256         157                 99
        SYS.I_OBJ2   INDEX       SYS   I_OBJ2                                 8,192       5,536              2,656

    --[[
        @CHECK_ACCESS: dbms_space/dba_objects/dba_tablespaces={}
        @check_access_dba: dba_objects={dba_} default={all_}
        @check_access_segs: dba_segments={dba_segments} default={(select user owner,a.* from user_segments a)}
        @ARGS: 1
        @fs5: 12.2={fs5_blocks=>v_fs5_blocks,fs5_bytes => v_fs5_bytes,} default={}
        &dep: default={0} dep={1}
    --]]
]]*/

findobj "&V1" "" 1
pro &object_type: &object_owner..&object_name
pro ==================================
set feed off sep4k on digits 2 SQLTIMEOUT 86400
VAR CUR REFCURSOR;

DECLARE
    TYPE l_ary IS TABLE OF VARCHAR2(100) INDEX BY VARCHAR2(100);
    TYPE l_grp IS TABLE OF l_ary INDEX BY VARCHAR2(100);
    v_cur SYS_REFCURSOR;
    CURSOR l_CursorSegs(p_owner     VARCHAR2,
                        p_segname   VARCHAR2,
                        p_partition VARCHAR2,
                        P_type      VARCHAR2 :=null) IS
            WITH objs AS(SELECT /*+ordered use_hash(objs lobs parts subs)*/
                    objs.segment_owner,
                    coalesce(subs.lob_name,parts.lob_name,lobs.segment_name,objs.segment_name) segment_name,
                    coalesce(subs.lob_subpartition_name,parts.lob_partition_name,objs.partition_name) partition_name,
                    objs.segment_type segment_type,
                    coalesce(lobs.tablespace_name,objs.tablespace_name) tablespace_name,
                    objs.lob_column_name,
                    lobs.index_name index_name,
                    nvl(subs.lob_indsubpart_name,parts.lob_indpart_name) index_part
            FROM    (
                    SELECT *
                    FROM   TABLE(dbms_space.object_dependent_segments(p_owner, --objowner
                                        p_segname, --objname
                                        p_partition, --partname
                                        CASE nvl(p_type,
                                                 (SELECT max(x.object_type)
                                                  FROM   dba_objects x
                                                  WHERE  x.owner = p_owner
                                                  AND    x.object_name = p_segname
                                                  AND    x.subobject_name IS NULL))
                                            WHEN 'TABLE' THEN 1
                                            WHEN 'TABLE PARTITION' THEN 7
                                            WHEN 'TABLE SUBPARTITION' THEN 9
                                            WHEN 'INDEX' THEN 3
                                            WHEN 'INDEX PARTITION' THEN 8
                                            WHEN 'INDEX SUBPARTITION' THEN 10
                                            WHEN 'NESTED_TABLE' THEN 2
                                            WHEN 'MATERIALIZED VIEW' THEN 13
                                            WHEN 'MATERIALIZED VIEW LOG' THEN 14
                                            WHEN 'MATERIALIZED ZONEMAP' THEN 1
                                        END))
                    --object_dependent_segments supports neither clusters(ORA-20000) nor LOB segment
                    --names; a filter that is false before the first fetch keeps it from running
                    WHERE  nvl(p_type,'x') NOT LIKE 'LOB%'
                    AND    nvl(p_type,'x') != 'CLUSTER'
                    UNION ALL
                    --a cluster is not an objtype the procedure above accepts, so list its own
                    --segment from *_segments. UNION matches by position and the names come from
                    --the piped table, whose order is (owner, name, type, tablespace, partition,
                    --lob_column) -- not the order *_segments prints them in.
                    SELECT owner,segment_name,segment_type,tablespace_name,partition_name,null
                    FROM   &check_access_segs
                    WHERE  p_type = 'CLUSTER'
                    AND    segment_type = 'CLUSTER'
                    AND    owner = p_owner
                    AND    segment_name = p_segname) objs,
                   &check_access_dba.lobs lobs,
                   &check_access_dba.lob_partitions parts,
                   &check_access_dba.lob_subpartitions subs
            WHERE  objs.segment_owner = lobs.owner(+)
            AND    objs.segment_name = lobs.table_name(+)
            AND    objs.lob_column_name = lobs.column_name(+)
            AND    objs.segment_owner = parts.table_owner(+)
            AND    objs.segment_name = parts.table_name(+)
            AND    objs.lob_column_name = parts.column_name(+)
            AND    objs.partition_name = parts.partition_name(+)
            AND    objs.segment_owner = subs.table_owner(+)
            AND    objs.segment_name = subs.table_name(+)
            AND    objs.lob_column_name = subs.column_name(+)
            AND    objs.partition_name = subs.subpartition_name(+)
            AND    nvl(objs.partition_name, ' ') LIKE p_partition || '%')
        SELECT /*+leading(x seg y) use_nl(seg) use_hash(y) no_merge(y)*/
               DISTINCT segment_owner || '.' || segment_name || nullif('.' || partition_name, '.') object_name,
               segment_type object_type,
               seg.*,
               (SELECT segment_space_management
                FROM   dba_tablespaces ts
                WHERE  seg.tablespace_name = ts.tablespace_name) mgnt,
               (SELECT block_size
                FROM   dba_tablespaces ts
                WHERE  seg.tablespace_name = ts.tablespace_name) block_size
        FROM   (SELECT s.*,
                       --The segment that holds the target itself: either it is named after the
                       --target, or the target is an IOT and object_dependent_segments pipes its
                       --storage as the "IOT - TOP" index segments.
                       CASE WHEN s.segment_name = p_segname
                                 OR s.segment_name = (SELECT idx.index_name
                                                      FROM   &check_access_dba.indexes idx
                                                      WHERE  idx.table_owner = p_owner
                                                      AND    idx.table_name = p_segname
                                                      AND    idx.index_type = 'IOT - TOP'
                                                      AND    ROWNUM < 2)
                            THEN 1 ELSE 2 END lv
                FROM   (SELECT segment_owner,segment_name,segment_type,partition_name,tablespace_name
                        FROM   objs
                        UNION ALL
                        SELECT segment_owner,index_name,'INDEX',index_part,tablespace_name
                        FROM   objs
                        WHERE  index_name IS NOT NULL) s) seg
        WHERE  (&dep = 1 OR seg.lv = 1);

    TYPE l_CursorSet IS TABLE OF l_CursorSegs%ROWTYPE;

    FUNCTION parseName(owner VARCHAR2, seg VARCHAR2, part VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN trim('.' FROM owner || '.' || seg || '.' || part);
    END;

    PROCEDURE pr(p_msg VARCHAR2) IS
    BEGIN
        dbms_output.put_line(p_msg);
    END;

    FUNCTION show_space(p_segname   IN VARCHAR2,
                        p_owner     IN VARCHAR2 DEFAULT sys_context('USERENV','CURRENT_SCHEMA'),
                        p_partition IN VARCHAR2 DEFAULT NULL,
                        p_type      IN VARCHAR2 DEFAULT NULL) RETURN l_grp AS
        v_free_blks          INT;
        v_total_blocks       INT;
        v_total_bytes        INT;
        v_unused_blocks      INT;
        v_unused_bytes       INT;
        v_LastUsedExtFileId  INT;
        v_LastUsedExtBlockId INT;
        v_last_used_block    INT;
        v_unformatted_blocks INT;
        v_unformatted_bytes  INT;
        v_fs1_blocks         INT := -1;
        v_fs1_bytes          INT;
        v_fs2_blocks         INT := -1;
        v_fs2_bytes          INT;
        v_fs3_blocks         INT := -1;
        v_fs3_bytes          INT;
        v_fs4_blocks         INT := -1;
        v_fs4_bytes          INT;
        v_fs5_blocks         INT;
        v_fs5_bytes          INT := 0;
        v_full_blocks        INT;
        v_full_bytes         INT;
        v_free_bytes         INT;
        v_expired_blocks     INT;
        v_expired_bytes      INT;
        v_unexpired_blocks   INT;
        v_unexpired_bytes    INT;
        v_segname            VARCHAR2(200) := p_segname;
        v_owner              VARCHAR2(128) := p_owner;
        v_partition          VARCHAR2(128) := p_partition;
        v_result             l_grp;
        v_group              l_CursorSet;
        v_tag                VARCHAR2(100);
        --How many segments stand behind each aggregate column. A row such as
        --'HWM: Last Used File#' is an address, not a counter: summing six of them answers nothing,
        --so it is rolled up only when the column has a single segment.
        v_all_cnt            PLS_INTEGER := 0;
        v_lvl1_cnt           PLS_INTEGER := 0;
        v_lvl2_cnt           PLS_INTEGER := 0;

        FUNCTION additive(p_label VARCHAR2, p_cnt PLS_INTEGER) RETURN BOOLEAN IS
        BEGIN
            RETURN p_label NOT LIKE 'HWM: Last Used %' OR p_cnt = 1;
        END;

        PROCEDURE st(p_label IN VARCHAR2, p_val VARCHAR2, p_tag VARCHAR2 := NULL) IS
        BEGIN
            v_result(nvl(p_tag, v_tag))(p_label) := p_val;
        END;

        FUNCTION rd(p_label IN VARCHAR2, p_tag VARCHAR2 := NULL) RETURN VARCHAR2 IS
            v_tar VARCHAR2(100) := nvl(p_tag, v_tag);
        BEGIN
            IF NOT v_result.exists(v_tar) OR NOT v_result(v_tar).exists(p_label) THEN
                st(p_label, '', v_tar);
                RETURN '';
            END IF;
            RETURN v_result(v_tar)(p_label);
        END;

        PROCEDURE calc(p_label IN VARCHAR2, p_num IN NUMBER, p_tag VARCHAR2 := NULL) IS
            tag VARCHAR2(100) := nvl(p_tag, v_tag);
            v_cnt PLS_INTEGER;
        BEGIN
            st(p_label, nvl(rd(p_label, tag), 0) + nvl(p_num, 0), tag);
            IF tag NOT LIKE '@%' THEN
                IF additive(p_label, v_all_cnt) THEN
                    calc(p_label, p_num, '@all');
                ELSE
                    --the printed rows are the labels of the Total column, so keep the entry and
                    --leave it blank instead of showing a sum that describes no segment
                    st(p_label, '', '@all');
                END IF;
                v_cnt := v_lvl2_cnt;
                IF rd('@level', tag) = '1' THEN
                    v_cnt := v_lvl1_cnt;
                END IF;
                IF additive(p_label, v_cnt) THEN
                    calc(p_label, p_num, '@level' || rd('@level', tag));
                END IF;
            END IF;
        END;
    BEGIN
        --the dictionary stores unquoted names upper-cased, so the case the user typed is normalised
        v_segname   := trim(upper(v_segname));
        v_owner     := trim(upper(v_owner));
        v_partition := trim(upper(v_partition));
        --define root object

        st('@target', parseName(v_owner, v_segname, v_partition), '@all');
        st('@type', 'UNKNOWN', '@all');
        st('@level', 0, '@all');
        --read segment list
        OPEN l_CursorSegs(p_owner, p_segname, p_partition, p_type);
        FETCH l_CursorSegs BULK COLLECT INTO v_group;
        CLOSE l_CursorSegs;
        --handle the situation that no matched records found
        IF v_group.count = 0 THEN
            st('@msg', 'Object [' || rd('@target', '@all') || '] doesn''t exist!', '@all');
            RETURN v_result;
        END IF;

        v_all_cnt := v_group.count;
        FOR i IN 1 .. v_group.count LOOP
            IF v_group(i).lv = 1 THEN
                v_lvl1_cnt := v_lvl1_cnt + 1;
            ELSE
                v_lvl2_cnt := v_lvl2_cnt + 1;
            END IF;
        END LOOP;

        --start fetching space statistics for each segments
        FOR i IN 1 .. v_group.count LOOP
            v_tag := v_group(i).segment_name;
            st('@level', v_group(i).lv);
            st('@type', v_group(i).segment_type);
            st('@type', v_group(i).object_type, '@all');
            BEGIN
                --Every statistic below is a per-segment OUT and the loop keeps printing this
                --segment even when its probe raises, so a value left over from the previous
                --segment would be added into this row -- and lend it the 'LOB: Chunks' label.
                v_total_blocks := NULL;       v_total_bytes := NULL;
                v_unused_blocks := NULL;      v_unused_bytes := NULL;
                v_free_blks := NULL;          v_free_bytes := NULL;
                v_unformatted_blocks := NULL;
                v_fs1_blocks := -1;           v_fs2_blocks := -1;
                v_fs3_blocks := -1;           v_fs4_blocks := -1;
                v_fs5_blocks := NULL;         v_fs5_bytes := 0;
                v_full_blocks := NULL;        v_full_bytes := NULL;
                BEGIN
                    --object_dependent_segments reports no tablespace for an IOT partition, which
                    --leaves mgnt NULL; such a segment has no freelist anyway, so probe it as ASSM.
                    IF nvl(v_group(i).mgnt, 'AUTO') = 'AUTO' THEN
                        v_unformatted_blocks := 0;
                        BEGIN
                            dbms_space.space_usage(segment_owner      => v_group(i).segment_owner,
                                                   segment_name       => v_group(i).segment_name,
                                                   segment_type       => v_group(i).segment_type,
                                                   partition_name     => v_group(i).partition_name,
                                                   unformatted_blocks => v_unformatted_blocks,
                                                   unformatted_bytes  => v_unformatted_bytes,
                                                   fs1_blocks         => v_fs1_blocks,
                                                   fs1_bytes          => v_fs1_bytes,
                                                   fs2_blocks         => v_fs2_blocks,
                                                   fs2_bytes          => v_fs2_bytes,
                                                   fs3_blocks         => v_fs3_blocks,
                                                   fs3_bytes          => v_fs3_bytes,
                                                   fs4_blocks         => v_fs4_blocks,
                                                   fs4_bytes          => v_fs4_bytes,
                                                   &fs5
                                                   full_blocks        => v_full_blocks,
                                                   full_bytes         => v_full_bytes);
                            --FS5 (100% free) counts as free here too, otherwise this row and the
                            --'Free MBytes(Est)' below, which does add v_fs5_bytes, disagree
                            v_free_blks := v_fs1_blocks + v_fs2_blocks + v_fs3_blocks + v_fs4_blocks +
                                           nvl(v_fs5_blocks, 0);
                            -- This is only a estimated value, not a exactly value
                            v_free_bytes := v_fs1_bytes * 1 / 8 + v_fs2_bytes * 3 / 8 +
                                            v_fs3_bytes * 5 / 8 + v_fs4_bytes * 7 / 8 + v_fs5_bytes;
                            calc('HWM: FS1 Blocks(01%-25% Free)', v_fs1_blocks);
                            calc('HWM: FS2 Blocks(25%-50% Free)', v_fs2_blocks);
                            calc('HWM: FS3 Blocks(50%-75% Free)', v_fs3_blocks);
                            calc('HWM: FS4 Blocks(75%-100% Free)', v_fs4_blocks);
                            IF v_fs5_blocks IS NOT NULL THEN
                                calc('HWM: FS5 Blocks(100% Free)', v_fs5_blocks);
                            END IF;
                            calc('HWM: Full Blocks', v_full_blocks);
                            calc('HWM: Full MBytes', round(v_full_bytes / 1024 / 1024, 2));
                            calc('HWM: Free Blocks(Est)', v_free_blks);
                        EXCEPTION WHEN OTHERS THEN
                        $IF dbms_db_version.version > 10 $THEN
                            dbms_space.space_usage(segment_owner      => v_group(i).segment_owner,
                                                   segment_name       => v_group(i).segment_name,
                                                   segment_type       => v_group(i).segment_type,
                                                   partition_name     => v_group(i).partition_name,
                                                   segment_size_blocks=> v_total_blocks,
                                                   segment_size_bytes => v_total_bytes,
                                                   used_blocks        => v_unused_blocks,
                                                   used_bytes         => v_unused_bytes,
                                                   expired_blocks     => v_expired_blocks,
                                                   expired_bytes      => v_expired_bytes,
                                                   unexpired_blocks   => v_unexpired_blocks,
                                                   unexpired_bytes    => v_unexpired_bytes);
                            v_unformatted_blocks := -1;
                            calc('LOB: Expired Blocks', v_expired_blocks);
                            calc('LOB: Expired MBytes', round(v_expired_bytes / 1024 / 1024, 2));
                            calc('LOB: Versioned Blocks', v_unexpired_blocks);
                            calc('LOB: Versioned MBytes', round(v_unexpired_bytes / 1024 / 1024, 2));
                            calc('LOB: Used Blocks', v_unused_blocks);
                            calc('LOB: Used MBytes', round(v_unused_bytes / 1024 / 1024, 2));
                        $ELSE
                            NULL;
                        $END
                        END;
                    ELSE
                        dbms_space.free_blocks(segment_owner     => v_group(i).segment_owner,
                                               segment_name      => v_group(i).segment_name,
                                               segment_type      => v_group(i).segment_type,
                                               partition_name    => v_group(i).partition_name,
                                               freelist_group_id => 0,
                                               free_blks         => v_free_blks);
                        v_free_bytes := v_free_blks * v_group(i).block_size;
                        calc('HWM: Free Blocks', v_free_blks);
                    END IF;
                --free_blocks answers ORA-10618 for clusters and IOT segments whatever the
                --tablespace says; the HWM statistics of that segment are still worth showing
                EXCEPTION WHEN OTHERS THEN NULL;
                END;

                calc('HWM: Free MBytes(Est)', round(v_free_bytes / 1024 / 1024, 2));

                dbms_space.unused_space(segment_owner             => v_group(i).segment_owner,
                                        segment_name              => v_group(i).segment_name,
                                        segment_type              => v_group(i).segment_type,
                                        partition_name            => v_group(i).partition_name,
                                        total_blocks              => v_total_blocks,
                                        total_bytes               => v_total_bytes,
                                        unused_blocks             => v_unused_blocks,
                                        unused_bytes              => v_unused_bytes,
                                        LAST_USED_EXTENT_FILE_ID  => v_LastUsedExtFileId,
                                        LAST_USED_EXTENT_BLOCK_ID => v_LastUsedExtBlockId,
                                        LAST_USED_BLOCK           => v_last_used_block);
                calc('ABOVE HWM: Unused Blocks', v_unused_blocks);
                calc('ABOVE HWM: Unused MBytes', round(v_unused_bytes / 1024 / 1024, 2));
                calc('HWM: Last Used File#', v_LastUsedExtFileId);
                calc('HWM: Last Used Block#', v_LastUsedExtBlockId);
                calc('HWM: Last Used Blocks', v_last_used_block);
                calc('HWM: * Total Blocks *', v_total_blocks - v_unused_blocks);
                calc('HWM: * Total MBytes *',
                     round((v_total_blocks - v_unused_blocks) * v_group(i).block_size / 1024 / 1024, 2));
                --v_unformatted_blocks says which probe answered: -1 is the marker the LOB
                --fallback leaves behind, >= 0 is what space_usage measured for an ASSM segment
                --(compare it with the remainder the HWM arithmetic implies, as before), and NULL
                --means neither probe ran, so nothing is known about the remainder.
                calc(CASE WHEN v_unformatted_blocks = -1 THEN 'LOB: Chunks'
                          ELSE 'HWM: Unformatted Blocks' END,
                     CASE WHEN v_unformatted_blocks IS NULL THEN 0
                          WHEN v_unformatted_blocks = -1 THEN
                              greatest(0, nvl(v_total_blocks, 0) - nvl(v_unused_blocks, 0))
                          ELSE
                              greatest(v_unformatted_blocks, nvl(v_total_blocks, 0) - nvl(v_unused_blocks, 0) -
                                          nvl(v_free_blks, 0) - nvl(v_full_blocks, 0))
                     END);
            EXCEPTION WHEN OTHERS THEN
                IF sqlcode = -1031 THEN
                    RAISE;
                END IF;
            END;
            calc('Total: Segments', 1);
            calc('Total: Blocks', v_total_blocks);
            calc('Total: KBytes', v_total_bytes / 1024);
            calc('Total: MBytes', round(v_total_bytes / 1024 / 1024, 2));
        END LOOP;
        --this setting indicates that the fetching has completed
        v_result('@all')('@msg') := 'done';
        v_result('@all')('@title') := 'Total';
        v_result('@level1')('@title') := 'THIS-OBJ';
        IF v_result.exists('@level2') THEN
            v_result('@level2')('@title') := 'DEP-OBJS';
        END IF;
        RETURN v_result;
    END;

    --the owner/name/partition triple that 'findobj' resolved for the current target
    FUNCTION analyze_target RETURN l_ary IS
        v_ary l_ary;
    BEGIN
        v_ary('owner')       := :object_owner;
        v_ary('segment')     := :object_name;
        v_ary('partition')   := :object_subname;
        v_ary('object_type') := :object_type;
        RETURN v_ary;
    END;

    FUNCTION analyze_list(p_list VARCHAR2) RETURN l_grp AS
        v_ary        l_ary;
        v_uncl_array dbms_utility.uncl_array;
        v_count      PLS_INTEGER;
        v_group      l_grp;
        v_uniq       l_ary;
        v_obj        VARCHAR2(100);
    BEGIN
        dbms_utility.comma_to_table(replace(p_list, ''''), v_count, v_uncl_array);
        FOR i IN 1 .. v_count LOOP
            IF trim(v_uncl_array(i)) IS NOT NULL THEN
                v_ary := analyze_target();
                v_obj := v_ary('segment') || '.' || v_ary('owner') || '.' || v_ary('partition');
                IF NOT v_uniq.exists(v_obj) THEN
                    v_uniq(v_obj) := 1;
                    v_group(v_group.count + 1) := v_ary;
                END IF;
            END IF;
        END LOOP;
        RETURN v_group;
    END;

    PROCEDURE print(p_cur OUT SYS_REFCURSOR) IS
        v_target l_ary := analyze_target();
        v_ary    l_grp;
        v_titles l_ary;
        v_rows   l_ary;
        v_all    l_ary;
        v_idx    VARCHAR2(100);
        v_xml    CLOB := '<ROWSET>';
        v_sql    VARCHAR2(32767);
    BEGIN
        dbms_output.enable(NULL);
        IF v_target('segment') IS NULL THEN
            pr('Cannot find target object!');
            RETURN;
        END IF;
        v_ary := show_space(p_segname   => v_target('segment'),
                            p_owner     => v_target('owner'),
                            p_partition => v_target('partition'),
                            p_type      => v_target('object_type'));

        IF v_ary('@all')('@msg') != 'done' THEN
            pr(v_ary('@all')('@msg'));
            RETURN;
        END IF;

        v_sql := 'SELECT extractvalue(column_value,''/ROW/C0'') item,';
        v_all := v_ary('@all');

        IF NOT v_ary.exists('@level2') THEN
            v_ary.delete('@all');
        END IF;

        v_idx := v_ary.first;
        LOOP
            IF v_ary(v_idx).exists('@level') AND v_ary(v_idx)('@level') = 1 THEN
                v_ary.delete(v_idx);
            ELSE
                v_titles(v_titles.count + 1) := v_idx;
                v_sql := v_sql || '0+extractvalue(column_value,''/ROW/C' || v_titles.count || ''') ';
                IF v_ary(v_idx).exists('@title') THEN
                    v_sql := v_sql || '"' || v_ary(v_idx)('@title') || '"';
                ELSE
                    v_sql := v_sql || '"' || v_idx || '"';
                END IF;
                v_sql := v_sql || ',';
                IF v_idx = '@level2' THEN
                    v_sql := v_sql || ' ''|'' "*",';
                END IF;
            END IF;
            v_idx := v_ary.next(v_idx);
            EXIT WHEN v_idx IS NULL;
        END LOOP;
        v_sql := trim(',' FROM v_sql);

        v_idx := v_all.first;
        LOOP
            IF v_idx NOT LIKE '@%' THEN
                v_rows(v_rows.count + 1) := v_idx;
            END IF;
            v_idx := v_all.next(v_idx);
            EXIT WHEN v_idx IS NULL;
        END LOOP;

        FOR i IN 1 .. v_rows.count LOOP
            v_xml := v_xml || '<ROW><C0>' || v_rows(i) || '</C0>';
            FOR j IN 1 .. v_titles.count LOOP
                IF v_ary(v_titles(j)).exists(v_rows(i)) THEN
                    v_xml := v_xml || '<C' || j || '>' || v_ary(v_titles(j))(v_rows(i)) || '</C' || j || '>';
                END IF;
            END LOOP;
            v_xml := v_xml || '</ROW>' || chr(10);
        END LOOP;
        v_xml := v_xml || '</ROWSET>';
        v_sql := v_sql || ' FROM TABLE(xmlsequence(extract(xmltype(:1),''/ROWSET[1]/ROW'')))';
        --dbms_output.put_line(v_sql);
        OPEN p_cur FOR v_sql USING v_xml;
    END;

    PROCEDURE seg_advise(p_cur  OUT SYS_REFCURSOR,
                         p_list VARCHAR2) IS
        v_list  l_grp := analyze_list(p_list);
        v_items l_grp;
        v_segs  l_CursorSet;
        v_task  VARCHAR2(128) := 'PKG_SPACE_SEGMENT_ADVISE';
        v_node  VARCHAR2(200);
        v_top   VARCHAR2(200);
        v_xml   xmltype := xmltype('<ROOT/>');
        v_alloc NUMBER;
        v_used  NUMBER;
        v_free  NUMBER;
        v_objid INT;
        v_seek  PLS_INTEGER;
        v_id    VARCHAR2(30);
        PROCEDURE NewNode(id    VARCHAR2,
                          nam   VARCHAR2,
                          owner VARCHAR2,
                          seg   VARCHAR2,
                          part  VARCHAR2,
                          typ   VARCHAR2 := '') IS
            v_obj l_ary;
        BEGIN
            v_obj('id') := id;
            v_items(nam) := v_obj;
            v_xml := v_xml.appendchildxml('/ROOT[1]',
                                          xmltype('<NODE id="' || id || '" name="' || nam ||
                                                  '" owner="' || owner || '" seg="' || seg ||
                                                  '" part="' || part || '" segtype="' || typ ||
                                                  '"/>'));
        END;

    BEGIN
        --execute dbms_workload_repository.create_snapshot('ALL');
        IF v_list.count = 0 THEN
            RETURN;
        END IF;

        SELECT count(1) INTO v_objid FROM dba_advisor_tasks WHERE task_name = v_task;
        IF v_objid > 0 THEN
            dbms_advisor.delete_task(task_name => v_task);
        END IF;

        dbms_advisor.create_task(advisor_name => 'Segment Advisor', task_name => v_task);
        dbms_advisor.set_task_parameter(task_name => v_task,
                                        parameter => 'RECOMMEND_ALL',
                                        value     => 'TRUE');
        FOR i IN 1 .. v_list.count LOOP
            OPEN l_CursorSegs(v_list(i)('owner'),
                              v_list(i)('segment'),
                              v_list(i)('partition'),
                              v_list(i)('object_type'));
            FETCH l_CursorSegs BULK COLLECT INTO v_segs;
            CLOSE l_CursorSegs;

            v_top := parseName('Object: ' || v_list(i)('owner'),
                               v_list(i)('segment'),
                               v_list(i)('partition'));
            NewNode(lpad(i, 4, 0),
                    v_top,
                    v_list(i)('owner'),
                    v_list(i)('segment'),
                    v_list(i)('partition'),
                    '--total--');
            v_seek := 0;
            FOR j IN 1 .. v_segs.count LOOP
                dbms_advisor.create_object(task_name   => v_task,
                                           object_type => v_segs(j).segment_type,
                                           attr1       => v_segs(j).segment_owner,
                                           attr2       => v_segs(j).segment_name,
                                           attr3       => v_segs(j).partition_name,
                                           attr4       => 'null',
                                           attr5       => NULL,
                                           object_id   => v_objid);
                v_node := parseName(v_segs(j).segment_owner,
                                    v_segs(j).segment_name,
                                    v_segs(j).partition_name);
                v_id   := lpad(i, 4, 0) || lpad(j + 1, 4, 0);
                IF ('Object: ' || v_node || '.') LIKE v_top || '.%' AND v_seek = 0 THEN
                    v_id   := lpad(i, 4, 0) || lpad(1, 4, 0);
                    v_seek := 1;
                END IF;
                NewNode(v_id,
                        v_node,
                        v_segs(j).segment_owner,
                        v_segs(j).segment_name,
                        v_segs(j).partition_name,
                        v_segs(j).segment_type);
            END LOOP;
        END LOOP;
        dbms_advisor.execute_task(task_name => v_task);
        FOR r IN (SELECT a.*, b.more_info
                  FROM   dba_advisor_objects a, dba_advisor_findings b
                  WHERE  a.task_name = v_task
                  AND    a.task_id = b.task_id(+)
                  AND    a.object_id = b.object_id(+)) LOOP
            v_node := parseName(r.attr1, r.attr2, r.attr3);
            IF NOT v_items.exists(v_node) THEN
                NewNode(v_items(r.attr1 || '.' || r.attr2)('id') || lpad(r.object_id, 4, 0),
                        v_node,
                        r.attr1,
                        r.attr2,
                        r.attr3,
                        r.type);
            END IF;
            IF r.more_info IS NOT NULL THEN
                dbms_space.parse_space_adv_info(r.more_info, v_used, v_alloc, v_free);
                IF v_alloc IS NOT NULL THEN
                    v_xml := v_xml.appendchildxml('/ROOT[1]/NODE[@name="' || v_node || '"]',
                                                  xmltype('<ATTR><OBJECT_ID>' || r.object_id || '</OBJECT_ID>' ||
                                                          '<ALLOC>' || v_alloc || '</ALLOC>' ||
                                                          '<USED>' || v_used || '</USED>' ||
                                                          '<FREE>' || v_free || '</FREE></ATTR>')
                                                  .extract('/ATTR[1]/*'));
                END IF;
            END IF;
        END LOOP;
        --p_adv:=dbms_advisor.get_task_script(task_name => v_task);
        OPEN p_cur FOR
            SELECT lpad(' ', length(a.id) - 4) || a.name nam,
                   a.object_type,
                   a.owner,
                   a.segment_name,
                   a.partition_name,
                   round(sum(allocated_space) OVER(ORDER BY rpad(a.id, 12, 9) + 0
                              RANGE BETWEEN rpad(a.id, 12, 9) - rpad(a.id, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) allocated_kbytes,
                   round(sum(used_space) OVER(ORDER BY rpad(a.id, 12, 9) + 0
                              RANGE BETWEEN rpad(a.id, 12, 9) - rpad(a.id, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) used_kbytes,
                   round(sum(reclaimable_space)
                         OVER(ORDER BY rpad(a.id, 12, 9) + 0
                              RANGE BETWEEN rpad(a.id, 12, 9) - rpad(a.id, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) reclaimable_kbytes,
                   b.command,
                   b.attr1,
                   b.attr2
            FROM   (SELECT extractvalue(column_value, '/NODE/@id') id,
                           extractvalue(column_value, '/NODE/@name') name,
                           extractvalue(column_value, '/NODE/@segtype') object_type,
                           extractvalue(column_value, '/NODE/@owner') owner,
                           extractvalue(column_value, '/NODE/@seg') segment_name,
                           extractvalue(column_value, '/NODE/@part') partition_name,
                           extractvalue(column_value, '/NODE/OBJECT_ID[1]') object_id,
                           extractvalue(column_value, '/NODE/ALLOC[1]') allocated_space,
                           extractvalue(column_value, '/NODE/USED[1]') used_space,
                           extractvalue(column_value, '/NODE/FREE[1]') reclaimable_space
                    FROM   TABLE(xmlsequence(extract(v_xml, '/ROOT[1]/NODE')))) a,
                   dba_advisor_actions b
            WHERE  b.task_name(+) = v_task
            AND    b.object_id(+) = a.object_id
            ORDER  BY id;

    END;
BEGIN
    IF lower(nvl(:V2,'x')) != 'advise' THEN
        print(v_cur);
    ELSE
        seg_advise(v_cur, :V1);
    END IF;
    :cur := v_cur;
EXCEPTION
    WHEN OTHERS THEN raise_application_error(-20001, sqlerrm);
END;
/
