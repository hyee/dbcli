/*[[
    Show object size. Usage: @@NAME [-d] [[owner.]object_name[.PARTITION_NAME]|-a]
    If not specify the parameter, then list the top 100 segments.
    option '-d': used to detail in segment level, otherwise in name level, only shows the top 1000 segments
    option '-a': based on all schemas, default as current schema only.
    --[[
        @CHECK_ACCESS: sys.user$/sys.obj$/sys.seg$={}
        &OPT2: default={}, d={partition_name,}
        &OPT3: default={null}, d={partition_name}
        &OPT4: default={OWNER=SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')}, a={1=1}
    --]]
]]*/
ora _find_object "&V1" 1
set feed off
VAR cur REFCURSOR
col act_bytes,est_bytes format kmg
DECLARE
    cur        SYS_REFCURSOR;
    v_xml      XMLTYPE;
    v_DDL      CLOB;
    hdl        INT;
    v_alloc    INT;
    v_used     INT;
    v_degree   INT;
    v_initrans INT;
    v_free     INT;
BEGIN
    IF :V1 IS NOT NULL THEN
        OPEN cur FOR
        WITH clu AS(
            SELECT /*+ordered use_nl(u o)*/ 0 lv,
                   MIN(o.obj#) obj#,
                   :object_subname||'%' subname
            FROM   sys.user$ u, sys.obj$ o
            WHERE  o.owner# = u.user#
            AND    o.type#!=10
            AND    u.name = :object_owner
            AND    o.name = :object_name
            GROUP BY o.owner#,o.name),
        tab  AS(SELECT * FROM clu UNION ALL SELECT /*+ordered use_nl(c t)*/lv+1, t.obj#, c.subname FROM clu c, sys.tab$ t WHERE  t.bobj# = c.obj#),
        ind  AS(SELECT * FROM tab UNION ALL SELECT /*+ordered use_nl(c t o)*/ lv+1, t.obj#, c.subname FROM tab c, sys.ind$ t WHERE t.bo# = c.obj#),
        lobs AS(SELECT * FROM ind UNION SELECT /*+ordered use_nl(c t o)*/lv+1, t.lobj#, c.subname FROM ind c, sys.lob$ t WHERE  t.obj# = c.obj#),
        rws  AS(SELECT /*+materialize no_expand*/ a.*,inserts-deletes rws from sys.dba_tab_modifications a where table_owner=:object_owner and table_name=:object_name and (:object_subname is null or :object_subname in(partition_name,subpartition_name)))
        SELECT  /*+ordered use_hash(a b) use_nl(o2)*/ a.*,
                CASE WHEN object_type LIKE 'TABLE%' THEN
                    nvl(coalesce((select rowcnt from sys.tab$ where obj#=o2.obj#),(select rowcnt from sys.tabpart$ where obj#=o2.obj#),(select rowcnt from sys.tabsubpart$ where obj#=o2.obj#)),0)+ nvl(b.rws,0)
                END num_rows
        FROM(
            SELECT /*+first_rows(1000) ordered use_nl(t o b o2) no_merge(t) no_merge*/
                u.user# user_id,u.name owner, o.name object_name,
                nvl(extractvalue(b.column_value, '/ROW/P'),rtrim(t.subname,'%')) PARTITION_NAME,
                extractvalue(b.column_value, '/ROW/T') object_type,
                extractvalue(b.column_value, '/ROW/C1') +0 bytes,
                row_number() over(order by extractvalue(b.column_value, '/ROW/C1')+0 desc) seq,
                extractvalue(b.column_value, '/ROW/C2') + 0 extents,
                extractvalue(b.column_value, '/ROW/C3') + 0 segments,
                round(extractvalue(b.column_value, '/ROW/C4') / 1024) init_kb,
                round(extractvalue(b.column_value, '/ROW/C5') / 1024) next_kb,
                extractvalue(b.column_value, '/ROW/C6') tablespace_name
            FROM lobs t,sys.obj$ o,sys.user$ u,
                TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(
                   q'[SELECT * FROM (
                        SELECT /*+opt_param('optimizer_index_cost_adj',1) ordered use_nl(a b) no_merge(b) push_pred(b)*/
                               decode('&OPT3','null',a.object_type,b.segment_type) T, &OPT3 P,
                               SUM(bytes) C1, SUM(EXTENTS) C2,
                               COUNT(1) C3, AVG(initial_extent) C4, AVG(nvl(next_extent, 0)) C5,
                               MAX(tablespace_name) KEEP(dense_rank LAST ORDER BY blocks) C6
                        FROM   dba_objects a, dba_segments b
                        WHERE  b.segment_type not in('ROLLBACK','TYPE2 UNDO','DEFERRED ROLLBACK','TEMPORARY','CACHE','SPACE HEADER','UNDEFINED')
                        AND    b.owner = ']' || u.name || '''
                        AND    b.segment_name = ''' || o.name || '''
                        AND    b.segment_type LIKE a.object_type || ''%''
                        AND    nvl(b.partition_name, '' '') LIKE ''' || t.subname || '''
                        AND    a.object_id = ' || t.obj# || '
                        AND    a.owner = ''' || u.name || '''
                        AND    a.object_name = ''' || o.name || '''
                        GROUP  BY a.object_type, &OPT3,b.segment_type
                        ORDER  BY C1 DESC)
                    WHERE  ROWNUM <= 1000'),'/ROWSET/ROW'))) B
            WHERE t.obj#=o.obj# AND o.owner#=u.user#
        ) a
        LEFT JOIN sys.obj$ o2 on(o2.owner#=a.user_id AND o2.name=a.object_name and nvl(o2.subname,' ')=nvl(a.partition_name,' ') and o2.namespace=1)
        LEFT JOIN rws b ON(a.owner=b.table_owner and a.object_name=b.table_name and 
                           (a.partition_name=b.subpartition_name or nvl(a.partition_name,' ') in nvl(b.partition_name,' ') and b.subpartition_name is null) and 
                           A.object_type like 'TABLE%')
        WHERE seq<=1000
        ORDER BY seq;

        $IF DBMS_DB_VERSION.VERSION>10 $THEN
            hdl   := dbms_xmlgen.newcontext(cur);
            v_xml := dbms_xmlgen.getxmltype(hdl);
            dbms_xmlgen.closecontext(hdl);
            hdl   := 0;
            FOR r IN (SELECT extractvalue(column_value,'//OWNER') owner,
                             extractvalue(column_value,'//OBJECT_NAME') object_name,
                             extractvalue(column_value,'//PARTITION_NAME') PARTITION_NAME,
                             extractvalue(column_value,'//OBJECT_TYPE') object_type,
                             extractvalue(column_value,'//TABLESPACE_NAME') TABLESPACE_NAME
                      FROM   table(xmlsequence(extract(v_xml,'/ROWSET/ROW')))) LOOP
                v_alloc := null;
                v_used  := null;
                hdl := hdl +1;
                IF r.object_type='INDEX' THEN
                    v_ddl := dbms_metadata.get_ddl(r.object_type,r.object_name,r.owner);
                    dbms_space.create_index_cost(v_ddl,v_alloc,v_used);
                    SELECT SUM(a.avg_col_len+1),max(c.pct_free),max(nvl(regexp_substr(c.degree,'\d+'),'1')+0),max(c.ini_trans)
                    INTO   v_used,v_free,v_degree,v_initrans
                    FROM   dba_tab_cols a,dba_ind_columns b,dba_indexes c
                    WHERE  b.index_owner=r.owner
                    AND    b.index_name =r.object_name
                    AND    c.owner=r.owner
                    AND    c.index_name =r.object_name
                    AND    c.owner=b.index_owner
                    AND    c.index_name =b.index_name
                    AND    b.table_owner=a.owner
                    AND    b.table_name=a.table_name
                    AND    b.column_name=a.column_name;
                ELSIF r.object_type LIKE 'TABLE%' THEN
                    for r1 in(
                            select tablespace_name,avg_row_len,num_rows,pct_free,nvl(regexp_substr(degree,'\d+'),'1')+0 degree,ini_trans from dba_tables where table_name=r.object_name and owner=r.owner and avg_row_len>0 and num_rows>0 and r.object_type='TABLE'
                            UNION  ALL
                            select tablespace_name,avg_row_len,num_rows,pct_free,null degree,ini_trans from dba_tab_partitions where table_name=r.object_name and table_owner=r.owner and partition_name=r.partition_name and avg_row_len>0 and num_rows>0 and r.object_type='TABLE PARTITION'
                            UNION  ALL
                            select tablespace_name,avg_row_len,num_rows,pct_free,null degree,ini_trans from dba_tab_subpartitions where table_name=r.object_name and table_owner=r.owner and subpartition_name=r.partition_name and avg_row_len>0 and num_rows>0 and r.object_type='TABLE SUBPARTITION') 
                    loop
                        dbms_space.create_table_cost(coalesce(r1.tablespace_name,r.tablespace_name,'SYSTEM'),r1.avg_row_len,r1.num_rows,r1.pct_free,v_alloc,v_used);
                        v_used     := r1.avg_row_len;
                        v_degree   := r1.degree;
                        v_initrans := r1.ini_trans;
                        v_free     := r1.pct_free; 
                    end loop;
                END IF;
                v_xml := v_xml.appendChildXML('/ROWSET/ROW['||hdl||']',xmltype('<ALLOC_BYTES>'||v_alloc||'</ALLOC_BYTES>'));
                v_xml := v_xml.appendChildXML('/ROWSET/ROW['||hdl||']',xmltype('<AVG_ROW_LEN>'||v_used||'</AVG_ROW_LEN>'));
                v_xml := v_xml.appendChildXML('/ROWSET/ROW['||hdl||']',xmltype('<PCT_FREE>'||v_free||'</PCT_FREE>'));
                v_xml := v_xml.appendChildXML('/ROWSET/ROW['||hdl||']',xmltype('<INI_TRANS>'||v_initrans||'</INI_TRANS>')); 
                v_xml := v_xml.appendChildXML('/ROWSET/ROW['||hdl||']',xmltype('<DEGREE>'||v_degree||'</DEGREE>')); 
            END LOOP;
            open cur for 
                SELECT  extractvalue(column_value,'//OWNER') owner,
                        extractvalue(column_value,'//OBJECT_NAME') object_name,
                        extractvalue(column_value,'//PARTITION_NAME') PARTITION_NAME,
                        extractvalue(column_value,'//OBJECT_TYPE') object_type,
                        extractvalue(column_value,'//ALLOC_BYTES')+0 EST_BYTES,
                        extractvalue(column_value,'//BYTES')+0 ACT_BYTES,
                        extractvalue(column_value,'//EXTENTS')+0 EXTENTS,
                        extractvalue(column_value,'//SEGMENTS')+0 SEGMENTS,
                        extractvalue(column_value,'//INIT_KB')+0 INIT_KB,
                        extractvalue(column_value,'//NEXT_KB')+0 NEXT_KB,
                        extractvalue(column_value,'//TABLESPACE_NAME') TABLESPACE_NAME,
                        extractvalue(column_value,'//NUM_ROWS')+0 num_rows,
                        extractvalue(column_value,'//AVG_ROW_LEN')+0 avg_row_len,
                        extractvalue(column_value,'//PCT_FREE')+0 pct_free,
                        extractvalue(column_value,'//INI_TRANS')+0 initrans,
                        extractvalue(column_value,'//DEGREE')+0 degree
                FROM   table(xmlsequence(extract(v_xml,'/ROWSET/ROW')));
        $END
        :CUR := cur;
    ELSE
        OPEN :CUR FOR
        SELECT rownum "#",a.*
        FROM   ( SELECT OWNER,
                        SEGMENT_NAME,&OPT2  decode('&OPT2','',regexp_substr(segment_type, '\S+'),segment_type) object_type,
                        round(SUM(bytes) / 1024 / 1024, 2) SIZE_MB,
                        round(SUM(bytes) / 1024 / 1024 /1024, 3) SIZE_GB,
                        SUM(EXTENTS) EXTENTS,
                        count(1) SEGMENTS,
                        ROUND(AVG(INITIAL_EXTENT)/1024) init_ext_kb,
                        ROUND(AVG(next_extent)/1024) next_ext_kb,
                    MAX(TABLESPACE_NAME) KEEP(DENSE_RANK LAST ORDER BY BYTES) TABLESPACE_NAME
            FROM   dba_segments s
            WHERE  &OPT4
            GROUP BY OWNER,SEGMENT_NAME,&OPT2  decode('&OPT2','',regexp_substr(segment_type, '\S+'),segment_type)
            ORDER BY SIZE_MB DESC) a
        WHERE  ROWNUM <= 100;
    END IF;
END;
/
