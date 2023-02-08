
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
        oname   VARCHAR2(128):= nvl(:object_subname, :object_name);
        own     VARCHAR2(128):= :owner;
        oid     INT          := :object_id;
        v_target VARCHAR2(100):=:owner || NULLIF('.' || :object_name, '.') || NULLIF('.' || :object_subname, '.');
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
            SELECT decode(p,'-','-',TRIM('.' FROM o || replace(p,' '))) no#, 
                   '|' "|",
                   Argument, 
                   data_type, 
                   IN_OUT, 
                   defaulted "Default?",
                   CHARSET
            FROM   (SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
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
                p [ANY,ANY] ORDER BY s = max(p) [s < cv(s), CV(l) - 1] || '.' || lpad(p [CV(), CV()],4),
                p [9999,0]='-')
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
    END;]]