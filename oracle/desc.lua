local env=env
local db,cfg=env.getdb(),env.set
local desc={}

local desc_sql={
    PROCEDURE=[[
    DECLARE /*INTERNAL_DBCLI_CMD*/ 
        over    dbms_describe.number_table;
        posn    dbms_describe.number_table;
        levl    dbms_describe.number_table;
        arg     dbms_describe.varchar2_table;
        dtyp    dbms_describe.number_table;
        defv    dbms_describe.number_table;
        inout   dbms_describe.number_table;
        len     dbms_describe.number_table;
        prec    dbms_describe.number_table;
        scal    dbms_describe.number_table;
        n       dbms_describe.number_table;
        iodesc  VARCHAR2(6);
        v_xml   XMLTYPE := XMLTYPE('<ROWSET/>');
        v_stack VARCHAR2(3000);
        v_ov    PLS_INTEGER:=-1;
        v_seq   PLS_INTEGER:=-1;
        v_type  VARCHAR2(300);
        v_pos   VARCHAR2(30);
        v_target VARCHAR2(100):=:owner || NULLIF('.' || :object_name, '.') || NULLIF('.' || :object_subname, '.');
        type t_idx IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;
        v_idx    t_idx;
    BEGIN
        BEGIN 
            EXECUTE IMMEDIATE '
                SELECT /*+index(a) opt_param(''_optim_peek_user_binds'',''false'') no_expand*/ 
                       ARGUMENT,
                       OVERLOAD#,
                       POSITION# POSITION,
                       TYPE# TYPE,
                       NVL(DEFAULT#, 0) DEFAULT#,
                       NVL(IN_OUT, 0) IN_OUT,
                       NVL(LEVEL#, 0) LEVEL#,
                       NVL(LENGTH, 0) LENGTH,
                       NVL(PRECISION#, 0) PRECISION,
                       DECODE(TYPE#, 1, 0, 96, 0, NVL(SCALE, 0)) SCALE
                FROM   SYS.ARGUMENT$ A
                WHERE  OBJ# = 0+:id
                AND   (PROCEDURE$ IS NULL OR PROCEDURE$=:name)
                ORDER BY OVERLOAD#,SEQUENCE#'
            BULK COLLECT INTO arg,over,posn,dtyp,defv,inout,levl,len,prec,scal USING :object_id,nvl(:object_subname, :object_name);
        
        EXCEPTION WHEN OTHERS THEN
            v_target:='"'||replace(v_target,'.','"."')||'"';
            dbms_describe.describe_procedure(v_target, NULL, NULL, over, posn, levl,arg, dtyp, defv, inout, len, prec, scal, n, n,true);
        END;

        FOR i IN 1 .. over.COUNT LOOP
            IF over(i) != v_ov THEN
                v_ov := over(i);
                v_seq:= 1; 
                IF v_ov > 1 THEN
                    v_stack := '<ROW><OVERLOAD>' || v_ov || '</OVERLOAD><LEVEL>0</LEVEL><POSITION>-1</POSITION><ARGUMENT_NAME>---------------</ARGUMENT_NAME><DEFAULT/><SEQUENCE>0</SEQUENCE><DATA_TYPE>---------------</DATA_TYPE></ROW>';
                    v_xml   := v_xml.AppendChildXML('//ROWSET', XMLTYPE(v_stack));
                END IF;
            ELSE
                v_seq:=v_seq+1;
            END IF;

            v_idx(levl(i)) := posn(i);
            v_pos          := '';
            FOR j IN 0..levl(i)-1 LOOP
                v_pos := v_pos||v_idx(j)||'.';
            END LOOP;
            v_pos := v_pos||posn(i);

            SELECT decode(dtyp(i),  /* DATA_TYPE */
                0, null,
                1, 'VARCHAR2',
                2, decode(scal(i), -127, 'FLOAT', CASE WHEN prec(i)=38 AND nvl(scal(i),0)=0 THEN 'INTEGER' ELSE 'NUMBER' END),
                3, 'NATIVE INTEGER',
                8, 'LONG',
                9, 'VARCHAR',
                11, 'ROWID',
                12, 'DATE',
                23, 'RAW',
                24, 'LONG RAW',
                29, 'BINARY_INTEGER',
                69, 'ROWID',
                96, 'CHAR',
                100, 'BINARY_FLOAT',
                101, 'BINARY_DOUBLE',
                102, 'REF CURSOR',
                104, 'UROWID',
                105, 'MLSLABEL',
                106, 'MLSLABEL',
                110, 'REF',
                111, 'REF',
                112, 'CLOB',
                113, 'BLOB', 114, 'BFILE', 115, 'CFILE',
                121, 'OBJECT',
                122, 'TABLE',
                123, 'VARRAY',
                178, 'TIME',
                179, 'TIME WITH TIME ZONE',
                180, 'TIMESTAMP',
                181, 'TIMESTAMP WITH TIME ZONE',
                231, 'TIMESTAMP WITH LOCAL TIME ZONE',
                182, 'INTERVAL YEAR TO MONTH',
                183, 'INTERVAL DAY TO SECOND',
                250, 'PL/SQL RECORD',
                251, 'PL/SQL TABLE',
                252, 'PL/SQL BOOLEAN',
                'UNDEFINED') || 
                CASE 
                    WHEN dtyp(i) =2 AND prec(i)>0 AND nvl(nullif(scal(i),0),prec(i)) NOT IN(38,-127) THEN '('||prec(i)||NULLIF(','||scal(i),',')||')'
                    WHEN dtyp(i)!=2 AND len(i) >0 THEN '('||len(i)||')' 
                END
            INTO  v_type FROM dual;
            v_stack := '<ROW><OVERLOAD>' || over(i) || '</OVERLOAD><LEVEL>' || levl(i) || '</LEVEL><POSITION>' || v_pos || '</POSITION><ARGUMENT_NAME>' ||arg(i) || '</ARGUMENT_NAME><DEFAULT>' 
                || defv(i) || '</DEFAULT><SEQUENCE>' || v_seq || '</SEQUENCE><DATA_TYPE>' || v_type || '</DATA_TYPE><INOUT>' || inout(i) || '</INOUT></ROW>';
            v_xml   := v_xml.AppendChildXML('//ROWSET', XMLTYPE(v_stack));
        END LOOP;

        OPEN :v_cur FOR
            SELECT /*+no_merge(a) no_merge(b) use_nl(b a) push_pred(a) ordered*/
                     decode(b.pos,'-1','---',decode(b.overload,0,'', b.overload||'.') || b.pos) NO#,
                     lpad(' ',b.lv*2)||decode(0+regexp_substr(b.pos,'\d+$'), 0, '(RETURNS)', Nvl(b.argument_name, '<Collection>')) Argument,
                     nvl(CASE
                         WHEN a.pls_type IS NOT NULL AND a.pls_type!=a.data_type THEN
                              a.pls_type
                         WHEN a.type_subname IS NOT NULL THEN
                              a.type_name || '.' || a.type_subname || '(' || DATA_TYPE || ')'
                         WHEN a.type_name IS NOT NULL THEN
                              a.type_name || '(' || a.data_type || ')'
                         WHEN a.data_type='NUMBER' AND a.data_length=22 AND nvl(a.data_scale,0)=0 THEN 'INTEGER'      
                         WHEN a.data_type IN('FLOAT','INTEGER','INT','BINARY_FLOAT','BINARY_DOUBLE') THEN a.data_type
                         ELSE a.data_type || 
                            CASE WHEN DATA_PRECISION>0 THEN '('||DATA_PRECISION||NULLIF(','||DATA_SCALE,',')||')'
                                 WHEN DATA_LENGTH   >0 THEN '('||DECODE(CHAR_USED,'C',CHAR_LENGTH||' CHAR',DATA_LENGTH)||')'
                            END
                         END,b.dtype) DATA_TYPE,
                     decode(b.inout,0,'IN', 1, 'IN/OUT',2,'OUT','------') IN_OUT,
                     decode(b.default#, 1, 'Y', 0, 'N','--------') "Default?",
                     decode(b.pos,'-1','-------',a.character_set_name) charset
            FROM   (SELECT extractvalue(column_value, '/ROW/OVERLOAD') + 0 OVERLOAD,
                           extractvalue(column_value, '/ROW/LEVEL') + 0  lv,
                           extractvalue(column_value, '/ROW/POSITION')  pos,
                           extractvalue(column_value, '/ROW/SEQUENCE') + 0  seq,
                           extractvalue(column_value, '/ROW/ARGUMENT_NAME') ARGUMENT_NAME,
                           extractvalue(column_value, '/ROW/DATA_TYPE') DTYPE,
                           extractvalue(column_value, '/ROW/DEFAULT') + 0 DEFAULT#,
                           extractvalue(column_value, '/ROW/INOUT') + 0 INOUT
                    FROM   TABLE(XMLSEQUENCE(EXTRACT(v_xml, '/ROWSET/ROW')))) b,
                    all_arguments a
            WHERE  a.object_id(+) = :object_id
            AND    a.owner(+) = :owner
            AND    a.object_name(+) = nvl(:object_subname, :object_name)
            AND    nvl(a.overload(+), 0) = b.overload
            AND    a.position(+) = 0+regexp_substr(b.pos,'\d+$')
            AND    a.sequence(+)=b.seq
            AND    a.data_level(+) = b.lv
            ORDER  BY b.overload, b.seq ,b.pos;
    END;]],

    PACKAGE=[[
    SELECT NO#,ELEMENT,NVL2(RETURNS,'FUNCTION','PROCEDURE') Type,ARGUMENTS,RETURNS,
           AGGREGATE,PIPELINED,PARALLEL,INTERFACE,DETERMINISTIC,AUTHID
    FROM (
        SELECT /*INTERNAL_DBCLI_CMD*/ SUBPROGRAM_ID NO#,
               PROCEDURE_NAME||NVL2(OVERLOAD,' (#'||OVERLOAD||')','') ELEMENT,
               (SELECT (CASE
                           WHEN pls_type IS NOT NULL THEN
                            pls_type
                           WHEN type_subname IS NOT NULL THEN
                            type_name || '.' || type_subname
                           WHEN type_name IS NOT NULL THEN
                            type_name||'('||DATA_TYPE||')'
                           ELSE
                            data_type
                       END)
                FROM   all_Arguments b
                WHERE  a.SUBPROGRAM_ID = b.SUBPROGRAM_ID
                AND    NVL(a.OVERLOAD, -1) = NVL(b.OVERLOAD, -1)
                AND    position = 0
                AND    a.object_id = b.object_id) RETURNS,
               (SELECT COUNT(1)
                FROM   all_Arguments b
                WHERE  a.SUBPROGRAM_ID = b.SUBPROGRAM_ID
                AND    NVL(a.OVERLOAD, -1) = NVL(b.OVERLOAD, -1)
                AND    position > 0
                AND    a.object_id = b.object_id) ARGUMENTS,
               AGGREGATE,
               PIPELINED,
               PARALLEL,
               INTERFACE,
               DETERMINISTIC,
               AUTHID
        FROM   ALL_PROCEDURES a
        WHERE  owner=:owner and object_id =:object_id and object_name=:object_name
        AND    SUBPROGRAM_ID > 0
    ) ORDER  BY NO#]],

    INDEX={[[select /*INTERNAL_DBCLI_CMD*/ column_position NO#,column_name,column_length,char_length,descend from all_ind_columns
            WHERE  index_owner=:1 and index_name=:2
            ORDER BY NO#]],
            [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/* FROM ALL_INDEXES WHERE owner=:1 and index_name=:2]]},
    TYPE=[[
        SELECT /*INTERNAL_DBCLI_CMD*/
               attr_no NO#,
               attr_name,
               attr_type_owner||NVL2(attr_type_owner,'.','')||
               attr_TYPE_OWNER || NVL2(attr_TYPE_OWNER, '.', '') ||
               CASE WHEN attr_type_name IN('CHAR',
                                      'VARCHAR',
                                      'VARCHAR2',
                                      'NCHAR',
                                      'NVARCHAR',
                                      'NVARCHAR2',
                                      'RAW') --
               THEN attr_type_name||'(' || LENGTH || ')' --
               WHEN attr_type_name = 'NUMBER' --
               THEN (CASE WHEN nvl(scale, PRECISION) IS NULL THEN attr_type_name
                          WHEN scale > 0 THEN attr_type_name||'(' || NVL(''||PRECISION, '38') || ',' || SCALE || ')'
                          WHEN PRECISION IS NULL AND scale=0 THEN 'INTEGER'
                          ELSE attr_type_name||'(' || PRECISION  || ')' END) ELSE attr_type_name END
               data_type,
               attr_type_name || CASE
                   WHEN attr_type_name IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') --
                   THEN '(' || LENGTH || ')'
                   WHEN attr_type_name = 'NUMBER' THEN
                    (CASE
                        WHEN scale IS NULL AND PRECISION IS NULL THEN
                         ''
                        WHEN scale <> 0 THEN
                         '(' || NVL(PRECISION, 38) || ',' || SCALE || ')'
                        ELSE
                         '(' || NVL(PRECISION, 38) || ')'
                    END)
                   ELSE
                    ''
               END data_type,
               Inherited
        FROM   all_type_attrs
        WHERE  owner=:owner and type_name=:object_name
        ORDER BY NO#]],
    TABLE={[[
        SELECT /*INTERNAL_DBCLI_CMD*/ --+opt_param('_optim_peek_user_binds','false') no_merge(b) no_merge(a)
               INTERNAL_COLUMN_ID NO#,
               COLUMN_NAME NAME,
               DATA_TYPE_OWNER || NVL2(DATA_TYPE_OWNER, '.', '') ||
               CASE WHEN DATA_TYPE IN('CHAR',
                                      'VARCHAR',
                                      'VARCHAR2',
                                      'NCHAR',
                                      'NVARCHAR',
                                      'NVARCHAR2',
                                      'RAW') --
               THEN DATA_TYPE||'(' || DECODE(CHAR_USED, 'C', CHAR_LENGTH,DATA_LENGTH) || DECODE(CHAR_USED, 'C', ' CHAR') || ')' --
               WHEN DATA_TYPE = 'NUMBER' --
               THEN (CASE WHEN nvl(DATA_scale, DATA_PRECISION) IS NULL THEN DATA_TYPE
                          WHEN DATA_scale > 0 THEN DATA_TYPE||'(' || NVL(''||DATA_PRECISION, '38') || ',' || DATA_SCALE || ')'
                          WHEN DATA_PRECISION IS NULL AND DATA_scale=0 THEN 'INTEGER'
                          ELSE DATA_TYPE||'(' || DATA_PRECISION ||')' END) ELSE DATA_TYPE END
               data_type,
               DECODE(NULLABLE, 'N', 'NOT NULL', '') NULLABLE,
               (CASE
                   WHEN default_length > 0 THEN
                    DATA_DEFAULT
                   ELSE
                    NULL
               END) "Default",
               HIDDEN_COLUMN "Hidden?",
               AVG_COL_LEN AVG_LEN,
               num_distinct "NDV",
               CASE WHEN num_rows>=num_nulls THEN round(num_nulls*100/nullif(num_rows,0),2) END "Nulls(%)",
               CASE WHEN num_rows>=num_nulls THEN round((num_rows-num_nulls)/nullif(num_distinct,0),2) END CARDINALITY,
               nullif(HISTOGRAM,'NONE') HISTOGRAM,
               (select trim(comments) from all_col_comments where owner=a.owner and table_name=a.table_name and column_name=a.column_name) comments
               
               /*,decode(data_type
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(low_value))
                  ,'DATE',RTRIM(LTRIM(TO_CHAR(100 * (TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX') - 100) +
                                         (TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX') - 100),
                                         '0000')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX'), '00')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX'), '00')) || ' ' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX') - 1, '00')))
                  ,  low_value) low_v,
                decode(data_type
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(high_value))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(high_value))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(high_value))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(high_value))
                      ,'DATE', RTRIM(LTRIM(TO_CHAR(100 * (TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX') - 100) +
                                         (TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX') - 100),
                                         '0000')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX'), '00')) || '-' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX'), '00')) || ' ' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX') - 1, '00')) || ':' ||
                           LTRIM(TO_CHAR(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX') - 1, '00')))
                      ,  high_value) hi_v*/
        FROM   (select * from all_tab_cols a where a.owner=:owner and a.table_name=:object_name) a,
               (select * from all_tables a where a.owner=:owner and a.table_name=:object_name) b
        WHERE  a.table_name=b.table_name(+)
        AND    a.owner=b.owner(+)
        ORDER BY NO#]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ --+opt_param('_optim_peek_user_binds','false')
             DECODE(C.COLUMN_POSITION, 1, I.INDEX_NAME, '') INDEX_NAME,
             DECODE(C.COLUMN_POSITION, 1, I.INDEX_TYPE, '') INDEX_TYPE,
             DECODE(C.COLUMN_POSITION, 1, DECODE(I.UNIQUENESS,'UNIQUE','YES','NO'), '') "UNIQUE",
             DECODE(C.COLUMN_POSITION, 1, PARTITIONED, '') "PARTITIONED",
             DECODE(C.COLUMN_POSITION, 1, (select nvl(max(LOCALITY),'GLOBAL') from all_part_indexes l where l.owner=i.owner and l.index_name=i.index_name), '') "LOCALITY",
           --DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",
             DECODE(C.COLUMN_POSITION, 1, decode(I.STATUS,'N/A',(SELECT MIN(STATUS) FROM All_Ind_Partitions p WHERE p.INDEX_OWNER = I.OWNER AND p.INDEX_NAME = I.INDEX_NAME),I.STATUS), '') STATUS,
             DECODE(C.COLUMN_POSITION, 1, i.BLEVEL) BLEVEL,
             DECODE(C.COLUMN_POSITION, 1, i.LEAF_BLOCKS) LEAF_BLOCKS,
             DECODE(C.COLUMN_POSITION, 1, i.DISTINCT_KEYS) DISTINCT_KEYS,
             DECODE(C.COLUMN_POSITION, 1, i.LAST_ANALYZED) LAST_ANALYZED,
             C.COLUMN_POSITION NO#,
             C.COLUMN_NAME,
             C.DESCEND
        FROM   ALL_IND_COLUMNS C, ALL_INDEXES I
        WHERE  C.INDEX_OWNER = I.OWNER
        AND    C.INDEX_NAME = I.INDEX_NAME
        AND    I.TABLE_OWNER = :owner
        AND    I.TABLE_NAME = :object_name
        ORDER  BY C.INDEX_NAME, C.COLUMN_POSITION]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ --+opt_param('_optim_peek_user_binds','false')
               DECODE(R, 1, CONSTRAINT_NAME) CONSTRAINT_NAME,
               DECODE(R, 1, CONSTRAINT_TYPE) CTYPE,
               DECODE(R, 1, R_TABLE) R_TABLE,
               DECODE(R, 1, R_CONSTRAINT) R_CONSTRAINT,
               SEARCH_CONDITION C_CONDITION,
               DECODE(R, 1, status) status,
               --DECODE(R, 1, DEFERRABLE) DEFERRABLE,
               DECODE(R, 1, DEFERRED) DEFERRED,
               DECODE(R, 1, VALIDATED) VALIDATED,
               COLUMN_NAME
        FROM   (SELECT --+no_merge(a) ordered use_nl(a r c)
                       A.CONSTRAINT_NAME,
                       A.CONSTRAINT_TYPE,
                       R.TABLE_NAME R_TABLE,
                       A.R_CONSTRAINT_NAME R_CONSTRAINT,
                       a.status,
                       a.DEFERRABLE,
                       a.DEFERRED,
                       a.VALIDATED,
                       A.SEARCH_CONDITION,
                       c.COLUMN_NAME,
                       ROW_NUMBER() OVER(PARTITION BY A.CONSTRAINT_NAME ORDER BY C.COLUMN_NAME) R
                FROM   (select * from all_constraints where owner=:owner and table_name=:object_name) a,
                       all_constraints R, ALL_CONS_COLUMNS C
                WHERE  A.R_OWNER = R.OWNER(+)
                AND    A.R_CONSTRAINT_NAME = R.CONSTRAINT_NAME(+)
                AND    A.OWNER = C.OWNER(+)
                AND    A.CONSTRAINT_NAME = C.CONSTRAINT_NAME(+)
                AND    (A.constraint_type != 'C' OR A.constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'))
    ]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/*
        FROM   ALL_TABLES T
        WHERE  T.OWNER = :owner AND T.TABLE_NAME = :object_name]]},
    ['TABLE PARTITION']={[[
         SELECT /*INTERNAL_DBCLI_CMD*/ COLUMN_ID NO#,
                a.COLUMN_NAME NAME,
                DATA_TYPE_OWNER || NVL2(DATA_TYPE_OWNER, '.', '') ||
                CASE WHEN DATA_TYPE IN('CHAR',
                                       'VARCHAR',
                                       'VARCHAR2',
                                       'NCHAR',
                                       'NVARCHAR',
                                       'NVARCHAR2',
                                       'RAW') --
                THEN DATA_TYPE||'(' || DECODE(CHAR_USED, 'C', CHAR_LENGTH,DATA_LENGTH) || DECODE(CHAR_USED, 'C', ' CHAR') || ')' --
                WHEN DATA_TYPE = 'NUMBER' --
                THEN (CASE WHEN nvl(DATA_scale, DATA_PRECISION) IS NULL THEN DATA_TYPE
                           WHEN DATA_scale > 0 THEN DATA_TYPE||'(' || NVL(''||DATA_PRECISION, '38') || ',' || DATA_SCALE || ')'
                           WHEN DATA_PRECISION IS NULL AND DATA_scale=0 THEN 'INTEGER'
                           ELSE DATA_TYPE||'(' || DATA_PRECISION ||')' END) ELSE DATA_TYPE END
                data_type,
                DECODE(NULLABLE, 'N', 'NOT NULL', '') NULLABLE,
                (CASE
                    WHEN default_length > 0 THEN
                     DATA_DEFAULT
                    ELSE
                     NULL
                END) "Default",
                HIDDEN_COLUMN "Hidden?",
                a.AVG_COL_LEN AVG_LEN,
                a.num_distinct "NDV",
                CASE WHEN b.num_rows>=a.num_nulls THEN round(a.num_nulls*100/nullif(b.num_rows,0),2) END "Nulls(%)",
                CASE WHEN b.num_rows>=a.num_nulls THEN round((num_rows-a.num_nulls)/nullif(a.num_distinct,0),2) END CARDINALITY,
                nullif(a.HISTOGRAM,'NONE') HISTOGRAM
         FROM   all_tab_cols c,  all_Part_Col_Statistics a ,all_tab_partitions  b
         WHERE  a.owner=c.owner and a.table_name=c.table_name
         AND    a.column_name=c.column_name
         AND    a.owner=B.table_owner and a.table_name=B.table_name and a.partition_name=b.partition_name
         AND    upper(a.owner)=:owner and a.table_name=:object_name AND a.partition_name=:object_subname
         ORDER BY NO#]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/*
        FROM   all_tab_partitions T
        WHERE  T.TABLE_OWNER = :1 AND T.TABLE_NAME = :2 AND partition_name=:3]]}
}

desc_sql.VIEW=desc_sql.TABLE[1]
desc_sql['MATERIALIZED VIEW']=desc_sql.TABLE[1]
desc_sql['INDEX PARTITION']=desc_sql.INDEX
desc_sql.FUNCTION=desc_sql.PROCEDURE
desc_sql.TYPE={desc_sql.TYPE,desc_sql.PACKAGE}

function desc.desc(name,option)
    env.checkhelp(name)
    local rs,success,err
    local obj=db:check_obj(name)
    env.checkerr(obj,'Cannot find target object!')
    if obj.object_type=='SYNONYM' then
        local new_obj=db:dba_query(db.get_value,[[WITH r AS
         (SELECT /*+materialize cardinality(p 1)*/REFERENCED_OBJECT_ID OBJ, rownum lv
          FROM   PUBLIC_DEPENDENCY p
          START  WITH OBJECT_ID = :1
          CONNECT BY NOCYCLE PRIOR REFERENCED_OBJECT_ID = OBJECT_ID AND LEVEL<4)
        SELECT *
        FROM   (SELECT regexp_substr(obj,'[^/]+', 1, 1) + 0 object_id,
                       regexp_substr(obj,'[^/]+', 1, 2) owner,
                       regexp_substr(obj,'[^/]+', 1, 3) object_name,
                       regexp_substr(obj,'[^/]+', 1, 4) object_type
                 FROM   (SELECT (SELECT o.object_id || '/' || o.owner || '/' || o.object_name || '/' ||
                                           o.object_type
                                   FROM   ALL_OBJECTS o
                                   WHERE  OBJECT_ID = obj) OBJ, lv
                          FROM   r)
                 ORDER  BY lv)
        WHERE  object_type != 'SYNONYM'
        AND    object_type NOT LIKE '% BODY'
        AND    owner IS NOT NULL
        AND    rownum<2]],{obj.object_id})
        if type(new_obj)=="table" and new_obj[1] then
            obj.object_id,obj.owner,obj.object_name,obj.object_type=table.unpack(new_obj)
        end
    elseif obj.object_type=='PACKAGE' or obj.object_type=='PROCEDURE' or obj.object_type=='FUNCTION' then
        obj.object_id=db:dba_query(db.get_value,'select object_id from all_procedures where owner=:1 and object_name=:2 and rownum<2',{obj.owner,obj.object_name})
    end

    rs={obj.owner,obj.object_name,obj.object_subname or "",
       obj.object_subname and obj.object_subname~='' and (obj.object_type=="PACKAGE" or obj.object_type=="TYPE") and "PROCEDURE"
       or obj.object_type,2}

    local sqls=desc_sql[rs[4]]
    if not sqls then return print("Cannot describe "..rs[4]..'!') end
    if type(sqls)~="table" then sqls={sqls} end
    if (rs[4]=="PROCEDURE" or rs[4]=="FUNCTION") and rs[5]~=2 then
        rs[2],rs[3]=rs[3],rs[2]
    end

    for k,v in pairs{owner=rs[1],object_name=rs[2],object_subname=rs[3],object_type=rs[4],object_id=obj.object_id} do
        rs[k]=v
    end

    local dels=string.rep("=",100)
    local feed=cfg.get("feed")
    cfg.set("feed","off",true)
    print(("%s : %s%s%s\n"..dels):format(rs[4],rs[1],rs[2]=="" and "" or "."..rs[2],rs[3]=="" and "" or "."..rs[3]))
    for i,sql in ipairs(sqls) do
        if sql:find("/*PIVOT*/",1,true) then cfg.set("PIVOT",1) end
        local typ=db.get_command_type(sql)
        if typ=='DECLARE' or typ=='BEGIN' then
            rs['v_cur']='#CURSOR'
            db:dba_query(db.internal_call,sql,rs)

            db:print_result(rs.v_cur)
        else
            db:dba_query(db.query,sql,rs)
        end
        if i<#sqls then print(dels) end
    end

    if option and option:upper()=='ALL' then
        if rs[2]==""  then rs[2],rs[3]=rs[3],rs[2] end
        print(dels)
        cfg.set("PIVOT",1)
        db:query([[SELECT * FROM ALL_OBJECTS WHERE OWNER=:1 AND OBJECT_NAME=:2 AND nvl(SUBOBJECT_NAME,' ')=nvl(:3,' ')]],rs)
    end

    cfg.temp("feed",feed,true)
end

env.set_command(nil,{"describe","desc"},'Describe datbase object. Usage: @@NAME {[owner.]<object>[.partition] | [owner.]<pkg|typ>[.<function|procedure>]}',desc.desc,false,3)
return desc
