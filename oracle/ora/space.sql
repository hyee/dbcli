/*[[
Show object's space. Usage: ora space [-L] <[owner.]<object_name>[.PARTITION_NAME]>[,...]] [1-7]
   &V9: P={1},l={2}
]]*/

VAR CUR REFCURSOR;

DECLARE
    TYPE l_ary IS TABLE OF VARCHAR2(100) INDEX BY VARCHAR2(100);
    TYPE l_grp IS TABLE OF l_ary INDEX BY VARCHAR2(100);
    --when p_top =1, then only display top object(ignore partition)
    CURSOR l_CursorSegs(p_owner      VARCHAR2,
                        p_segname    VARCHAR2,
                        p_partition  VARCHAR2,
                        p_includedps PLS_INTEGER,
                        p_Top        PLS_INTEGER := NULL) IS
        SELECT DISTINCT segment_owner owner,
               segment_name seg,
               decode(p_Top || p_partition, '1', '', partition_name) pname,
               decode(p_Top || p_partition,
                      '1',
                      REPLACE(segment_type, ' PARTITION'),
                      segment_type) typ,
               nvl2(p_Top,
                    NULL,
                    (SELECT segment_space_management
                     FROM   dba_tablespaces ts
                     WHERE  seg.tablespace_name = ts.tablespace_name)) mgnt,
               nvl2(p_Top,
                    NULL,
                    (SELECT block_size
                     FROM   dba_tablespaces ts
                     WHERE  seg.tablespace_name = ts.tablespace_name)) block_size,
               nvl2(p_Top,
                    NULL,
                    (SELECT MAX(extents)
                     FROM   dba_segments
                     WHERE  owner = seg.segment_owner
                     AND    segment_name = seg.segment_name
                     AND    NVL(partition_name, ' ') = NVL(seg.partition_name, ' '))) exts
        FROM   dba_objects x,
               TABLE(DBMS_SPACE.OBJECT_DEPENDENT_SEGMENTS(x.owner,
                                                          x.OBJECT_name,
                                                          '',
                                                          CASE x.object_type
                                                              WHEN 'TABLE' THEN
                                                               1
                                                              WHEN 'TABLE PARTITION' THEN
                                                               7
                                                              WHEN 'TABLE SUBPARTITION' THEN
                                                               9
                                                              WHEN 'INDEX' THEN
                                                               3
                                                              WHEN 'INDEX PARTITION' THEN
                                                               8
                                                              WHEN 'INDEX SUBPARTITION' THEN
                                                               10
                                                              WHEN 'CLUSTER' THEN
                                                               4
                                                              WHEN 'NESTED_TABLE' THEN
                                                               2
                                                              WHEN 'MATERIALIZED VIEW' THEN
                                                               13
                                                              WHEN 'MATERIALIZED VIEW LOG' THEN
                                                               14
                                                          END)) seg
        WHERE  owner = p_owner
        AND    OBJECT_name = p_segname
        AND    nvl(subobject_name, ' ') = nvl(p_partition, ' ')
        AND    (bitand(p_includedps, 2) > 0 OR seg.segment_name = p_segname);

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
                        p_owner      IN VARCHAR2 DEFAULT USER,
                        p_partition  IN VARCHAR2 DEFAULT NULL,
                        p_ignoreCase IN BOOLEAN := TRUE,
                        p_includedps IN PLS_INTEGER := 1) RETURN l_grp AS
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
        v_full_blocks        INT;
        v_full_bytes         INT;
        v_free_bytes         INT;
        v_parentseg          VARCHAR2(61);
        v_segname            VARCHAR2(200) := p_segname;
        v_owner              VARCHAR2(30) := p_owner;
        v_partition          VARCHAR2(30) := p_partition;
        v_result             l_grp;
        v_group              l_CursorSet;
    
        PROCEDURE st(p_label IN VARCHAR2, p_val VARCHAR2, p_tag VARCHAR2 := '@all') IS
            v_tmp l_ary;
        BEGIN
            IF p_tag = '@all' OR bitand(p_includedps, 7) = 7 THEN
                IF NOT v_result.exists(p_tag) THEN
                    v_tmp('@target') := p_tag;
                    v_result(p_tag) := v_tmp;
                END IF;
                v_result(p_tag)(p_label) := p_val;
            END IF;
        END;
    
        FUNCTION rd(p_label IN VARCHAR2, p_tag VARCHAR2 := '@all') RETURN VARCHAR2 IS
        BEGIN
            IF NOT v_result.exists(p_tag) OR NOT v_result(p_tag).exists(p_label) THEN
                st(p_label, '', p_tag);
                RETURN '';
            END IF;
            RETURN v_result(p_tag)(p_label);
        END;
    
        PROCEDURE calc(p_label IN VARCHAR2, p_num IN NUMBER, p_tag VARCHAR2 := '@all') IS
        BEGIN
            st(p_label, nvl(rd(p_label, p_tag), 0) + NVL(p_num, 0), p_tag);
            IF p_tag = '@all' AND bitand(p_includedps, 7) = 7 THEN
                calc(p_label, p_num, v_segname);
                IF v_segname != v_parentseg THEN
                    calc(p_label, p_num, v_parentseg);
                END IF;
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
        st('@target', parseName(v_owner, v_segname, v_partition));
        st('@level', 0);
        --read segment list
        OPEN l_CursorSegs(p_owner, p_segname, p_partition, p_includedps);
        FETCH l_CursorSegs BULK COLLECT
            INTO v_group;
        CLOSE l_CursorSegs;
        --handle the situation that no matched records found
        IF v_group.count = 0 THEN
            IF p_includedps = 2 THEN
                st('@msg', 'Target object doesn''t have depended objects.');
            ELSE
                st('@msg', 'Object [' || rd('@target') || '] doesn''t exist!');
            END IF;
            RETURN v_result;
        END IF;
    
        --start fetching space statistics for each segments
        FOR i IN 1 .. v_group.count LOOP
            v_parentseg := parseName(v_group(i).owner, v_group(i).seg, '');
            v_segname   := parseName(v_group(i).owner, v_group(i).seg, v_group(i).pname);
            st('@type', v_group(i).typ, v_segname);
            st('@level', 1, v_segname);
            IF v_parentseg != v_segname THEN
                st('@type', REPLACE(v_group(i).typ, ' PARTITION'), v_parentseg);
                st('@level', 1, v_parentseg);
                st('@level', 2, v_segname);
            END IF;
            IF v_segname || '.' LIKE rd('@target') || '.%' THEN
                st('@type', REPLACE(v_group(i).typ, ' PARTITION', '(Partitioned)'));
            END IF;
            calc('Total Extents', v_group(i).exts);
            IF v_group(i).mgnt = 'AUTO' THEN
                dbms_space.space_usage(segment_owner      => v_group(i).owner,
                                       segment_name       => v_group(i).seg,
                                       segment_type       => v_group(i).typ,
                                       partition_name     => v_group(i).pname,
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
                                       full_blocks        => v_full_blocks,
                                       full_bytes         => v_full_bytes);
                v_free_blks := v_fs1_blocks + v_fs2_blocks + v_fs3_blocks + v_fs4_blocks;
                -- This is only a estimated value, not a exactly value
                v_free_bytes := v_fs1_bytes * 1 / 8 + v_fs2_bytes * 3 / 8 +
                                v_fs3_bytes * 5 / 8 + v_fs4_bytes * 7 / 8;
            ELSE
                dbms_space.free_blocks(segment_owner     => v_group(i).owner,
                                       segment_name      => v_group(i).seg,
                                       partition_name    => v_group(i).pname,
                                       segment_type      => v_group(i).typ,
                                       freelist_group_id => 0,
                                       free_blks         => v_free_blks);
                v_free_bytes := v_free_blks * v_group(i).block_size;
            END IF;
            calc('Unformatted Blocks', v_unformatted_blocks);
            calc('FS1 Blocks(00-25)', v_fs1_blocks);
            calc('FS2 Blocks(25-50)', v_fs2_blocks);
            calc('FS3 Blocks(50-75)', v_fs3_blocks);
            calc('FS4 Blocks(75-100)', v_fs4_blocks);
            calc('Full Blocks', v_full_blocks);
            calc('Free Blocks', v_free_blks);
            calc('Total MBytes(Free)', round(v_free_bytes / 1024 / 1024));
            dbms_space.unused_space(segment_owner             => v_group(i).owner,
                                    segment_name              => v_group(i).seg,
                                    segment_type              => v_group(i).typ,
                                    partition_name            => v_group(i).pname,
                                    total_blocks              => v_total_blocks,
                                    total_bytes               => v_total_bytes,
                                    unused_blocks             => v_unused_blocks,
                                    unused_bytes              => v_unused_bytes,
                                    LAST_USED_EXTENT_FILE_ID  => v_LastUsedExtFileId,
                                    LAST_USED_EXTENT_BLOCK_ID => v_LastUsedExtBlockId,
                                    LAST_USED_BLOCK           => v_last_used_block);
            calc('Total Blocks', v_total_blocks);
            calc('Total KBytes', v_total_bytes / 1024);
            calc('Total MBytes', TRUNC(v_total_bytes / 1024 / 1024));
            calc('Unused Blocks', v_unused_blocks);
            calc('Unused KBytes', v_unused_bytes / 1024);
            calc('Last Ext FileID', v_LastUsedExtFileId);
            calc('Last Ext BlockID', v_LastUsedExtBlockId);
            calc('Last Block', v_last_used_block);
        END LOOP;
        --this setting indicates that the fetching has completed
        v_result('@all')('@msg') := 'done';
        RETURN v_result;
    END;

    --split input string into 3 fields: owner, segment_name and partition name
    FUNCTION analyze_target(p_target VARCHAR2, p_ignoreCase BOOLEAN) RETURN l_ary IS
        v_uncl_array dbms_utility.uncl_array;
        v_count      PLS_INTEGER;
        v_ary        l_ary;
        v_target     VARCHAR2(100) := REPLACE(p_target, '.', ',');
    BEGIN
        IF NVL(p_ignoreCase, TRUE) THEN
            v_target := upper(TRIM(v_target));
        END IF;
        v_target := REPLACE(REPLACE(v_target, '"'), '''');
        v_ary('owner') := USER;
        v_ary('segment') := NULL;
        v_ary('partition') := NULL;
        dbms_utility.comma_to_table(v_target, v_count, v_uncl_array);
        IF v_count <= 1 THEN
            v_ary('segment') := v_target;
        ELSIF v_count >= 3 THEN
            v_ary('owner') := v_uncl_array(1);
            v_ary('segment') := v_uncl_array(2);
            v_ary('partition') := v_uncl_array(3);
        ELSE
            SELECT COUNT(1)
            INTO   v_count
            FROM   dba_segments
            WHERE  owner = v_uncl_array(1)
            AND    segment_name = v_uncl_array(2);
            IF v_count > 0 THEN
                v_ary('owner') := v_uncl_array(1);
                v_ary('segment') := v_uncl_array(2);
            ELSE
                v_ary('segment') := v_uncl_array(1);
                v_ary('partition') := v_uncl_array(2);
            END IF;
        END IF;
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
                v_obj := v_ary('segment') || '.' || v_ary('owner') || '.' ||
                         v_ary('partition');
                IF NOT v_uniq.exists(v_obj) THEN
                    v_uniq(v_obj) := 1;
                    v_group(v_group.count + 1) := v_ary;
                END IF;
            END IF;
        END LOOP;
        RETURN v_group;
    END;

    PROCEDURE show_list(p_cur        OUT SYS_REFCURSOR,
                        p_list       VARCHAR2,
                        p_ignoreCase IN BOOLEAN := TRUE,
                        p_includedps IN PLS_INTEGER := 1) IS
        v_ary    l_ary;
        v_titles l_ary;
        v_seq    PLS_INTEGER := 0;
        v_obj    VARCHAR2(100);
        v_idx    VARCHAR2(100);
        v_line   VARCHAR2(2000);
        v_print  l_grp := analyze_list(p_list, p_ignoreCase);
        v_list   l_grp;
        v_xml    xmltype := xmltype('<ROWSET/>');
        v_sql    VARCHAR2(32767);
    BEGIN
        v_sql := 'SELECT Extractvalue(COLUMN_VALUE, ''/ROW[1]/@name'') SEGMENT_NAME,Extractvalue(COLUMN_VALUE, ''/ROW[1]/@type'') SEGMENT_TYPE,';
        FOR i IN 1 .. v_print.count LOOP
            v_list := show_space(p_segname    => v_print(i) ('segment'),
                                 p_owner      => v_print(i) ('owner'),
                                 p_partition  => v_print(i) ('partition'),
                                 p_ignoreCase => p_ignoreCase,
                                 p_includedps => p_includedps);
            v_ary  := v_list('@all');
            --remove those objects that fetching isn't completed
            IF v_ary('@msg') = 'done' THEN
                v_obj := v_ary.first;
                LOOP
                    EXIT WHEN v_obj IS NULL;
                    IF NOT v_titles.exists(v_obj) AND v_obj NOT LIKE '@%' THEN
                        v_titles(v_obj) := 'attr' || v_titles.count;
                        v_sql := v_sql || chr(10) || lpad(' ', 7) ||
                                 'Extractvalue(COLUMN_VALUE,''/ROW[1]/@' ||
                                 v_titles(v_obj) || ''')+0 "' || v_obj || '",';
                    END IF;
                    v_obj := v_ary.next(v_obj);
                END LOOP;
                v_idx := v_list.first;
                LOOP
                    EXIT WHEN v_idx IS NULL;
                    v_ary  := v_list(v_idx);
                    v_seq  := v_seq + 1;
                    v_line := utl_lms.format_message('<ROW seq="%d" name="%s" type="%s"',
                                                     v_seq,
                                                     rpad(' ', 4 * v_ary('@level')) ||
                                                     v_ary('@target'),
                                                     v_ary('@type'));
                    v_obj  := v_titles.first;
                    LOOP
                        EXIT WHEN v_obj IS NULL;
                        IF v_ary.exists(v_obj) THEN
                            v_line := v_line || ' ' || v_titles(v_obj) || '="' ||
                                      v_ary(v_obj) || '"';
                            v_obj  := v_titles.next(v_obj);
                        END IF;
                    END LOOP;
                    v_line := v_line || ' />';
                    v_xml  := v_xml.appendChildXML('/ROWSET[1]', xmltype(v_line));
                    v_idx  := v_list.next(v_idx);
                END LOOP;
            END IF;
        END LOOP;
    
        v_sql := TRIM(',' FROM v_sql) || chr(10) ||
                 'FROM TABLE(XMLSEQUENCE(EXTRACT(xmltype(:1), ''/ROWSET[1]/*'')))' ||
                 chr(10) || 'ORDER BY Extractvalue(COLUMN_VALUE, ''/ROW[1]/@seq'')+0';
        OPEN p_cur FOR v_sql
            USING v_xml.getclobval;
    END;

    PROCEDURE print(p_target     VARCHAR2,
                    p_ignoreCase IN BOOLEAN := TRUE,
                    p_includedps IN PLS_INTEGER := 1) IS
        v_target l_ary := analyze_target(p_target, p_ignoreCase);
        v_ary    l_ary;
        v_iry    l_ary;
        v_idx    VARCHAR2(100);
        v_fmt    VARCHAR2(20) := 'fm999,999,999,990';
        v_fix    PLS_INTEGER := 40;
        v_size   PLS_INTEGER := length(v_fmt);
        v_title  VARCHAR2(300) := rpad('ITEM', v_fix);
    BEGIN
        dbms_output.enable(NULL);
        -- when p_includedps=7, then will display 3 fields: object,dependencies and total
        IF p_includedps = 7 THEN
            v_ary   := show_space(v_target('segment'),
                                  v_target('owner'),
                                  v_target('partition'),
                                  p_ignoreCase,
                                  1) ('@all');
            v_iry   := show_space(v_target('segment'),
                                  v_target('owner'),
                                  v_target('partition'),
                                  p_ignoreCase,
                                  2) ('@all');
            v_title := v_title || lpad('OBJECT', v_size) || lpad('DEPENDENCIES', v_size) ||
                       lpad('TOTAL', v_size);
            --if the fetching doesn't complete(i.e. no related dependencies), then initialize its values as zero
            IF v_iry('@msg') != 'done' THEN
                v_iry := v_ary;
                v_idx := v_iry.first;
                LOOP
                    EXIT WHEN v_idx IS NULL;
                    v_iry(v_idx) := 0;
                    v_idx := v_iry.next(v_idx);
                END LOOP;
            END IF;
        ELSE
            -- otherwise only display one field
            v_title := v_title || lpad('TOTAL', v_size);
            v_ary   := show_space(p_segname    => v_target('segment'),
                                  p_owner      => v_target('owner'),
                                  p_partition  => v_target('partition'),
                                  p_ignoreCase => p_ignoreCase,
                                  p_includedps => p_includedps) ('@all');
        
            IF v_ary('@msg') != 'done' THEN
                pr(v_ary('@msg'));
                RETURN;
            END IF;
        END IF;
        pr('Object  Name        : ' || v_ary('@target'));
        pr('Object  Type        : ' || v_ary('@type'));
        pr(rpad('=', v_fix + v_size, '='));
        pr(v_title);
        pr(rpad('-', length(v_title), '-'));
        v_idx := v_ary.first;
        --start organizating output
        LOOP
            EXIT WHEN v_idx IS NULL;
            IF v_idx NOT LIKE '@%' AND v_ary(v_idx) >= 0 THEN
                pr(rpad(v_idx, v_fix, '.') ||
                   lpad(TO_CHAR(v_ary(v_idx) + 0, v_fmt), v_size) || --
                   CASE p_includedps WHEN 7 THEN
                   lpad(TO_CHAR(v_iry(v_idx) + 0, v_fmt), v_size) ||
                   lpad(TO_CHAR(v_iry(v_idx) + v_ary(v_idx), v_fmt), v_size) END);
            END IF;
            v_idx := v_ary.next(v_idx);
        END LOOP;
    END;

    PROCEDURE seg_advise(p_cur        OUT SYS_REFCURSOR,
                         p_list       VARCHAR2,
                         p_ignoreCase IN BOOLEAN := TRUE,
                         p_includedps IN PLS_INTEGER := 1) IS
        v_list  l_grp := analyze_list(p_list, p_ignoreCase);
        v_items l_grp;
        v_segs  l_CursorSet;
        v_task  VARCHAR2(30) := 'PKG_SPACE_SEGMENT_ADVISE';
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
                              p_includedps,
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
                                           object_type => v_segs(j).typ,
                                           attr1       => v_segs(j).owner,
                                           attr2       => v_segs(j).seg,
                                           attr3       => v_segs(j).pname,
                                           attr4       => 'null',
                                           attr5       => NULL,
                                           object_id   => v_objid);
                v_node := parseName(v_segs(j).owner, v_segs(j).seg, v_segs(j).pname);
                v_id   := lpad(i, 4, 0) || lpad(j + 1, 4, 0);
                IF 'Object: ' || v_node || '.' LIKE v_top || '.%' AND v_seek = 0 THEN
                    v_id   := lpad(i, 4, 0) || lpad(1, 4, 0);
                    v_seek := 1;
                END IF;
                NewNode(v_id,
                        v_node,
                        v_segs(j).owner,
                        v_segs(j).seg,
                        v_segs(j).pname,
                        v_segs(j).typ);
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
                NewNode(v_items(r.attr1 || '.' || r.attr2)
                        ('id') || lpad(r.object_id, 4, 0),
                        v_node,
                        r.attr1,
                        r.attr2,
                        r.attr3,
                        r.type);
            END IF;
            IF r.more_info IS NOT NULL THEN
                dbms_space.parse_space_adv_info(r.more_info, v_used, v_alloc, v_free);
                IF v_alloc IS NOT NULL THEN
                    v_xml := v_xml.appendChildXML('/ROOT[1]/NODE[@name="' || v_node ||
                                                  '"]',
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
                   Round(SUM(allocated_space)
                         OVER(ORDER BY rpad(ID, 12, 9) + 0
                              RANGE BETWEEN rpad(ID, 12, 9) - rpad(ID, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) allocated_kbytes,
                   Round(SUM(used_space)
                         OVER(ORDER BY rpad(ID, 12, 9) + 0
                              RANGE BETWEEN rpad(ID, 12, 9) - rpad(ID, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) used_kbytes,
                   Round(SUM(reclaimable_space)
                         OVER(ORDER BY rpad(ID, 12, 9) + 0
                              RANGE BETWEEN rpad(ID, 12, 9) - rpad(ID, 12, 0)
                              PRECEDING AND 0 FOLLOWING) / 1024) reclaimable_kbytes,
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

    PROCEDURE show_tablespaces(p_cursor IN OUT SYS_REFCURSOR) IS
    BEGIN
        --static sql does'nt support "wm_concat(DISTINCT)", use dynamic sql instead.
        OPEN p_cursor FOR --
         q'{SELECT a.tablespace_name,
                   round(a.bytes_alloc / power(1024, 3), 2) "Total(GB)",
                   round(nvl(b.bytes_free, 0) / power(1024, 3), 2) "Free(GB)",
                   round((a.bytes_alloc - nvl(b.bytes_free, 0)) / power(1024, 3), 2) "Used(GB)",
                   round((nvl(b.bytes_free, 0) / a.bytes_alloc) * 100, 2) "Free(%)",
                   round(maxbytes / power(1024, 3), 2) "File Size(GB)",
                   Round(FSFI, 2) "FSFI(%)",
                   disks "Disks"
            FROM   (SELECT f.tablespace_name,
                           SUM(f.bytes) bytes_alloc,
                           SUM(decode(f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxbytes,
                           wmsys.wm_concat(regexp_substr(f.file_name,'\w+')) disks
                    FROM   dba_data_files f
                    GROUP  BY tablespace_name) a,
                   (SELECT f.tablespace_name,
                           SUM(f.bytes) bytes_free,
                           sqrt(MAX(blocks) / SUM(blocks)) *
                           (100 / sqrt(sqrt(COUNT(blocks)))) FSFI
                    FROM   dba_free_space f
                    GROUP  BY tablespace_name) b
            WHERE  a.tablespace_name = b.tablespace_name(+)
            UNION ALL
            SELECT h.tablespace_name,
                   round(SUM(h.bytes_free + h.bytes_used) / power(1024, 3), 2) megs_alloc,
                   round(SUM((h.bytes_free + h.bytes_used) - nvl(p.bytes_used, 0)) /
                         power(1024, 3),
                         2) megs_free,
                   round(SUM(nvl(p.bytes_used, 0)) / power(1024, 3), 2) megs_used,
                   round((SUM((h.bytes_free + h.bytes_used) - nvl(p.bytes_used, 0)) /
                         SUM(h.bytes_used + h.bytes_free)) * 100,
                         2) Pct_Free,
                   round(SUM(decode(f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) /
                         power(1024, 3),
                         2),
                   NULL,
                   wmsys.wm_concat(distinct regexp_substr(f.file_name,'\w+'))
            FROM   sys.v_$TEMP_SPACE_HEADER h,
                   sys.v_$Temp_extent_pool  p,
                   dba_temp_files           f
            WHERE  p.file_id(+) = h.file_id
            AND    p.tablespace_name(+) = h.tablespace_name
            AND    f.file_id = h.file_id
            AND    f.tablespace_name = h.tablespace_name
            GROUP  BY h.tablespace_name}';
    END;
BEGIN
    IF &V9=1 THEN
        print(:V1,true,nvl(:V2,1));
    ELSE
       show_list(p_cur => :CUR,
                p_list => :V1,
                p_ignorecase => true,
                p_includedps => nvl(:V2,1));
    END IF;
END;
