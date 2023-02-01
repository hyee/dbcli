local env=env
local db,cfg=env.getdb(),env.set
local desc={}

local ad=[[(SELECT  /*+no_merge opt_param('optimizer_dynamic_sampling' 5) opt_param('optimizer_adaptive_plans' 'false') opt_param('_optimizer_cartesian_enabled' 'false')*/
                     row_number() OVER(ORDER BY ba.seq, a.order_num) seq,
                     a.attribute_name,
                     ba.alt,
                     ba.role,
                     ba.level_name,
                     d.level_type,
                     ba.dtm_levels,
                     e.used_hiers,
                     nullif(b.owner || '.', ad.owner || '.') || b.table_name || '.' || column_name source_column,
                     decode(ba.role, 'KEY', regexp_substr(to_char(substr(d.member_name_expr,1,1000)),'[^'||chr(10)||']*')) member_expr,
                     d.skip_when_null skip_null,
                     aggs.level_order,
                     c.caption attr_caption,
                     c.descr attr_Desc,
                     decode(ba.role, 'KEY', regexp_substr(to_char(substr(d.member_caption_expr,1,1000)),'[^'||chr(10)||']*')) level_caption,
                     decode(ba.role, 'KEY', regexp_substr(to_char(substr(d.member_description_expr,1,1000)),'[^'||chr(10)||']*')) level_desc
              FROM   (SELECT *
                      FROM   all_attribute_dim_tables
                      WHERE  owner = ad.owner
                      AND    dimension_name = ad.dimension_name
                      AND    origin_con_id = ad.origin_con_id) b
              JOIN   (SELECT *
                     FROM   all_attribute_dim_attrs
                     WHERE  owner = ad.owner
                     AND    dimension_name = ad.dimension_name
                     AND    origin_con_id = ad.origin_con_id) a
              ON     (a.table_alias = b.table_alias)
              LEFT   JOIN (SELECT ROWNUM seq, a.*
                          FROM   (SELECT attribute_name,
                                         MAX(is_minimal_dtm) is_minimal_dtm,
                                         MIN(ROLE) ROLE,
                                         MAX(DECODE(ROLE, 'KEY', level_name)) level_name,
                                         MAX(DECODE(ROLE, 'KEY', is_alternate)) alt,
                                         MAX(DECODE(ROLE, 'KEY', GREATEST(attr_order_num,key_order_num))) key_ord,
                                         listagg(DECODE(role, 'PROP', level_name), '/') WITHIN GROUP(ORDER BY order_num DESC) dtm_levels,
                                         COUNT(DECODE(role, 'PROP', 1)) dtms,
                                         SUM(DECODE(role, 'KEY', 0, 255) + order_num) ords
                                  FROM   all_attribute_dim_level_attrs attr
                                  LEFT   JOIN all_attribute_dim_keys
                                  USING (owner,dimension_name,attribute_name,level_name)
                                  WHERE  owner = ad.owner
                                  AND    dimension_name = ad.dimension_name
                                  AND    nvl(attr.origin_con_id, ad.origin_con_id) = ad.origin_con_id
                                  GROUP  BY attribute_name
                                  ORDER  BY is_minimal_dtm,dtms,ords,key_ord) a) ba
              ON     (a.attribute_name = ba.attribute_name)
              LEFT   JOIN (SELECT level_name,
                                 listagg(agg_func || ' ' || attribute_name || NULLIF(' ' || criteria, ' ASC') || NULLIF(' NULLS ' || nulls_position, ' NULLS ' || DECODE(criteria, 'ASC', 'LAST', 'FIRST')),
                                         ',') WITHIN GROUP(ORDER BY order_num) level_order
                          FROM   all_attribute_dim_order_attrs
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = ad.origin_con_id
                          GROUP  BY level_name) aggs
              ON     (ba.level_name = aggs.level_name)
              LEFT   JOIN (SELECT attribute_name,
                                 MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) caption,
                                 MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST) descr
                          FROM   all_attribute_dim_attr_class j
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = ad.origin_con_id
                          GROUP  BY attribute_name) c
              ON     (a.attribute_name = c.attribute_name)
              LEFT   JOIN (SELECT *
                          FROM   all_attribute_dim_levels
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = ad.origin_con_id) d
              ON     (ba.level_name = d.level_name)
              LEFT   JOIN (SELECT level_name, listagg(hier_name, ',') WITHIN GROUP(ORDER BY hier_name) used_hiers
                          FROM   all_hierarchies
                          JOIN   all_hier_levels
                          USING  (owner, hier_name, origin_con_id)
                          WHERE  owner = ad.owner
                          AND    dimension_name = ad.dimension_name
                          AND    origin_con_id = ad.origin_con_id
                          GROUP  BY level_name, dimension_owner, dimension_name) e
              ON     (ba.level_name = e.level_name)
              ORDER  BY 1)]]
local ah=([[ (SELECT /*+no_merge opt_param('optimizer_dynamic_sampling' 5) */ 
                     row_number() OVER(ORDER BY adk.hier_seq DESC NULLS LAST, adt.seq, ahc.order_num) seq,
                     NVL(adk.hier_level, adt.level_name) hier_level,
                     adt.level_type,
                     NVL(adt.attribute_name, ahc.column_name) column_name,
                     adt.alt,
                     adt.dtm_levels,
                     CASE
                         WHEN ahc.data_type IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                          ahc.data_type || '(' || ahc.data_length || decode(ahc.char_used, 'C', ' CHAR') || ')' --
                         WHEN ahc.data_type = 'NUMBER' THEN
                          CASE
                              WHEN nvl(ahc.data_scale, ahc.data_precision) IS NULL THEN
                               ahc.data_type
                              WHEN data_scale > 0 THEN
                               ahc.data_type || '(' || nvl('' || ahc.data_precision, '38') || ',' || ahc.data_scale || ')'
                              WHEN ahc.data_precision IS NULL AND ahc.data_scale = 0 THEN
                               'INTEGER'
                              ELSE
                               ahc.data_type || '(' || ahc.data_precision || ')'
                          END
                         ELSE
                          ahc.data_type
                     END data_type,
                     ahc.nullable,
                     ahc.role,
                     coalesce(adt.source_column,regexp_substr(to_char(substr(ahd.expression,1,1000)),'[^'||chr(10)||']*')) source_column,
                     adt.member_expr,
                     adt.skip_null,
                     adt.level_order,
                     NVL(ahd.caption, adt.attr_caption) caption,
                     NVL(ahd.descr, adt.attr_desc) description
              FROM   all_attribute_dimensions ad
              JOIN   all_hier_columns ahc
              ON     (ah.owner = ahc.owner AND ah.hier_name = ahc.hier_name AND ah.origin_con_id = ahc.origin_con_id)
              OUTER  APPLY(SELECT *
                           FROM   (SELECT level_name,
                                          attribute_name,
                                          lpad(' ', 2 * (MAX(lv.order_num) OVER() - lv.order_num)) || level_name || '(*)' hier_level,
                                          lv.order_num hier_seq
                                   FROM   all_hier_levels lv
                                   JOIN   all_hier_level_id_attrs attr
                                   USING  (owner, hier_name, origin_con_id, level_name)
                                   WHERE  owner = ah.owner
                                   AND    hier_name = ah.hier_name
                                   AND    origin_con_id = ah.origin_con_id)
                           WHERE  attribute_name = ahc.column_name) adk
              OUTER  APPLY(SELECT /*+no_merge(i) NO_GBY_PUSHDOWN(i)*/
                                   g.*, i.caption, i.descr
                           FROM   all_hier_hier_attributes g,
                                  (SELECT hier_attr_name,
                                          MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                                          MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  descr
                                   FROM   all_hier_hier_attr_class
                                   WHERE  owner = ah.owner
                                   AND    hier_name = ah.hier_name
                                   AND    origin_con_id = ah.origin_con_id
                                   GROUP  BY hier_attr_name) i
                           WHERE  g.hier_attr_name = i.hier_attr_name(+)
                           AND    ahc.column_name = g.hier_attr_name
                           AND    ah.hier_name = g.hier_name
                           AND    ah.owner = g.owner
                           AND    ah.origin_con_id = g.origin_con_id) ahd
              OUTER  APPLY(SELECT *
                           FROM   @ad@ adt
                           WHERE  TRIM(adt.attribute_name) = ahc.column_name) adt
              WHERE  ah.dimension_owner = ad.owner
              AND    ah.dimension_name = ad.dimension_name
              AND    ah.origin_con_id = ad.origin_con_id)]]):gsub('@ad@',ad)
local desc_sql={
    PROCEDURE=[[
    DECLARE /*INTERNAL_DBCLI_CMD*/
        cur     SYS_REFCURSOR;
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
        oname   VARCHAR2(128):= nvl(:object_subname, :object_name);
        own     VARCHAR2(128):= :owner;
        oid     INT          := :object_id;
        v_target VARCHAR2(100):=:owner || NULLIF('.' || :object_name, '.') || NULLIF('.' || :object_subname, '.');
        type t_idx IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;
        v_idx    t_idx;
    BEGIN
        select nvl(max(object_id),oid) into oid 
        from   all_procedures where owner=own 
        and    object_name=:object_name and rownum<2;

        $IF DBMS_DB_VERSION.VERSION > 10 $THEN
        OPEN cur for
            SELECT decode(p,'-','-',TRIM('.' FROM o || replace(p,' '))) no#, 
                   '|' "|",
                   Argument, 
                   data_type, 
                   IN_OUT, 
                   defaulted "Default?",
                   CHARSET
            FROM   (SELECT /*+opt_param('optimizer_dynamic_sampling' 5) */ 
                           overload,
                           SEQUENCE s,
                           DATA_LEVEL l,
                           POSITION p,
                           lpad(' ', DATA_LEVEL * 2) || decode(0 + POSITION, 0, '(RETURNS)', Nvl(argument_name, '<Collection>')) Argument,
                           CASE
                               WHEN pls_type != data_type THEN
                                pls_type
                               WHEN type_subname IS NOT NULL THEN
                                type_name || '.' || type_subname || '(' || DATA_TYPE || ')'
                               WHEN type_name IS NOT NULL THEN
                                type_name || '(' || data_type || ')'
                               WHEN data_type = 'NUMBER' AND NVL(t.data_precision, -1) >0 AND nvl(data_scale, 0) = 0 THEN
                                'INTEGER'
                               WHEN data_type IN ('FLOAT',
                                                  'INTEGER',
                                                  'INT',
                                                  'BINARY_INTEGER',
                                                  'BINARY_FLOAT',
                                                  'BINARY_DOUBLE',
                                                  'PL/SQL BOOLEAN',
                                                  'PL/SQL RECORD') THEN
                                data_type
                               WHEN (t.data_type LIKE 'TIMESTAMP%' OR t.data_type LIKE 'INTERVAL DAY%' OR
                                    t.data_type LIKE 'INTERVAL YEAR%' OR t.data_type = 'DATE' OR
                                    (t.data_type = 'NUMBER' AND ((t.data_precision = 0) OR NVL(t.data_precision, -1) = -1) AND
                                    nvl(t.data_scale, -1) = -1)) THEN
                                data_type
                               ELSE
                                data_type || --
                                NULLIF('(' || TRIM(CASE
                                                       WHEN t.data_type IN ('VARCHAR', 'VARCHAR2', 'RAW', 'CHAR') THEN
                                                        DECODE((SELECT VALUE FROM nls_session_parameters WHERE PARAMETER = 'NLS_LENGTH_SEMANTICS'),
                                                               'BYTE',
                                                               DECODE(char_used, 'B', t.data_length || '', t.char_length || ' CHAR'),
                                                               DECODE(char_used, 'B', t.data_length || ' BYTE', t.char_length || ' CHAR'))
                                                       WHEN t.data_type IN ('NVARCHAR2', 'NCHAR') AND nvl(t.data_length, -1) != -1 THEN
                                                        t.data_length / 2 || ''
                                                       WHEN ((t.data_type = 'NUMBER' AND NVL(t.data_precision, -1) = -1) AND (nvl(t.data_scale, -1) != -1)) THEN
                                                        '38,' || t.data_scale
                                                       WHEN (t.data_scale = 0 OR nvl(t.data_scale, -1) = -1) THEN
                                                        t.data_precision || ''
                                                       WHEN (t.data_precision != 0 AND t.data_scale != 0) THEN
                                                        t.data_precision || ',' || t.data_scale
                                                   END) || ')',
                                       '()')
                           END data_type,
                           IN_OUT,
                           decode(t.defaulted, 'Y', 'Yes', 'No') defaulted,
                           CHARACTER_SET_NAME charset
                    FROM   all_arguments t
                    WHERE  owner = own
                    AND    object_id = oid
                    AND    object_name = oname) 
            MODEL PARTITION BY(0+overload o) DIMENSION BY(s, l) 
            MEASURES(CAST(p AS VARCHAR2(30)) p, Argument, data_type, IN_OUT, defaulted, CHARSET) 
            RULES SEQUENTIAL ORDER(
                p [ANY,ANY] ORDER BY s = max(p) [ s < cv(s), CV(l) - 1 ] || '.' || lpad(p [ CV(), CV() ],4),
                p [9999,0]='-'
            )
            ORDER  BY o, s;
        $ELSE

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
            BULK COLLECT INTO arg,over,posn,dtyp,defv,inout,levl,len,prec,scal USING oid,oname;
        
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

        OPEN cur FOR
            SELECT /*+no_merge(a) no_merge(b) use_nl(b a) push_pred(a) ordered opt_param('optimizer_dynamic_sampling' 5) */ 
                     decode(b.pos,'-1','---',decode(b.overload,0,'', b.overload||'.') || b.pos) NO#,
                     lpad(' ',b.lv*2)||decode(0+regexp_substr(b.pos,'\d+$'), 0, '(RETURNS)', Nvl(b.argument_name, '<Collection>')) Argument,
                     nvl(CASE
                         WHEN a.pls_type!=a.data_type THEN
                              a.pls_type
                         WHEN a.type_subname IS NOT NULL THEN
                              a.type_name || '.' || a.type_subname || '(' || DATA_TYPE || ')'
                         WHEN a.type_name IS NOT NULL THEN
                              a.type_name || '(' || a.data_type || ')'
                         WHEN a.data_type='NUMBER' AND a.data_length=22 AND a.data_precision>0 AND nvl(a.data_scale,0)=0 THEN 'INTEGER'      
                         WHEN a.data_type IN('FLOAT','INTEGER','INT','BINARY_FLOAT','BINARY_DOUBLE') THEN a.data_type
                         ELSE a.data_type || 
                            CASE WHEN DATA_PRECISION>0 THEN '('||DATA_PRECISION||NULLIF(','||DATA_SCALE,',')||')'
                                 WHEN DATA_LENGTH   >0 THEN '('||DECODE(CHAR_USED,'C',CHAR_LENGTH||' CHAR',DATA_LENGTH)||')'
                            END
                         END,b.dtype) DATA_TYPE,
                     decode(b.inout,0,'IN', 1, 'IN/OUT',2,'OUT','------') IN_OUT,
                     decode(b.default#, 1, 'Y', 0, 'N','--------') "Default?",
                     decode(b.pos,'-1','-------',a.character_set_name) charset
            FROM   (SELECT /*+cardinality(1)*/
                           extractvalue(column_value, '/ROW/OVERLOAD') + 0 OVERLOAD,
                           extractvalue(column_value, '/ROW/LEVEL') + 0  lv,
                           extractvalue(column_value, '/ROW/POSITION')  pos,
                           extractvalue(column_value, '/ROW/SEQUENCE') + 0  seq,
                           extractvalue(column_value, '/ROW/ARGUMENT_NAME') ARGUMENT_NAME,
                           extractvalue(column_value, '/ROW/DATA_TYPE') DTYPE,
                           extractvalue(column_value, '/ROW/DEFAULT') + 0 DEFAULT#,
                           extractvalue(column_value, '/ROW/INOUT') + 0 INOUT
                    FROM   TABLE(XMLSEQUENCE(EXTRACT(v_xml, '/ROWSET/ROW')))) b,
                    all_arguments a
            WHERE  a.owner(+) = own
            AND    a.object_id(+) = oid
            AND    a.object_name(+) = oname
            AND    nvl(a.overload(+), -1) = nvl(b.overload,-1)
            AND    a.position(+) = 0+regexp_substr(b.pos,'\d+$')
            AND    a.sequence(+)=b.seq
            AND    a.data_level(+) = b.lv
            ORDER  BY b.overload, b.seq ,b.pos;
        $END
        :v_cur := cur;
    END;]],

    PACKAGE=[[
    SELECT NO#,ELEMENT,NVL2(RETURNS,'FUNCTION','PROCEDURE') Type,ARGUMENTS,RETURNS,
           AGGREGATE,PIPELINED,PARALLEL,INTERFACE,DETERMINISTIC,AUTHID
    FROM (
        SELECT /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) use_hash(a b)*/ 
               A.SUBPROGRAM_ID NO#,
               PROCEDURE_NAME||NVL2(OVERLOAD,' (#'||OVERLOAD||')','') ELEMENT,
               b.RETURNS,
               b.ARGUMENTS,
               AGGREGATE,
               PIPELINED,
               PARALLEL,
               INTERFACE,
               DETERMINISTIC,
               AUTHID
        FROM   ALL_PROCEDURES a,
               (SELECT SUBPROGRAM_ID,
                       MAX(decode(position,1,CASE
                           WHEN pls_type IS NOT NULL THEN
                            pls_type
                           WHEN type_subname IS NOT NULL THEN
                            type_name || '.' || type_subname
                           WHEN type_name IS NOT NULL THEN
                            type_name||'('||DATA_TYPE||')'
                           ELSE
                            data_type
                       END)) returns,
                       COUNT(CASE WHEN position>0 THEN 1 END) ARGUMENTS
                FROM   all_Arguments b
                WHERE  owner='&owner'
                AND    package_name='&object_name'
                GROUP  BY SUBPROGRAM_ID) b
        WHERE  a.owner='&owner'
        AND    a.object_name='&object_name'
        AND    a.SUBPROGRAM_ID=b.SUBPROGRAM_ID(+)
        AND    a.SUBPROGRAM_ID > 0
    ) ORDER  BY NO#]],

    INDEX={[[select /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) */ 
                   table_owner||'.'||table_name table_name,column_position NO#,column_name,column_expression column_expr,column_length,char_length,descend
            from   all_ind_columns left join all_ind_expressions using(index_owner,index_name,column_position,table_owner,table_name)
            WHERE  index_owner=:1 and index_name=:2
            ORDER BY NO#]],
            [[WITH r1 AS (SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode')*/* FROM all_part_key_columns WHERE owner=:owner and NAME = :object_name),
                    r2 AS (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=:owner and NAME = :object_name)
             SELECT LOCALITY,
                    PARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                          FROM   r1
                                          START  WITH column_position = 1
                                          CONNECT BY PRIOR column_position = column_position - 1) PARTITIONED_BY,
                    PARTITION_COUNT PARTS,
                    SUBPARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                             FROM   R2
                                             START  WITH column_position = 1
                                             CONNECT BY PRIOR column_position = column_position - 1) SUBPART_BY,
                    def_subpartition_count subs,
                    DEF_TABLESPACE_NAME,
                    DEF_PCT_FREE,
                    DEF_INI_TRANS,
                    DEF_LOGGING
                FROM   all_part_indexes
                WHERE  index_name = :object_name
                AND    owner = :owner]],
            [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/* FROM ALL_INDEXES WHERE owner=:1 and index_name=:2]]},
    TYPE=[[
        SELECT /*INTERNAL_DBCLI_CMD*//*+opt_param('optimizer_dynamic_sampling' 5) */ 
               attr_no NO#,
               decode(c, 1,
                      CASE
                          WHEN attr_no = 1 THEN
                           (SELECT a.type_name||'['||DECODE(COLL_TYPE, 'TABLE', 'TABLE', 'VARRAY(' || UPPER_BOUND || ')') ||']'||CHR(10) || '  '
                            FROM   ALL_COLL_TYPES
                            WHERE  owner = :owner
                            AND    type_name = :object_name)
                          ELSE
                           '  '
                      END) || attr_name attr_name,
               decode(attr_no*c, 1, chr(10)) || nullif(attr_type_owner||'.', '.') || --
               CASE
                   WHEN attr_type_name IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                    attr_type_name || '(' || LENGTH || ')' --
                   WHEN attr_type_name = 'NUMBER' THEN
                    (CASE
                        WHEN nvl(scale, PRECISION) IS NULL THEN
                         attr_type_name
                        WHEN scale > 0 THEN
                         attr_type_name || '(' || NVL('' || PRECISION, '38') || ',' || SCALE || ')'
                        WHEN PRECISION IS NULL AND scale = 0 THEN
                         'INTEGER'
                        ELSE
                         attr_type_name || '(' || PRECISION || ')'
                    END)
                   ELSE
                    attr_type_name
               END data_type, 
               decode(attr_no*c, 1, chr(10)) || ATTR_TYPE_MOD ATTR_MOD, 
               decode(attr_no*c, 1, chr(10)) || Inherited inherit, 
               decode(attr_no*c, 1, chr(10)) || CHARACTER_SET_NAME "CHARSET"
        FROM   (SELECT A.*, decode(type_name, :object_name, 0, 1) c
                FROM   all_type_attrs a
                WHERE  (owner = :owner AND type_name = :object_name)) a
        ORDER  BY NO#]],
    TABLE={[[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5) */ 
               --+no_parallel opt_param('_optim_peek_user_binds','false') use_hash(a b c) swap_join_inputs(c)
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
               round(decode(histogram,'HYBRID',NULL,greatest(0,num_rows-num_nulls)/nullif(num_distinct,0)),2) CARDINALITY,
               nullif(HISTOGRAM,'NONE') HISTOGRAM,
               NUM_BUCKETS buckets,
               c.comments,
               case when low_value is not null then 
               substrb(decode(dtype
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(low_value))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(low_value))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(low_value))
                  ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(low_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(low_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(low_value, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(low_value, 25, 2), 'XX')-60,0)
                  ,'DATE',lpad(TO_NUMBER(SUBSTR(low_value, 1, 2), 'XX')-100,2,0)||
                          lpad(TO_NUMBER(SUBSTR(low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(low_value, 13, 2), 'XX')-1,2,0)
                  ,  low_value),1,32) end low_value,
                case when high_value is not null then 
                substrb(decode(dtype
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(high_value))
                      ,'FLOAT'        ,to_char(utl_raw.cast_to_number(high_value))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(high_value))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                      ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(high_value))
                      ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(high_value))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(high_value))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(high_value))
                      ,'TIMESTAMP'   , lpad(TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(high_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                        ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(high_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(high_value, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(high_value, 25, 2), 'XX')-60,0)
                        ,'DATE',lpad(TO_NUMBER(SUBSTR(high_value, 1, 2), 'XX')-100,2,0)||
                                lpad(TO_NUMBER(SUBSTR(high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(high_value, 13, 2), 'XX')-1,2,0)
                        ,  high_value),1,32) end high_value
        FROM   (select /*+no_merge*/ a.*,regexp_replace(data_type,'\(.+\)') dtype from all_tab_cols a where a.owner=:owner and a.table_name=:object_name) a,
               (select /*+no_merge*/ * from all_tables a where a.owner=:owner and a.table_name=:object_name) b,
               (select /*+no_merge*/ column_name cname,substr(trim(comments),1,256) comments from all_col_comments where owner=:owner and table_name=:object_name) c
        WHERE  a.table_name=b.table_name(+)
        AND    a.owner=b.owner(+)
        AND    a.column_name=c.cname(+)
        ORDER BY NO#]],
    [[
        WITH I AS (SELECT /*+cardinality(1) no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('optimizer_dynamic_sampling' 5) */ 
                           I.*,nvl(c.LOCALITY,'GLOBAL') LOCALITY,
                           PARTITIONING_TYPE||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+no_merge*/* FROM all_part_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') PARTITIONED_BY,
                           nullif(SUBPARTITIONING_TYPE,'NONE')||EXTRACTVALUE(dbms_xmlgen.getxmltype(q'[
                                    SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')') V
                                    FROM   (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=']'||i.owner|| ''' and NAME = '''||i.index_name||q'[')
                                    START  WITH column_position = 1
                                    CONNECT BY PRIOR column_position = column_position - 1]'),'//V') SUBPART_BY
                    FROM   ALL_INDEXES I,ALL_PART_INDEXES C
                    WHERE  C.OWNER(+) = I.OWNER
                    AND    C.INDEX_NAME(+) = I.INDEX_NAME
                    AND    I.TABLE_OWNER = :owner
                    AND    I.TABLE_NAME = :table_name)
        SELECT /*+no_parallel leading(i c e) opt_param('_optim_peek_user_binds','false') opt_param('_sort_elimination_cost_ratio',5)*/
                DECODE(C.COLUMN_POSITION, 1, I.OWNER, '') OWNER,
                DECODE(C.COLUMN_POSITION, 1, I.INDEX_NAME, '') INDEX_NAME,
                DECODE(C.COLUMN_POSITION, 1, I.INDEX_TYPE, '') INDEX_TYPE,
                DECODE(C.COLUMN_POSITION, 1, DECODE(I.UNIQUENESS,'UNIQUE','YES','NO'), '') "UNIQUE",
                DECODE(C.COLUMN_POSITION, 1, NVL(PARTITIONED_BY||NULLIF(','||SUBPART_BY,','),'NO'), '') "PARTITIONED",
                DECODE(C.COLUMN_POSITION, 1, LOCALITY, '') "LOCALITY",
                --DECODE(C.COLUMN_POSITION, 1, (SELECT NVL(MAX('YES'),'NO') FROM ALL_Constraints AC WHERE AC.INDEX_OWNER = I.OWNER AND AC.INDEX_NAME = I.INDEX_NAME), '') "IS_PK",
                DECODE(C.COLUMN_POSITION, 1, decode(I.STATUS,'N/A',(SELECT MIN(STATUS) FROM All_Ind_Partitions p WHERE p.INDEX_OWNER = I.OWNER AND p.INDEX_NAME = I.INDEX_NAME),I.STATUS), '') STATUS,
                DECODE(C.COLUMN_POSITION, 1, i.BLEVEL) BLEVEL,
                DECODE(C.COLUMN_POSITION, 1, round(100*i.CLUSTERING_FACTOR/greatest(i.num_rows,1),2)) "CF(%)/Rows",
                DECODE(C.COLUMN_POSITION, 1, i.DISTINCT_KEYS) DISTINCTS,
                DECODE(C.COLUMN_POSITION, 1, i.LEAF_BLOCKS) LEAF_BLOCKS,
                DECODE(C.COLUMN_POSITION, 1, AVG_LEAF_BLOCKS_PER_KEY) "LB/KEY",
                DECODE(C.COLUMN_POSITION, 1, AVG_DATA_BLOCKS_PER_KEY) "DB/KEY",
                DECODE(C.COLUMN_POSITION, 1, ceil(i.num_rows/greatest(i.DISTINCT_KEYS,1))) CARD,
                DECODE(C.COLUMN_POSITION, 1, i.LAST_ANALYZED) LAST_ANALYZED,
                C.COLUMN_POSITION NO#,
                C.COLUMN_NAME,
                E.COLUMN_EXPRESSION COLUMN_EXPR,
                C.DESCEND
        FROM   I,  ALL_IND_COLUMNS C,  all_ind_expressions e
        WHERE  C.INDEX_OWNER = I.OWNER
        AND    C.INDEX_NAME = I.INDEX_NAME
        AND    C.INDEX_NAME = e.INDEX_NAME(+)
        AND    C.INDEX_OWNER = e.INDEX_OWNER(+)
        AND    C.column_position = e.column_position(+)
        AND    :owner = c.table_owner
        AND    :table_name =c.table_name
        AND    :owner = E.table_owner(+)
        AND    :table_name =e.table_name(+)
        ORDER  BY C.INDEX_NAME, C.COLUMN_POSITION]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ --+no_parallel opt_param('_optim_peek_user_binds','false') opt_param('optimizer_dynamic_sampling' 5)
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
        FROM   (SELECT --+no_merge(a) leading(a r c) use_nl(a r c) cardinality(a 1)
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
                AND    :owner = c.owner(+)
                AND    :object_name =c.table_name(+)
                AND    (A.constraint_type != 'C' OR A.constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'))
    ]],
    [[/*grid={topic='ALL_TABLES', pivot=1}*/ 
    WITH r1 AS (SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode') opt_param('optimizer_dynamic_sampling' 5)*/ * 
                FROM all_part_key_columns WHERE owner=:owner and NAME = :object_name),
           r2 AS (SELECT /*+no_merge*/* FROM all_subpart_key_columns WHERE owner=:owner and NAME = :object_name)
    SELECT PARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                 FROM   r1
                                 START  WITH column_position = 1
                                 CONNECT BY PRIOR column_position = column_position - 1)
                              PARTITIONED_BY,
            PARTITION_COUNT PARTS,
            SUBPARTITIONING_TYPE || (SELECT MAX('(' || TRIM(',' FROM sys_connect_by_path(column_name, ',')) || ')')
                                     FROM   R2
                                     START  WITH column_position = 1
                                     CONNECT BY PRIOR column_position = column_position - 1) SUBPART_BY,
            def_subpartition_count subs,
            DEF_TABLESPACE_NAME,
            DEF_PCT_FREE,
            DEF_INI_TRANS,
            DEF_LOGGING,
            DEF_COMPRESSION
    FROM   all_part_tables
    WHERE  table_name = :object_name
    AND    owner = :owner]],
    [[SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*+opt_param('optimizer_dynamic_sampling' 5)*/ *
      FROM   ALL_TABLES T
      WHERE  T.OWNER = :owner AND T.TABLE_NAME = :object_name]]},
      
    ['TABLE PARTITION']={[[
         SELECT /*INTERNAL_DBCLI_CMD*/ /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                COLUMN_ID NO#,
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
                round(decode(a.histogram,'HYBRID',NULL,greatest(0,num_rows-a.num_nulls)/nullif(a.num_distinct,0)),2) CARDINALITY,
                nullif(a.HISTOGRAM,'NONE') HISTOGRAM，
                a.NUM_BUCKETS buckets,
                case when a.low_value is not null then 
                substrb(decode(dtype
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(a.low_value))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(a.low_value))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(a.low_value))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(a.low_value))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(a.low_value))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(a.low_value))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(a.low_value))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(a.low_value))
                  ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(a.low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(a.low_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.low_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(a.low_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(a.low_value, 23,2),'XX')-20,0)||':'||nvl(TO_NUMBER(SUBSTR(a.low_value, 25, 2), 'XX')-60,0)
                  ,'DATE',lpad(TO_NUMBER(SUBSTR(a.low_value, 1, 2), 'XX')-100,2,0)||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 5, 2), 'XX') ,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(a.low_value, 13, 2), 'XX')-1,2,0)
                  ,  a.low_value),1,32) end low_value,
                case when a.high_value is not null then 
                substrb(decode(dtype
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(a.high_value))
                      ,'FLOAT'        ,to_char(utl_raw.cast_to_number(a.high_value))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(a.high_value))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(a.high_value))
                      ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(a.high_value))
                      ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(a.high_value))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(a.high_value))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(a.high_value))
                      ,'TIMESTAMP'    ,lpad(TO_NUMBER(SUBSTR(a.high_value, 1, 2), 'XX')-100,2,0)||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                       lpad(TO_NUMBER(SUBSTR(a.high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                       nvl(substr(TO_NUMBER(SUBSTR(a.high_value, 15, 8), 'XXXXXXXX'),1,6),'0')
                      ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(a.high_value, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(a.high_value, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(a.high_value, 23,2),'XX')-20,0)||':'||nvl(TO_NUMBER(SUBSTR(a.high_value, 25, 2), 'XX')-60,0)
                     ,'DATE',lpad(TO_NUMBER(SUBSTR(a.high_value, 1, 2), 'XX')-100,2,0)||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 3, 2), 'XX')-100,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 5, 2), 'XX') ,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 7, 2), 'XX') ,2,0)|| ' ' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 9, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 11, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(a.high_value, 13, 2), 'XX')-1,2,0)
                        ,  a.high_value),1,32) end high_value
         FROM   (select c.*,regexp_replace(data_type,'\(.+\)') dtype from all_tab_cols c) c,  all_Part_Col_Statistics a ,all_tab_partitions  b
         WHERE  a.owner=c.owner and a.table_name=c.table_name
         AND    a.column_name=c.column_name
         AND    a.owner=B.table_owner and a.table_name=B.table_name and a.partition_name=b.partition_name
         AND    upper(a.owner)=:owner and a.table_name=:object_name AND a.partition_name=:object_subname
         ORDER BY NO#]],
    [[
        SELECT /*INTERNAL_DBCLI_CMD*/ /*PIVOT*/ /*+opt_param('optimizer_dynamic_sampling' 5)*/ *
        FROM   all_tab_partitions T
        WHERE  T.TABLE_OWNER = :1 AND T.TABLE_NAME = :2 AND partition_name=:3]]},
    FIXED_TABLE=[[
        SELECT /*+ordered use_nl(b c) opt_param('optimizer_dynamic_sampling' 5)*/ 
               a.*,
               C.avgcln AVG_LEN,
               C.DISTCNT "NDV",
               CASE WHEN B.ROWCNT>=c.NULL_CNT THEN round(c.NULL_CNT*100/nullif(B.ROWCNT,0),2) END "Nulls(%)",
               CASE WHEN B.ROWCNT>=c.NULL_CNT THEN round((B.ROWCNT-c.NULL_CNT)/nullif(C.DISTCNT,0),2) END CARDINALITY,
               c.sample_size,
               c.TIMESTAMP# LAST_ANALYZED,
               case when LOWVAL is not null then 
               substrb(decode(regexp_substr(DATA_TYPE,'[^\(]+')
                  ,'NUMBER'       ,to_char(utl_raw.cast_to_number(LOWVAL))
                  ,'FLOAT'        ,to_char(utl_raw.cast_to_number(LOWVAL))
                  ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(LOWVAL))
                  ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(LOWVAL))
                  ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(LOWVAL))
                  ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(LOWVAL))
                  ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(LOWVAL))
                  ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(LOWVAL))
                  ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(LOWVAL, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(LOWVAL, 15, 8), 'XXXXXXXX'),1,6),'0')
                  ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(LOWVAL, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(LOWVAL, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(LOWVAL, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(LOWVAL, 25, 2), 'XX')-60,0)
                  ,'DATE',lpad(TO_NUMBER(SUBSTR(LOWVAL, 1, 2), 'XX')-100,2,0)||
                          lpad(TO_NUMBER(SUBSTR(LOWVAL, 3, 2), 'XX')-100,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(LOWVAL, 5, 2), 'XX') ,2,0)|| '-' ||
                          lpad(TO_NUMBER(SUBSTR(LOWVAL, 7, 2), 'XX') ,2,0)|| ' ' ||
                          lpad(TO_NUMBER(SUBSTR(LOWVAL, 9, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(LOWVAL, 11, 2), 'XX')-1,2,0)|| ':' ||
                          lpad(TO_NUMBER(SUBSTR(LOWVAL, 13, 2), 'XX')-1,2,0)
                  ,  LOWVAL),1,32) end LOWVAL,
                case when HIVAL is not null then 
                substrb(decode(regexp_substr(DATA_TYPE,'[^\(]+')
                      ,'NUMBER'       ,to_char(utl_raw.cast_to_number(HIVAL))
                      ,'FLOAT'        ,to_char(utl_raw.cast_to_number(HIVAL))
                      ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(HIVAL))
                      ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(HIVAL))
                      ,'CHAR'         ,to_char(utl_raw.cast_to_varchar2(HIVAL))
                      ,'NCHAR'        ,to_char(utl_raw.cast_to_nvarchar2(HIVAL))
                      ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(HIVAL))
                      ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(HIVAL))
                      ,'TIMESTAMP'   , lpad(TO_NUMBER(SUBSTR(HIVAL, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 5, 2), 'XX') ,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 7, 2), 'XX') ,2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(HIVAL, 15, 8), 'XXXXXXXX'),1,6),'0')
                        ,'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 1, 2), 'XX')-100,2,0)||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 3, 2), 'XX')-100,2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 5, 2), 'XX'),2,0)|| '-' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 7, 2), 'XX'),2,0)|| ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 9, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 11, 2), 'XX')-1,2,0)|| ':' ||
                                    lpad(TO_NUMBER(SUBSTR(HIVAL, 13, 2), 'XX')-1,2,0)|| '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(HIVAL, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                    nvl(TO_NUMBER(SUBSTR(HIVAL, 23,2),'XX')-20,0)||':'||
                                    nvl(TO_NUMBER(SUBSTR(HIVAL, 25, 2), 'XX')-60,0)
                        ,'DATE',lpad(TO_NUMBER(SUBSTR(HIVAL, 1, 2), 'XX')-100,2,0)||
                                lpad(TO_NUMBER(SUBSTR(HIVAL, 3, 2), 'XX')-100,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(HIVAL, 5, 2), 'XX') ,2,0)|| '-' ||
                                lpad(TO_NUMBER(SUBSTR(HIVAL, 7, 2), 'XX') ,2,0)|| ' ' ||
                                lpad(TO_NUMBER(SUBSTR(HIVAL, 9, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(HIVAL, 11, 2), 'XX')-1,2,0)|| ':' ||
                                lpad(TO_NUMBER(SUBSTR(HIVAL, 13, 2), 'XX')-1,2,0)
                        ,  HIVAL),1,32) end HIVAL
        FROM (
            SELECT KQFTAOBJ obj#, c.KQFCOCNO COL#, c.kqfconam COLUMN_NAME,
                   decode(kqfcodty,
                           1,'VARCHAR2',
                           2,'NUMBER',
                           8,'LONG',
                           9,'VARCHAR',
                           12,'DATE',
                           23,'RAW',
                           24,'LONG RAW',
                           58,'CUSTOM OBJ',
                           69,'ROWID',
                           96,'CHAR',
                           100,'BINARY_FLOAT',
                           101,'BINARY_DOUBLE',
                           105,'MLSLABEL',
                           106,'MLSLABEL',
                           111,'REF',
                           112,'CLOB',
                           113,'BLOB',
                           114,'BFILE',
                           115,'CFILE',
                           121,'CUSTOM OBJ',
                           122,'CUSTOM OBJ',
                           123,'CUSTOM OBJ',
                           178,'TIME',
                           179,'TIME WITH TIME ZONE',
                           180,'TIMESTAMP',
                           181,'TIMESTAMP WITH TIME ZONE',
                           231,'TIMESTAMP WITH LOCAL TIME ZONE',
                           182,'INTERVAL YEAR TO MONTH',
                           183,'INTERVAL DAY TO SECOND',
                           208,'UROWID',
                           'UNKNOWN') || '(' || to_char(c.kqfcosiz) || ')' DATA_TYPE,
                   c.kqfcosiz col_size, 
                   c.kqfcooff col_offset, lpad('0x' || TRIM(to_char(c.kqfcooff, 'XXXXXX')), 8) offset_hex,
                   decode(c.kqfcoidx, 0,'','Yes('||c.kqfcoidx||')') "Indexed?"
            FROM   sys.x$kqfta t, sys.x$kqfco c
            WHERE  c.kqfcotab = t.indx
            AND    c.inst_id = t.inst_id
            AND   (t.kqftanam=:object_name or t.kqftanam=(SELECT KQFDTEQU FROM sys.x$kqfdt WHERE KQFDTNAM=:object_name))) a,
            sys.tab_stats$ b,
            sys.hist_head$ c
        WHERE a.obj#=b.obj#(+)
        AND   a.obj#=c.obj#(+)
        AND   a.col#=c.col#(+)
        ORDER  BY 1,2]],
  
  ['ATTRIBUTE DIMENSION']={
    [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
             dimension_type,
             compile_state,
             table_owner,
             table_name,
             table_alias,
             order_num,
             caption,
             description,
             to_char(all_member_name) all_member_name,
             to_char(all_member_caption) all_member_caption,
             to_char(all_member_description) all_member_description
      FROM   (SELECT * FROM all_attribute_dimensions JOIN all_attribute_dim_tables USING (origin_con_id, owner, dimension_name)) ad
      OUTER  APPLY (SELECT MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                           MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  description
                    FROM   all_attribute_dim_class j
                    WHERE  owner = ad.owner
                    AND    dimension_name = ad.dimension_name
                    AND    origin_con_id = ad.origin_con_id)
      WHERE  owner = :owner
      AND    dimension_name = :object_name]],
    (([[
      SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
             dtl.*
      FROM   all_attribute_dimensions ad
      CROSS  APPLY @ad@ dtl
      WHERE  owner=:owner 
      AND    dimension_name=:object_name
      ORDER  BY 1]]):gsub('@ad@',ad))},

  HIERARCHY={
    [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
             dimension_owner, dimension_name,dim_source_table,parent_attr,caption,description
      FROM   all_hierarchies hr
      OUTER APPLY(SELECT MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                         MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  description
                  FROM   all_hier_class j
                  WHERE  owner = hr.owner
                  AND    hier_name = hr.hier_name
                  AND    origin_con_id = hr.origin_con_id)
     JOIN  (SELECT owner dimension_owner, dimension_name, origin_con_id, nullif(table_owner||'.',owner||'.')||table_name dim_source_table FROM all_attribute_dim_tables a) dim_tab
     USING (origin_con_id,dimension_owner, dimension_name)
     WHERE owner = :owner 
     AND   hier_name = :object_name]],

    (([[SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
              dtl.*
      FROM   all_hierarchies ah
      CROSS  APPLY @ah@ dtl
      WHERE  ah.owner = :owner 
      AND    ah.hier_name = :object_name
      ORDER  BY 1]]):gsub('@ah@',ah))},

  ['ANALYTIC VIEW']={
   [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ * 
     FROM  all_analytic_views av
     OUTER APPLY( SELECT MAX(DECODE(classification, 'CAPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  caption,
                         MAX(DECODE(classification, 'DESCRIPTION', regexp_substr(to_char(substr(value,1,1000)),'[^'||chr(10)||']*'))) KEEP(dense_rank LAST ORDER BY LANGUAGE NULLS FIRST)  description
                  FROM   all_analytic_view_class j
                  WHERE  owner = av.owner
                  AND    analytic_view_name = av.analytic_view_name
                  AND    origin_con_id = av.origin_con_id)
     OUTER APPLY  (SELECT av_lvlgrp_order cache_id,
                         listagg(nvl2(level_name,trim('.' from dimension_alias||'.'||hier_alias||'.'||level_name),''),',') WITHIN GROUP(ORDER BY level_meas_order) cache_levels,
                         listagg(measure_name,',')  WITHIN GROUP(ORDER BY level_meas_order) cache_measures
                    FROM   all_analytic_view_lvlgrps 
                    WHERE  owner = av.owner
                    AND    analytic_view_name = av.analytic_view_name
                    AND    origin_con_id = av.origin_con_id
                    GROUP  BY av_lvlgrp_order) 
     WHERE owner = :owner 
     AND   analytic_view_name = :object_name]],
   [[SELECT /*+opt_param('optimizer_dynamic_sampling' 5) */ 
           hier_alias,
           ltrim(nullif(hier_owner, owner) || '.' || hier_name, '.') src_hier_name,
           is_default hier_default,
           '||' "||",
           dimension_alias dim_alias,
           ltrim(nullif(dimension_owner, owner) || '.' || dimension_name, '.') src_dim_name,
           dimension_type,
           ltrim(nullif(dim_tab.table_owner, owner) || '.' || dim_tab.table_name, '.') src_dim_table,
           dim_keys,
           fact_joins,
           references_distinct dim_key_distinct,
           regexp_substr(to_char(substr(all_member_name,1,1000)),'[^'||chr(10)||']*') all_dim_member_name,
           regexp_substr(to_char(substr(all_member_caption,1,1000)),'[^'||chr(10)||']*') all_dim_member_caption,
           regexp_substr(to_char(substr(all_member_description,1,1000)),'[^'||chr(10)||']*') all_dim_member_desc
    FROM   (SELECT owner,
                   analytic_view_name,
                   origin_con_id,
                   dimension_alias,
                   listagg(av_key_column, ',') WITHIN GROUP(ORDER BY order_num) fact_joins,
                   listagg(ref_dimension_attr, ',') WITHIN GROUP(ORDER BY order_num) dim_keys
            FROM   all_analytic_view_keys
            GROUP  BY owner, analytic_view_name, origin_con_id, dimension_alias)
    JOIN   all_analytic_view_dimensions
    USING  (owner, analytic_view_name, origin_con_id, dimension_alias)
    JOIN   all_analytic_view_hiers
    USING  (owner, analytic_view_name, origin_con_id, dimension_alias)
    JOIN   (SELECT owner dimension_owner, dimension_name, origin_con_id, table_owner, table_name FROM all_attribute_dim_tables a) dim_tab
    USING  (dimension_owner, dimension_name, origin_con_id)
    WHERE  owner = :owner
    AND    analytic_view_name = :object_name
    ORDER  BY 1]],
  (([[
    SELECT /*+opt_param('optimizer_dynamic_sampling' 5) */ 
           nvl2(avh.hier_name, 'HIER: ', '') || av.hier_name CATEGORY,
           row_number() over(partition by av.hier_name order by hier.seq,av.order_num) "#",
           hier.hier_level,
           hier.level_type,
           NVL(hier.column_name, av.column_name) column_name,
           hier.alt,
           hier.dtm_levels,
           CASE
               WHEN av.data_type IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                av.data_type || '(' || av.data_length || decode(av.char_used, 'C', ' CHAR') || ')' --
               WHEN av.data_type = 'NUMBER' THEN
                CASE
                    WHEN nvl(av.data_scale, av.data_precision) IS NULL THEN
                     av.data_type
                    WHEN data_scale > 0 THEN
                     av.data_type || '(' || nvl('' || av.data_precision, '38') || ',' || av.data_scale || ')'
                    WHEN av.data_precision IS NULL AND av.data_scale = 0 THEN
                     'INTEGER'
                    ELSE
                     av.data_type || '(' || av.data_precision || ')'
                END
               ELSE
                av.data_type
           END data_type,
           NVL(avc.cached,base.dyn_all_cache) cached,
           av.nullable,
           av.role,
           nvl(RTRIM(nvl2(hier.source_column,hier.source_column || ' => ','') ||
                 nvl2(COALESCE(ak.av_key_column, meas.measure_name),
                      nvl2(meas.measure_name,
                           nvl(meas.aggr_function,base.default_aggr)||'('|| base.table_name || '.' || meas.measure_name||')',
                           base.table_name || '.' || ak.av_key_column),
                      ''),
                 '=> '), to_char(calc.meas_expression)) source_column,
           hier.member_expr,
           hier.skip_null,
           hier.level_order,
           hier.caption caption,
           hier.description DESCRIPTION
    FROM   all_analytic_views base
    JOIN   all_analytic_view_columns av
    ON     (av.owner = base.owner AND av.analytic_view_name = base.analytic_view_name AND av.origin_con_id = base.origin_con_id)
    LEFT   JOIN all_analytic_view_base_meas meas
    ON     (av.owner = meas.owner AND av.analytic_view_name = meas.analytic_view_name AND av.column_name = meas.measure_name AND av.origin_con_id = meas.origin_con_id)
    LEFT   JOIN all_analytic_view_calc_meas calc
    ON     (av.owner = calc.owner AND av.analytic_view_name = calc.analytic_view_name AND av.column_name = calc.measure_name AND av.origin_con_id = calc.origin_con_id)
    LEFT   JOIN all_analytic_view_keys ak
    ON     (av.owner = ak.owner AND av.analytic_view_name = ak.analytic_view_name AND av.column_name = ak.ref_dimension_attr AND av.origin_con_id = ak.origin_con_id)
    LEFT   JOIN all_analytic_view_dimensions ad
    ON     (av.owner = ad.owner AND av.analytic_view_name = ad.analytic_view_name AND av.dimension_name = ad.dimension_alias AND av.origin_con_id = ad.origin_con_id)
    LEFT   JOIN all_analytic_view_hiers avh
    ON     (av.owner = avh.owner AND av.analytic_view_name = avh.analytic_view_name AND av.hier_name = avh.hier_alias AND av.dimension_name = avh.dimension_alias AND av.origin_con_id = avh.origin_con_id)
    OUTER  APPLY (SELECT dtl.*
                  FROM   all_hierarchies ah
                  CROSS  APPLY @ah@ dtl
                  WHERE  av.column_name = TRIM(dtl.column_name)
                  AND    avh.hier_owner = ah.owner
                  AND    avh.hier_name = ah.hier_name
                  AND    avh.origin_con_id = ah.origin_con_id) hier
    OUTER APPLY (SELECT regexp_replace(listagg(av_lvlgrp_order,',') WITHIN GROUP(ORDER BY av_lvlgrp_order),'^0$','Y') CACHED
                 FROM (SELECT *
                       FROM   all_analytic_view_lvlgrps
                       WHERE  av.owner = owner 
                       AND    av.analytic_view_name = analytic_view_name
                       AND    av.origin_con_id = origin_con_id)
                 WHERE measure_name IS NULL AND
                       av.hier_name = hier_alias AND 
                       av.dimension_name = dimension_alias AND
                       regexp_substr(hier.hier_level,'[^\(\) ]+')=level_name
                    OR
                       av.column_name=measure_name AND
                       av.dimension_name IS NULL) avc
    WHERE  base.owner = :owner
    AND    base.analytic_view_name = :object_name
    ORDER  BY av.dimension_name, av.hier_name, hier.seq, av.order_num]]):gsub('@ah@',ah))}
}

desc_sql.VIEW=desc_sql.TABLE[1]
desc_sql['MATERIALIZED VIEW']=desc_sql.TABLE[1]
desc_sql['INDEX PARTITION']=desc_sql.INDEX
desc_sql.FUNCTION=desc_sql.PROCEDURE
desc_sql.TYPE={desc_sql.TYPE,desc_sql.PACKAGE}

function desc.desc(name,option)
    env.checkhelp(name)
    set.set("autohide","on")
    local rs,success,err
    local desc=''
    local obj=db:check_obj(name)
    if obj.object_type=='SYNONYM' then
        local new_obj=db:dba_query(db.get_value,[[WITH r AS
         (SELECT /*+materialize cardinality(p 1) opt_param('_connect_by_use_union_all','old_plan_mode')*/REFERENCED_OBJECT_ID OBJ, rownum lv
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
    elseif obj.object_type=='TABLE' and obj.object_name:find('^X%$') and obj.owner=='SYS' and obj.object_id>=4200000000 then
        env.checkerr(db.props.isdba,"Cannot describe the fixed table without SYSDBA account.")
        obj.object_type="FIXED_TABLE"
        --desc=' (Rows = '..db:get_value('select /*INTERNAL_DBCLI_CMD*/ kqftarsz from sys.x$kqfta where kqftanam=:1',{obj.object_name})..')'
    end

    rs={obj.owner,obj.object_name,obj.object_subname or "",
       obj.object_subname and obj.object_subname~='' and (obj.object_type=="PACKAGE" or obj.object_type=="TYPE") and "PROCEDURE"
       or obj.object_type,2}

    local sqls=desc_sql[rs[4]]
    
    if not sqls then return print("Cannot describe "..rs[4]..'!') end
    if type(sqls)~="table" then sqls={sqls} end
    if rs[4]=="TABLE" then
        local result=db:dba_query(db.internal_call,
                                  [[select nvl(cluster_name,table_name)
                                   from ALL_TABLES
                                   WHERE owner = :owner AND table_name = :object_name]],
                                  {owner=rs[1],object_name=rs[2]})
        result=db.resultset:rows(result,-1)
        result=result[2] or {}
        obj.table_name=result[1]
    elseif (rs[4]=="PROCEDURE" or rs[4]=="FUNCTION") and rs[5]~=2 then
        rs[2],rs[3]=rs[3],rs[2]
    elseif rs[4]=='VIEW' then
        env.var.define_column('Default,Hidden?,AVG_LEN,NDV,Nulls(%),CARDINALITY,HISTOGRAM,BUCKETS,LOW_VALUE,HIGH_VALUE','NOPRINT')
    elseif rs[4]=='ANALYTIC VIEW' then
        env.var.define_column('CATEGORY','BREAK','SKIP','-')
        cfg.set("colsep",'|')
    elseif rs[4]=='TYPE' then
        local result=db:dba_query(db.internal_call,
                                  [[select ELEM_TYPE_OWNER,ELEM_TYPE_NAME,COLL_TYPE,UPPER_BOUND,ELEM_TYPE_MOD
                                   from ALL_COLL_TYPES 
                                   WHERE owner = :owner AND type_name = :object_name]],
                                  {owner=rs[1],object_name=rs[2]})
        result=db.resultset:rows(result,-1)
        if #result>1 then
            result=result[2]
            if result[1]~='' then
                rs[10],rs[11]=result[1],result[2]
            end
            desc=' ['..(result[3]=='TABLE' and 'TABLE' or ('VARRAY('..result[4]..')'))..' OF '..
                       (result[5]~='' and (result[5]..' ') or '')..
                       (result[1]~='' and (result[1]..'.') or '')..result[2]..']'
        end
    end
    local dels='\n'..string.rep("=",80)
    local feed,autohide=cfg.get("feed"),cfg.get("autohide")
    cfg.set("feed","off",true)
    cfg.set("autohide","col",true)
    print(("%s : %s%s%s%s\n"..dels):format(rs[4],rs[1],rs[2]=="" and "" or "."..rs[2],rs[3]=="" and "" or "."..rs[3],desc))
    if rs[10] then
        rs[1],rs[2]=rs[10],rs[11]
    end

    for k,v in pairs{owner=rs[1],object_name=rs[2],object_subname=rs[3],object_type=rs[4],object_id=obj.object_id,table_name=obj.table_name} do
        rs[k]=v
    end

    for i,sql in ipairs(sqls) do
        if sql:find("/*PIVOT*/",1,true) then cfg.set("PIVOT",1) end
        local typ=db.get_command_type(sql)
        local result
        if typ=='DECLARE' or typ=='BEGIN' then
            rs['v_cur']='#CURSOR'
            db:dba_query(db.internal_call,sql,rs)
            result=rs.v_cur
        else
            result=db:dba_query(db.internal_call,sql,rs)
        end
        result=db.resultset:rows(result,-1)
        if #result>1 then 
            grid.print(result)
            if i<#sqls then print(dels) end
        end
    end

    if option and option:upper()=='ALL' then
        if rs[2]==""  then rs[2],rs[3]=rs[3],rs[2] end
        print(dels)
        cfg.set("PIVOT",1)
        db:dba_query([[SELECT * FROM ALL_OBJECTS WHERE OWNER=:1 AND OBJECT_NAME=:2 AND nvl(SUBOBJECT_NAME,' ')=nvl(:3,' ')]],rs)
    end
    cfg.temp("autohide",autohide,true)
    cfg.temp("feed",feed,true)
end

env.set_command(nil,{"describe","desc"},'Describe database object. Usage: @@NAME [owner.]<object>[.<partition>|.<sub_program>] [all]',desc.desc,false,3)
return desc
