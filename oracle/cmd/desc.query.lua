-- Use dbms_sql to parse select statement and generate column information

-- Define columns to be hidden
env.var.define_column('OWNER,TABLE_NAME,OBJECT_NAME,SUBOBJECT_NAME,OBJECT_TYPE','NOPRINT')

-- Return SQL for parsing select statement
return [[
    DECLARE /*INTERNAL_DBCLI_CMD topic="Column info"*/
        v_cursor     INTEGER;
        v_col_cnt    INTEGER;
        v_desc_tab   dbms_sql.desc_tab3;
        v_owner      VARCHAR2(128) := :owner;
        v_schema     VARCHAR2(128) := sys_context('userenv','current_schema');
        v_sql        CLOB := :query;
        v_xml        XMLTYPE := XMLTYPE('<columns/>');
        v_stack      VARCHAR2(4000);
        v_typename   VARCHAR2(30);
        cur          SYS_REFCURSOR;
        TYPE t IS TABLE OF VARCHAR2(30) INDEX BY PLS_INTEGER;
        v_types t;
    BEGIN
        IF v_owner = v_schema OR v_owner like '<%>' THEN
            v_owner := NULL;
        END IF;
        v_types(1)    := 'VARCHAR';
        v_types(2)    := 'NUMBER';
        v_types(3)    := 'NATIVE INTEGER';
        v_types(8)    := 'LONG';
        v_types(9)    := 'VARCHAR';
        v_types(11)   := 'ROWID';
        v_types(12)   := 'DATE';
        v_types(23)   := 'RAW';
        v_types(24)   := 'LONG RAW';
        v_types(29)   := 'BINARY_INTEGER';
        v_types(69)   := 'ROWID';
        v_types(96)   := 'CHAR';
        v_types(100)  := 'BINARY_FLOAT';
        v_types(101)  := 'BINARY_DOUBLE';
        v_types(102)  := 'REF CURSOR';
        v_types(104)  := 'UROWID';
        v_types(105)  := 'MLSLABEL';
        v_types(106)  := 'MLSLABEL';
        v_types(110)  := 'REF';
        v_types(111)  := 'REF';
        v_types(112)  := 'CLOB';
        v_types(113)  := 'BLOB'; 
        v_types(114)  := 'BFILE'; 
        v_types(115)  := 'CFILE';
        v_types(119)  := 'JSON';
        v_types(121)  := 'OBJECT';
        v_types(122)  := 'TABLE';
        v_types(123)  := 'VARRAY';
        v_types(127)  := 'VECTOR';
        v_types(178)  := 'TIME';
        v_types(179)  := 'TIME WITH TIME ZONE';
        v_types(180)  := 'TIMESTAMP';
        v_types(181)  := 'TIMESTAMP WITH TIME ZONE';
        v_types(231)  := 'TIMESTAMP WITH LOCAL TIME ZONE';
        v_types(182)  := 'INTERVAL YEAR TO MONTH';
        v_types(183)  := 'INTERVAL DAY TO SECOND';
        v_types(208)  := 'UROWID';
        v_types(250)  := 'PL/SQL RECORD';
        v_types(251)  := 'PL/SQL TABLE';
        v_types(252)  := 'BOOLEAN';
        -- Open cursor
        v_cursor := dbms_sql.open_cursor;
        
        BEGIN
            -- Parse SQL statement
            $IF dbms_db_version.version < 12 $THEN
            IF v_owner IS NOT NULL THEN
                EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA="'||v_owner||'"';
                v_owner := '1';
            END IF;
            $END

            dbms_sql.parse(
                c=>v_cursor, 
                statement=>:query, 
            $IF dbms_db_version.version > 11 $THEN
                schema => v_owner,
                container => sys_context('userenv','con_name'),
            $END
                language_flag =>dbms_sql.native);
            
            -- Get column descriptions
            dbms_sql.describe_columns3(
                c => v_cursor, 
                col_cnt => v_col_cnt, 
                desc_t => v_desc_tab);
            
            -- Close cursor
            dbms_sql.close_cursor(v_cursor);
            
            -- Generate XML results
            FOR i IN 1..v_col_cnt LOOP
                v_typename := v_desc_tab(i).col_type;
                IF v_typename+0 IN(1,9,96,112) AND v_desc_tab(i).col_charsetform=2 THEN
                    v_typename := 'N'||v_types(v_typename+0);
                ELSIF v_typename+0=2 AND v_desc_tab(i).col_scale=-127 THEN
                    v_typename := 'FLOAT';
                ELSIF v_typename+0=2 AND nvl(v_desc_tab(i).col_scale,0)=0 AND v_desc_tab(i).col_precision=38 THEN
                    v_typename := 'INTEGER';
                ELSIF v_types.exists(v_typename+0) THEN
                    v_typename := v_types(v_typename+0);
                END IF;
                v_stack := '<column>
                    <position>' || i || '</position>
                    <name>' || dbms_xmlgen.convert(v_desc_tab(i).col_name, dbms_xmlgen.ENTITY_ENCODE) || '</name>
                    <type>' || dbms_xmlgen.convert(nvl(v_desc_tab(i).col_type_name,v_typename), dbms_xmlgen.ENTITY_ENCODE) || '</type>
                    <length>' || v_desc_tab(i).col_max_len || '</length>
                    <precision>' || v_desc_tab(i).col_precision || '</precision>
                    <scale>' || v_desc_tab(i).col_scale || '</scale>
                    <nullable>' || CASE WHEN v_desc_tab(i).col_null_ok THEN 'Y' ELSE 'N' END || '</nullable>
                </column>';
                v_xml := v_xml.appendchildxml('//columns', XMLTYPE(v_stack));
            END LOOP;
            IF v_owner = '1' THEN
                EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA="'||v_schema||'"';
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                -- Close cursor
                IF dbms_sql.is_open(v_cursor) THEN
                    dbms_sql.close_cursor(v_cursor);
                END IF;
                IF v_owner = '1' THEN
                    EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA="'||v_schema||'"';
                END IF;
                RAISE;
        END;
        
        -- Open cursor to return results
        OPEN cur FOR
            SELECT x.NO#,
                   x.NAME COLUMN_NAME,
                   CASE WHEN DATA_TYPE IN('CHAR','VARCHAR','VARCHAR2','NCHAR','NVARCHAR','NVARCHAR2','RAW') --
                       THEN DATA_TYPE||'(' || DATA_LENGTH || ')' --
                     WHEN DATA_TYPE IN('NCLOB','CLOB','BLOB') THEN
                         DATA_TYPE||'['||DATA_LENGTH||' INLINE]'
                     WHEN DATA_TYPE = 'NUMBER' --
                     THEN (CASE WHEN nvl(DATA_scale, DATA_PRECISION) IS NULL THEN DATA_TYPE
                              WHEN DATA_SCALE > 0 THEN DATA_TYPE||'(' || NVL(''||nullif(DATA_PRECISION,0), '38') || ',' || DATA_SCALE || ')'
                              WHEN DATA_PRECISION IS NULL AND DATA_SCALE=0 THEN 'INTEGER'
                              WHEN DATA_PRECISION=0 THEN DATA_TYPE
                              ELSE DATA_TYPE||'(' || DATA_PRECISION ||')' END)
                     ELSE DATA_TYPE 
                   END DATA_TYPE,
                   CASE WHEN x.NULLABLE = 'Y' THEN '' ELSE 'NOT NULL' END NULLABLE
            FROM XMLTABLE(
                '/columns/column'
                PASSING v_xml
                COLUMNS
                    NO#         NUMBER PATH 'position',
                    NAME        VARCHAR2(128) PATH 'name',
                    DATA_TYPE   VARCHAR2(128) PATH 'type',
                    DATA_LENGTH NUMBER PATH 'length',
                    DATA_PRECISION NUMBER PATH 'precision',
                    DATA_SCALE  NUMBER PATH 'scale',
                    NULLABLE    VARCHAR2(1) PATH 'nullable'
            ) x
            ORDER BY x.NO#;
        
        :v_cur := cur;
    END;
]]