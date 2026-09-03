
return [[
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
        tname   VARCHAR2(128) := :object_name;
        oname   VARCHAR2(128) := nvl(:object_subname, :object_name);
        own     VARCHAR2(128) := :owner;
        oid     INT           := :object_id;
        v_target VARCHAR2(500):=:owner || NULLIF('.' || :object_name, '.') || NULLIF('.' || :object_subname, '.');
        type t_idx IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;
        v_idx    t_idx;
    BEGIN
        select nvl(max(object_id),oid) into oid 
        from   all_procedures 
        where  owner=own 
        and    object_name=:object_name 
        and    rownum<2;

        $IF DBMS_DB_VERSION.VERSION > 10 $THEN
        OPEN cur for 
        WITH args AS(
            SELECT /*+opt_param('container_data' 'all') opt_param('parallel_execution_enabled', 'false')*/ -- ADB-- ORA-00600: internal error code, arguments: [evaopn2.h:kaf_qeeCol]
                   overload,
                   SEQUENCE*1e8 s,
                   DATA_LEVEL l,
                   POSITION p,
                   decode(0 + POSITION, 0, '(RETURNS)', Nvl(argument_name, '<Collection>')) Argument,
                   CASE
                       WHEN pls_type != data_type THEN
                        pls_type
                       WHEN type_subname IS NOT NULL THEN
                        type_name || '.' || type_subname || '(' || DATA_TYPE || ')'
                       WHEN type_name IS NOT NULL THEN
                        type_owner||'.'||type_name || '(' || data_type || ')'
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
                                                 t.data_length||DECODE(char_used, 'B', ' BYTE',' CHAR')
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
                       CHARACTER_SET_NAME charset,
                       type_owner,
                       type_name,
                       type_subname,
                       ' ' coll_type
                FROM   all_arguments t
                WHERE  owner = own
                AND    object_id = oid
                AND    object_name = oname
            $IF DBMS_DB_VERSION.VERSION <18 $THEN
                )
            $ELSE
                AND    data_level= 0)
        ,plsql(overload,s,l,p,argument,data_type,in_out,defaulted,charset,type_owner,type_name,type_subname,coll_type,lv) AS(
            SELECT  r.*,
                    1 lv
            FROM   args r
            UNION ALL
            SELECT /*+outline_leaf leading(r) cardinality(r 3) push_pred(s) monitor*/
                    r.overload,
                    r.s + s.attr_no*1e8/power(100,r.lv) s,
                    r.l + 1 l,
                    s.attr_no p,
                    s.attr_name argument ,
                    CASE
                       WHEN attr_type_name IN ('CHAR', 'VARCHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR', 'NVARCHAR2', 'RAW') THEN
                        attr_type_name || '(' || LENGTH || ')' --
                       WHEN attr_type_name = 'NUMBER' THEN
                        (CASE
                            WHEN nvl(scale, precision) IS NULL THEN
                             attr_type_name
                            WHEN scale > 0 THEN
                             attr_type_name || '(' || NVL('' || precision, '38') || ',' || scale || ')'
                            WHEN precision IS NULL AND scale = 0 THEN
                             'INTEGER'
                            ELSE
                             attr_type_name || '(' || precision || ')'
                        END)
                       ELSE
                        nullif(s.attr_type_package||'.','.')||s.attr_type_name
                   END data_type,
                    ' ' in_out,
                    null defaulted,
                    s.character_set_name,
                    s.attr_type_owner,
                    s.attr_type_package,
                    s.attr_type_name,
                    s.coll_type,
                    r.lv + 1 lv
            FROM   plsql r,
                   LATERAL(
                       SELECT /*+OUTLINE_LEAF leading(t s) use_nl(t s) push_pred(t) push_pred(s)*/ 
                              s.*,t.coll_type||NULLIF('('||t.upper_bound||t.index_by||')','()') coll_type
                       FROM   all_plsql_coll_types t, all_plsql_type_attrs s
                       WHERE  t.elem_type_owner = s.owner
                       AND    t.elem_type_name = s.type_name
                       AND    t.elem_type_package = s.package_name
                       AND    r.type_owner = t.owner
                       AND    r.type_name = t.package_name
                       AND    r.type_subname = t.type_name
                       UNION ALL
                       SELECT /*+OUTLINE_LEAF use_nl(t) push_pred(t)*/  
                              t.*,'PL/SQL RECORD'
                       FROM   all_plsql_type_attrs t
                       WHERE  r.type_owner = t.owner
                       AND    r.type_name = t.package_name
                       AND    r.type_subname = t.type_name) s
            WHERE r.type_subname IS NOT NULL
            )
            SEARCH DEPTH FIRST BY s SET ord
            CYCLE s SET cycle TO 1 DEFAULT 0
        $END
        ,base as(
        $IF DBMS_DB_VERSION.VERSION <18 $THEN
            select /*+materialzie*/ a.*, s s_ from args a 
        $ELSE
            select /*+materialzie*/ a.*, ord s_ from plsql a
        $END
        )
        SELECT /*+opt_param('_fix_control' '10182051:0,26552730:0,31945701:0,32108311:0,33926164:0,34092979:0,34970514:0,35495824:0,33792497:0,36554842:0,36283175:0,31720959:0,36004220:0,36635255:0,36675198:0,36868551:0,37400112:0,37626161:0,37668482:0')*/
                decode(p,'-','-',TRIM('.' FROM o || replace(p,' '))) no#, 
               '|' "|",
               lpad(' ', l * 2) || Argument Argument, 
               data_type, 
               IN_OUT, 
               defaulted "Default?",
               CHARSET
        FROM  base
        MODEL PARTITION BY(to_number(0+overload) o) DIMENSION BY(to_number(s_) s, to_number(l) l) 
        MEASURES(CAST(p AS VARCHAR2(30)) p, Argument, data_type, IN_OUT, defaulted, CHARSET,coll_type) 
        RULES SEQUENTIAL ORDER(
            p [ANY,ANY] ORDER BY s = max(p) [s < cv(s), CV(l) - 1] || '.' || lpad(p [CV(), CV()],4),
            p [9999E8,0]='-',
            data_type[ANY,ANY] ORDER BY s  = CASE WHEN trim(coll_type[cv()+1,cv()+1]) IS NOT NULL THEN REGEXP_REPLACE(data_type[cv(),cv()],'\(.*?\)$')||' ['||coll_type[cv()+1,cv()+1]||']' ELSE data_type[cv(),cv()] END
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
                       NVL(precision#, 0) precision,
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
                119, 'JSON',
                121, 'OBJECT',
                122, 'TABLE',
                123, 'VARRAY',
                127, 'VECTOR',
                178, 'TIME',
                179, 'TIME WITH TIME ZONE',
                180, 'TIMESTAMP',
                181, 'TIMESTAMP WITH TIME ZONE',
                231, 'TIMESTAMP WITH LOCAL TIME ZONE',
                182, 'INTERVAL YEAR TO MONTH',
                183, 'INTERVAL DAY TO SECOND',
                250, 'PL/SQL RECORD',
                251, 'PL/SQL TABLE',
                252, 'BOOLEAN',
                'UNKNOWN('||dtyp(i)||')') || 
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
            SELECT /*+no_merge(a) no_merge(b) use_nl(b a) push_pred(a) opt_param('container_data' 'all') ordered opt_param('optimizer_dynamic_sampling' 5) */ 
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
                            CASE WHEN DATA_precision>0 THEN '('||DATA_precision||NULLIF(','||DATA_SCALE,',')||')'
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
    END;]]