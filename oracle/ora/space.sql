/*[[
Show or advice on object's space. Usage: @@NAME <[owner.]object_name[.partition_name]> [stats|advise]
    --[[
        @CHECK_ACCESS: dbms_space/dba_objects/dba_tablespaces={}
    --]]
]]*/


set feed off SQLTIMEOUT 86400
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
        FROM TABLE(DBMS_SPACE.OBJECT_DEPENDENT_SEGMENTS(
                      p_owner,--objowner
                      p_segname,--objname
                      null,--partname
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
                          WHEN 'LOB' THEN 21
                          WHEN 'LOB PARTITION' THEN 40
                          WHEN 'LOB SUBPARTITION' THEN 41
                      END)) seg--objtype
        WHERE  nvl(seg.partition_name, ' ') LIKE p_partition||'%';

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
        v_full_blocks        INT;
        v_full_bytes         INT;
        v_free_bytes         INT;
        v_expired_blocks     int;
        v_expired_bytes      int;
        v_unexpired_blocks   int;
        v_unexpired_bytes    int;
        v_parentseg          VARCHAR2(61);
        v_segname            VARCHAR2(200) := p_segname;
        v_owner              VARCHAR2(30) := p_owner;
        v_partition          VARCHAR2(30) := p_partition;
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
        st('@type', 'UNKOWN', '@all');
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
                                               full_blocks        => v_full_blocks,
                                               full_bytes         => v_full_bytes);
                        v_free_blks := v_fs1_blocks + v_fs2_blocks + v_fs3_blocks + v_fs4_blocks;
                        -- This is only a estimated value, not a exactly value
                        v_free_bytes := v_fs1_bytes * 1 / 8 + v_fs2_bytes * 3 / 8 + v_fs3_bytes * 5 / 8 +v_fs4_bytes * 7 / 8;
                        calc('HWM: FS1 Blocks(00-25)', v_fs1_blocks);
                        calc('HWM: FS2 Blocks(25-50)', v_fs2_blocks);
                        calc('HWM: FS3 Blocks(50-75)', v_fs3_blocks);
                        calc('HWM: FS4 Blocks(75-100)', v_fs4_blocks);
                        calc('HWM: Full Blocks', v_full_blocks);
                        calc('HWM: Full MBytes', round(v_full_bytes / 1024 / 1024,2));
                        calc('HWM: Free Blocks(Est)', v_free_blks);
                        calc('HWM: Unformatted Blocks', v_unformatted_blocks);
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
                calc('HWM: Total Blocks', v_total_blocks - v_unused_blocks);
                calc('HWM: Total MBytes', Round((v_total_blocks - v_unused_blocks)*v_group(i).block_size/1024/1024,2));

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
        v_target     VARCHAR2(100) :=replace(replace(p_target,'.',','),' ');
    BEGIN
        if p_ignorecase then
            v_target := upper(v_target);
        end if;
        dbms_utility.comma_to_table(regexp_replace(v_target, '[''"]'), v_count, v_uncl_array);
        for i in 1..3 loop
            if not v_uncl_array.exists(i) or v_uncl_array(i) is null then
                v_uncl_array(i) := ' ';
            end if;
            --dbms_output.put_line(i||'"'||v_uncl_array(i)||'"');
        end loop;
        select max(owner),max(object_name),max(subobject_name),max(object_id)
        into v_ary('owner'),v_ary('segment'),v_ary('partition'),v_ary('object_id')
        from (
            select /*+no_expand*/ * from dba_objects
            where owner in(sys_context('USERENV','CURRENT_SCHEMA'),v_uncl_array(1))
            and   object_type!='SYNONYM'
            and   object_name in(v_uncl_array(1),v_uncl_array(2))
            and   nvl(subobject_name,' ') in(v_uncl_array(2),v_uncl_array(3))
            order by decode(owner,sys_context('USERENV','CURRENT_SCHEMA'),1,2),nvl2(subobject_name,1,2)
        ) where rownum<2;

        IF v_ary('object_id') is null then
            raise_application_error(-20001,'Cannot find target objects!');
        end if;
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
        dbms_output.put_line('OBJECT: '||v_all('@target')||'    TYPE: '||v_all('@type'));
        OPEN p_cur for v_sql using v_xml;
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
