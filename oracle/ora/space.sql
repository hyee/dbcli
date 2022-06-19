/*[[
Show or advice on object's space. Usage: @@NAME <[owner.]object_name[.partition_name]> [-dep] [advise]
Parameters 
    advise: run segment space adviser and print the result
    -dep  : also analyze the depending objects which could be time-consuming

Sample Output:
================
ORCL> ora space sys.obj$                                                                 
              ITEM           Total THIS-OBJ DEP-OBJS * I_OBJ1 I_OBJ2 I_OBJ3 I_OBJ4 I_OBJ5
    ------------------------ ----- -------- -------- - ------ ------ ------ ------ ------
    ABOVE HWM: Unused Blocks   413       68      345 |     48    113      3     68    113
    ABOVE HWM: Unused MBytes  3.22     0.53     2.69 |   0.38   0.88   0.02   0.53   0.88
    HWM: Free MBytes(Est)      0.2     0.04     0.16 |   0.02   0.03   0.03   0.04   0.04
    HWM: Total Blocks         3587     1212     2375 |    208    911     29    316    911
    HWM: Total MBytes        28.04     9.47    18.57 |   1.63   7.12   0.23   2.47   7.12
    Total: Blocks             4000     1280     2720 |    256   1024     32    384   1024
    Total: KBytes            32000    10240    21760 |   2048   8192    256   3072   8192
    Total: MBytes            31.25       10    21.25 |      2      8   0.25      3      8
    Total: Segments              6        1        5 |      1      1      1      1      1

ORCL> ora space sys.obj$ advise                                                                                                       
          NAM        OBJECT_TYPE OWNER SEGMENT_NAME PARTITION_NAME ALLOCATED_KBYTES USED_KBYTES RECLAIMABLE_KBYTES COMMAND ATTR1 ATTR2
    ---------------- ----------- ----- ------------ -------------- ---------------- ----------- ------------------ ------- ----- -----
    Object: SYS.OBJ$ --total--   SYS   OBJ$                                   32000       23896               8104                    
        SYS.OBJ$     TABLE       SYS   OBJ$                                   10240        9623                617                    
        SYS.I_OBJ1   INDEX       SYS   I_OBJ1                                  2048        1530                518                    
        SYS.I_OBJ3   INDEX       SYS   I_OBJ3                                   256         151                105                    
        SYS.I_OBJ2   INDEX       SYS   I_OBJ2                                  8192        5490               2702                    
        SYS.I_OBJ5   INDEX       SYS   I_OBJ5                                  8192        5491               2701                    
        SYS.I_OBJ4   INDEX       SYS   I_OBJ4                                  3072        1612               1460                    

    --[[
        @CHECK_ACCESS: dbms_space/dba_objects/dba_tablespaces={}
        @check_access_dba: dba_objects={dba_} default={_all}
        @check_access_segs: dba_segments={dba_segments} default={(select user owner,a.* from user_segments)}
        @ARGS: 1
        @fs5: 12.2={fs5_blocks=>v_fs5_blocks,fs5_bytes => v_fs5_bytes,} default={}
        &dep: default={0} dep={1}
    --]]
]]*/

findobj "&V1" "" 1
pro &object_type: &object_owner..&object_name
pro ==================================
set feed off sep4k on digits 0 SQLTIMEOUT 86400
VAR CUR REFCURSOR;

DECLARE
    TYPE l_ary IS TABLE OF VARCHAR2(100) INDEX BY VARCHAR2(100);
    TYPE l_grp IS TABLE OF l_ary INDEX BY VARCHAR2(100);
    v_cur SYS_REFCURSOR;
    --when p_top =1, then only display top object(ignore partition)
    CURSOR l_CursorSegs(p_owner     VARCHAR2,
                        p_segname   VARCHAR2,
                        p_partition VARCHAR2,
                        p_Top       PLS_INTEGER := NULL) IS
            WITH objs AS(SELECT /*+ordered use_hash(objs lobs parts subs)*/
                    objs.segment_owner,
                    coalesce(subs.lob_name,parts.lob_name,lobs.segment_name,objs.segment_name) segment_name,
                    coalesce(subs.lob_subpartition_name,parts.lob_partition_name,objs.partition_name) partition_name,
                    objs.segment_type segment_type,
                    coalesce(lobs.tablespace_name,objs.tablespace_name) tablespace_name,
                    objs.lob_column_name,
                    lobs.index_name index_name,
                    nvl(subs.lob_indsubpart_name,parts.lob_indpart_name) index_part
            FROM    TABLE(DBMS_SPACE.OBJECT_DEPENDENT_SEGMENTS(p_owner, --objowner
                                        p_segname, --objname
                                        NULL, --partname
                                        CASE (select regexp_substr(max(x.object_type),'[^ ]+') from dba_objects x WHERE x.owner = p_owner AND x.OBJECT_name = p_segname and subobject_name is null)
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
            WHERE  objs.segment_owner = lobs.owner(+)
            AND    objs.segment_name = lobs.table_name(+)
            AND    objs.lob_column_name = lobs.column_name(+)
            AND    objs.segment_owner = parts.table_owner(+)
            AND    objs.segment_name = parts.table_name(+)
            AND    objs.lob_column_name = parts.column_name(+)
            AND    objs.partition_name=parts.partition_name(+)
            AND    objs.segment_owner = subs.table_owner(+)
            AND    objs.segment_name = subs.table_name(+)
            AND    objs.lob_column_name = subs.column_name(+)
            AND    objs.partition_name=subs.subpartition_name(+)
            AND    nvl(objs.partition_name, ' ') LIKE p_partition || '%')
        SELECT /*+leading(x seg y) use_nl(seg) use_hash(y) no_merge(y)*/
               distinct segment_owner || '.' || segment_name || nvl2(partition_name, '.' || segment_name, '') object_name,
               segment_type object_type,
               seg.*,
               (SELECT segment_space_management
                FROM   dba_tablespaces ts
                WHERE  seg.tablespace_name = ts.tablespace_name) mgnt,
               (SELECT block_size
                FROM   dba_tablespaces ts
                WHERE  seg.tablespace_name = ts.tablespace_name) block_size,
               decode(p_segname, seg.segment_name, 1, 2) lv
        FROM  (SELECT segment_owner,segment_name,segment_type,partition_name,tablespace_name from objs
               UNION  ALL
               SELECT segment_owner,index_name,'INDEX',INDEX_PART,tablespace_name from objs where index_name is not null) seg
        WHERE  (&dep=1 OR regexp_substr(:object_type,'\S+')=regexp_substr(segment_type,'\S+'));

    TYPE l_CursorSet IS TABLE OF l_CursorSegs%ROWTYPE;

    FUNCTION parseName(owner VARCHAR2, seg VARCHAR2, part VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TRIM('.' FROM owner || '.' || seg || '.' || part);
    END;

    PROCEDURE pr(p_msg VARCHAR2) IS
    BEGIN
        dbms_output.put_line(p_msg);
    END;

    FUNCTION show_space(p_segname    IN VARCHAR2,
                        p_owner      IN VARCHAR2 DEFAULT sys_context('USERENV','CURRENT_SCHEMA'),
                        p_partition  IN VARCHAR2 DEFAULT NULL,
                        p_ignoreCase IN BOOLEAN := TRUE) RETURN l_grp AS
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
        v_expired_blocks     int;
        v_expired_bytes      int;
        v_unexpired_blocks   int;
        v_unexpired_bytes    int;
        v_parentseg          VARCHAR2(256);
        v_segname            VARCHAR2(200) := p_segname;
        v_owner              VARCHAR2(128) := p_owner;
        v_partition          VARCHAR2(128) := p_partition;
        v_Level              NUMBER(1);
        v_result             l_grp;
        v_group              l_CursorSet;
        v_tag                VARCHAR2(100);

        PROCEDURE st(p_label IN VARCHAR2, p_val VARCHAR2, p_tag VARCHAR2 := NULL) IS
            v_tmp l_ary;
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
        BEGIN
            st(p_label, nvl(rd(p_label, tag), 0) + NVL(p_num, 0), tag);
            IF tag NOT LIKE '@%' THEN
                calc(p_label, p_num, '@all');
                calc(p_label, p_num, '@level' || rd('@level', tag));
            END IF;
        END;
    BEGIN
        --upper-case when ignoring case
        IF NVL(p_ignoreCase, TRUE) THEN
            v_segname   := TRIM(upper(v_segname));
            v_owner     := TRIM(upper(v_owner));
            v_partition := TRIM(upper(v_partition));
        END IF;
        --define root object

        st('@target', parseName(v_owner, v_segname, v_partition), '@all');
        st('@type', 'UNKNOWN', '@all');
        st('@level', 0, '@all');
        --read segment list
        OPEN l_CursorSegs(p_owner, p_segname, p_partition);
        FETCH l_CursorSegs BULK COLLECT
            INTO v_group;
        CLOSE l_CursorSegs;
        --handle the situation that no matched records found
        IF v_group.count = 0 THEN
            st('@msg', 'Object [' || rd('@target', '@all') || '] doesn''t exist!', '@all');
            RETURN v_result;
        END IF;

        --start fetching space statistics for each segments
        FOR i IN 1 .. v_group.count LOOP
            v_tag := v_group(i).segment_name;
            st('@level', v_group(i).lv);
            st('@type', v_group(i).segment_type);
            st('@type', v_group(i).object_type,'@all');
            BEGIN
                v_total_blocks:=NULL;
                v_total_bytes :=NULL;
                IF v_group(i).mgnt = 'AUTO' THEN
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
                        v_free_blks := v_fs1_blocks + v_fs2_blocks + v_fs3_blocks + v_fs4_blocks;
                        -- This is only a estimated value, not a exactly value
                        v_free_bytes := v_fs1_bytes * 1 / 8 + v_fs2_bytes * 3 / 8 + v_fs3_bytes * 5 / 8 +v_fs4_bytes * 7 / 8+ v_fs5_bytes;
                        calc('HWM: FS1 Blocks(01%-25% Free)', v_fs1_blocks);
                        calc('HWM: FS2 Blocks(25%-50% Free)', v_fs2_blocks);
                        calc('HWM: FS3 Blocks(50%-75% Free)', v_fs3_blocks);
                        calc('HWM: FS4 Blocks(75%-100% Free)', v_fs4_blocks);
                        IF v_fs5_blocks IS NOT NULL THEN
                            calc('HWM: FS5 Blocks(100% Free)', v_fs5_blocks);
                        END IF;
                        calc('HWM: Full Blocks', v_full_blocks);
                        calc('HWM: Full MBytes', round(v_full_bytes / 1024 / 1024,2));
                        calc('HWM: Free Blocks(Est)', v_free_blks);
                    EXCEPTION WHEN OTHERS THEN
                    $IF DBMS_DB_VERSION.VERSION>10  $THEN
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
                        calc('LOB: Expired Blocks', v_expired_blocks);
                        calc('LOB: Expired MBytes', round(v_expired_bytes/1024/1024,2));
                        calc('LOB: Unexpired Blocks', v_unexpired_blocks);
                        calc('LOB: Unexpired MBytes', round(v_unexpired_bytes/1024/1024,2));
                        calc('LOB: Used Blocks', v_unused_blocks);
                        calc('LOB: Used MBytes', round(v_unused_bytes/1024/1024,2));
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
                    calc('HWM: Free Blocks',v_free_blks);
                END IF;

                calc('HWM: Free MBytes(Est)', round(v_free_bytes / 1024 / 1024,2));

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
                calc('ABOVE HWM: Unused MBytes', Round(v_unused_bytes / 1024/1024,2));
                calc('HWM: Last Used File#',v_LastUsedExtFileId);
                calc('HWM: Last Used Block#',v_LastUsedExtBlockId);
                calc('HWM: Last Used Blocks',v_last_used_block);
                calc('HWM: * Total Blocks *', v_total_blocks - v_unused_blocks);
                calc('HWM: * Total MBytes *', Round((v_total_blocks - v_unused_blocks)*v_group(i).block_size/1024/1024,2));
                calc('HWM: Unformatted Blocks', greatest(nvl(v_unformatted_blocks,0),v_total_blocks - v_unused_blocks - v_free_blks - v_full_blocks));
            EXCEPTION WHEN OTHERS THEN
                IF SQLCODE=-1031 THEN
                    RAISE;
                END IF;
            END;
            calc('Total: Segments', 1);
            calc('Total: Blocks', v_total_blocks);
            calc('Total: KBytes', v_total_bytes / 1024);
            calc('Total: MBytes', Round(v_total_bytes / 1024 / 1024,2));
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

    --split input string into 3 fields: owner, segment_name and partition name
    FUNCTION analyze_target(p_target VARCHAR2, p_ignoreCase BOOLEAN) RETURN l_ary IS
        v_ary         l_ary;
        v_uncl_array dbms_utility.uncl_array;
        v_count      PLS_INTEGER;
    BEGIN
        v_ary('owner'):=:object_owner;
        v_ary('segment'):=:object_name;
        v_ary('partition'):=:object_subname;
        v_ary('object_id'):=:object_id;
        v_ary('object_type'):=:object_type;
        RETURN v_ary;
    END;

    FUNCTION analyze_list(p_list VARCHAR2, p_ignoreCase BOOLEAN) RETURN l_grp AS
        v_ary        l_ary;
        v_uncl_array dbms_utility.uncl_array;
        v_count      PLS_INTEGER;
        v_group      l_grp;
        v_uniq       l_ary;
        v_obj        VARCHAR2(100);
    BEGIN
        dbms_utility.comma_to_table(REPLACE(p_list, ''''), v_count, v_uncl_array);
        FOR i IN 1 .. v_count LOOP
            IF TRIM(v_uncl_array(i)) IS NOT NULL THEN
                v_ary := analyze_target(TRIM(v_uncl_array(i)), p_ignoreCase);
                v_obj := v_ary('segment') || '.' || v_ary('owner') || '.' || v_ary('partition');
                IF NOT v_uniq.exists(v_obj) THEN
                    v_uniq(v_obj) := 1;
                    v_group(v_group.count + 1) := v_ary;
                END IF;
            END IF;
        END LOOP;
        RETURN v_group;
    END;

    PROCEDURE print(p_cur        OUT SYS_REFCURSOR,
                    p_target     VARCHAR2,
                    p_ignoreCase IN BOOLEAN := TRUE,
                    p_includedps IN PLS_INTEGER := 1) IS
        v_target l_ary := analyze_target(p_target, p_ignoreCase);
        v_ary    l_grp;
        v_titles l_ary;
        v_rows   l_ary;
        v_all    l_ary;
        v_idx    VARCHAR2(100);
        v_fmt    VARCHAR2(20) := 'fm999,999,999,990';
        v_fix    PLS_INTEGER := 40;
        v_size   PLS_INTEGER := length(v_fmt);
        v_title  VARCHAR2(300) := rpad('ITEM', v_fix);
        v_xml    CLOB := '<ROWSET>';
        v_sql    VARCHAR2(32767);
    BEGIN
        dbms_output.enable(NULL);
        IF v_target('segment') is null then
            pr('Cannot find target object!');
            return;
        end if;
        v_target('owner'):=:object_owner;
        v_target('segment'):=:object_name;
        v_target('partition'):=:object_subname;
        v_ary := show_space(p_segname    => v_target('segment'),
                            p_owner      => v_target('owner'),
                            p_partition  => v_target('partition'),
                            p_ignoreCase => p_ignoreCase);

        IF v_ary('@all') ('@msg') != 'done' THEN
            pr(v_ary('@all') ('@msg'));
            RETURN;
        END IF;

        v_sql :='SELECT extractvalue(column_value,''/ROW/C0'') Item,';
        v_all:=v_ary('@all');

        if not v_ary.exists('@level2') then
            v_ary.delete('@all');
        end if;

        v_idx := v_ary.first;
        LOOP
            IF v_ary(v_idx).exists('@level') and v_ary(v_idx)('@level')=1 THEN
                v_ary.delete(v_idx);
            ELSE
                v_titles(v_titles.count + 1) := v_idx;
                v_Sql:=v_sql||'0+extractvalue(column_value,''/ROW/C'||v_titles.count||''') ';
                IF v_ary(v_idx).exists('@title') THEN
                    v_sql:=v_sql||'"'||v_ary(v_idx)('@title')||'"';
                ELSE
                    v_sql:=v_sql||'"'||v_idx||'"';
                END IF;
                v_sql:=v_sql||',';
                if v_idx='@level2' then
                    v_sql:=v_sql||' ''|'' "*",';
                end if;
            END IF;
            v_idx := v_ary.next(v_idx);
            EXIT WHEN v_idx IS NULL;
        END LOOP;
        v_sql:=trim(',' from v_sql);


        v_idx := v_all.first;
        LOOP
            IF v_idx NOT LIKE '@%' THEN
                v_rows(v_rows.count + 1) := v_idx;
            END IF;
            v_idx := v_all.next(v_idx);
            EXIT WHEN v_idx IS NULL;
        END LOOP;

        FOR i IN 1 .. v_rows.count LOOP
            v_xml := v_xml || '<ROW><C0>'||v_rows(i)||'</C0>';
            FOR j IN 1 .. v_titles.count LOOP
                IF v_ary(v_titles(j)).exists(v_rows(i)) THEN
                    v_xml := v_xml || '<C' || j || '>' || v_ary(v_titles(j))(v_rows(i)) || '</C' || j || '>';
                END IF;
            END LOOP;
            v_xml := v_xml || '</ROW>' || chr(10);
        END LOOP;
        v_xml := v_xml || '</ROWSET>';
        v_sql := v_sql||' from table(xmlsequence(extract(xmltype(:1),''/ROWSET[1]/ROW'')))';
        --dbms_output.put_line(v_sql);
        OPEN p_cur for v_sql using v_xml;
    END;

    PROCEDURE seg_advise(p_cur        OUT SYS_REFCURSOR,
                         p_list       VARCHAR2,
                         p_ignoreCase IN BOOLEAN := TRUE,
                         p_includedps IN PLS_INTEGER := 1) IS
        v_list  l_grp := analyze_list(p_list, p_ignoreCase);
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
            v_xml := v_xml.appendChildXml('/ROOT[1]',
                                          XMLTYPE('<NODE id="' || id || '" name="' || nam ||
                                                  '" owner="' || owner || '" seg="' || seg ||
                                                  '" part="' || part || '" segtype="' || typ ||
                                                  '"/>'));
        END;

    BEGIN
        --execute dbms_workload_repository.create_snapshot('ALL');
        IF v_list.count = 0 THEN
            RETURN;
        END IF;

        SELECT COUNT(1) INTO v_objid FROM dba_advisor_tasks WHERE task_name = v_task;
        IF v_objid > 0 THEN
            DBMS_ADVISOR.delete_task(task_name => v_task);
        END IF;

        DBMS_ADVISOR.create_task(advisor_name => 'Segment Advisor', task_name => v_task);
        DBMS_ADVISOR.set_task_parameter(task_name => v_task,
                                        parameter => 'RECOMMEND_ALL',
                                        VALUE     => 'TRUE');
        FOR i IN 1 .. v_list.count LOOP
            OPEN l_CursorSegs(v_list(i) ('owner'),
                              v_list(i) ('segment'),
                              v_list(i) ('partition'),
                              1);
            FETCH l_CursorSegs BULK COLLECT
                INTO v_segs;
            CLOSE l_CursorSegs;

            v_top := parseName('Object: ' || v_list(i) ('owner'),
                               v_list(i) ('segment'),
                               v_list(i) ('partition'));
            NewNode(lpad(i, 4, 0),
                    v_top,
                    v_list(i) ('owner'),
                    v_list(i) ('segment'),
                    v_list(i) ('partition'),
                    '--total--');
            v_seek := 0;
            FOR j IN 1 .. v_segs.count LOOP

                DBMS_ADVISOR.create_object(task_name   => v_task,
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
                IF 'Object: ' || v_node || '.' LIKE v_top || '.%' AND v_seek = 0 THEN
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
        DBMS_ADVISOR.execute_task(task_name => v_task);
        FOR r IN (SELECT a.*, b.more_info
                  FROM   dba_advisor_objects a, dba_advisor_findings b
                  WHERE  a.task_name = v_task
                  AND    a.task_id = b.task_id(+)
                  AND    a.object_id = b.object_id(+)) LOOP
            v_node := parseName(r.attr1, r.attr2, r.attr3);
            IF NOT v_items.exists(v_node) THEN
                NewNode(v_items(r.attr1 || '.' || r.attr2) ('id') || lpad(r.object_id, 4, 0),
                        v_node,
                        r.attr1,
                        r.attr2,
                        r.attr3,
                        r.type);
            END IF;
            IF r.more_info IS NOT NULL THEN
                dbms_space.parse_space_adv_info(r.more_info, v_used, v_alloc, v_free);
                IF v_alloc IS NOT NULL THEN
                    v_xml := v_xml.appendChildXML('/ROOT[1]/NODE[@name="' || v_node || '"]',
                                                  xmltype('<ATTR><OBJECT_ID>' || R.OBJECT_ID || '</OBJECT_ID><ALLOC>' || v_alloc || '</ALLOC><USED>' || v_used || '</USED><FREE>' || v_free || '</FREE></ATTR>')
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
                   Round(SUM(allocated_space) OVER(ORDER BY rpad(ID, 12, 9) + 0
                              RANGE BETWEEN rpad(ID, 12, 9) - rpad(ID, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) allocated_kbytes,
                   Round(SUM(used_space) OVER(ORDER BY rpad(ID, 12, 9) + 0
                              RANGE BETWEEN rpad(ID, 12, 9) - rpad(ID, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) used_kbytes,
                   Round(SUM(reclaimable_space)
                         OVER(ORDER BY rpad(ID, 12, 9) + 0
                              RANGE BETWEEN rpad(ID, 12, 9) - rpad(ID, 12, 0) PRECEDING AND 0
                              FOLLOWING) / 1024) reclaimable_kbytes,
                   b.command,
                   b.attr1,
                   b.attr2
            FROM   (SELECT Extractvalue(COLUMN_VALUE, '/NODE/@id') ID,
                           Extractvalue(COLUMN_VALUE, '/NODE/@name') NAME,
                           Extractvalue(COLUMN_VALUE, '/NODE/@segtype') object_type,
                           Extractvalue(COLUMN_VALUE, '/NODE/@owner') owner,
                           Extractvalue(COLUMN_VALUE, '/NODE/@seg') segment_name,
                           Extractvalue(COLUMN_VALUE, '/NODE/@part') partition_name,
                           Extractvalue(COLUMN_VALUE, '/NODE/OBJECT_ID[1]') object_id,
                           Extractvalue(COLUMN_VALUE, '/NODE/ALLOC[1]') allocated_space,
                           Extractvalue(COLUMN_VALUE, '/NODE/USED[1]') used_space,
                           Extractvalue(COLUMN_VALUE, '/NODE/FREE[1]') reclaimable_space
                    FROM   TABLE(XMLSEQUENCE(EXTRACT(v_xml, '/ROOT[1]/NODE')))) a,
                   DBA_ADVISOR_ACTIONS B
            WHERE  B.TASK_NAME(+) = v_task
            AND    B.OBJECT_ID(+) = a.object_id
            ORDER  BY id;

    END;
BEGIN
    if lower(nvl(:V2,'x'))!='advise' then
        print(v_cur,:V1);
    else
        seg_advise(v_cur,:V1);
    end if;
    :cur := v_cur;
EXCEPTION
    WHEN OTHERS THEN raise_application_error(-20001,sqlerrm);
END;
/
