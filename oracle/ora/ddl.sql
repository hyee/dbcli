/*[[
   Get the DDL statement. Usage: @@NAME {[owner.]<object_name> [<object_type>] [-seg|-storage|-part]}
   -seg     : Remove the segment attributes
   -storage : Remove the storage clause
   -part    : Remove the partition clause
   -expand  : Expand the SQL text if the target is a view
   --[[
        @CHECK_ACCESS_OBJ: dba_views={dba_views}, default={all_views}
        @CHECK_ACCESS_COLS: dba_tab_cols={dba_tab_cols} default={all_tab_cols}
        @CHECK_ACCESS_EXP : sys.dbms_sql2={1} default={0}
        @ver: 12.1={dbms_utility} default={sys.dbms_sql2}
        @ARGS: 1
        &seg: default={true} seg={false}
        &st: default={true} storage={false}
        &pt: default={true} part={false}
        &expand: default={0} expand={1}
   --]]
]]*/


SET FEED OFF VERIFY OFF
VAR TEXT CLOB;
VAR DEST VARCHAR2
ora _find_object "&V1" 1

DECLARE
    v_default  NUMBER := dbms_metadata.session_transform;
    schem      VARCHAR2(128) := :object_owner;
    part1      VARCHAR2(128) := :object_name;
    name       VARCHAR2(128);
    obj_type   VARCHAR2(128) := nvl(upper(:v2),:object_type);
    txt        CLOB;
    vw         VARCHAR2(256);
    cols       VARCHAR2(32767);
BEGIN
    IF :v1 IS NULL THEN
        raise_application_error(-20001,'Please specify the object name!');
    END IF;
    IF obj_type IN ('VIEW','SYNONYM') THEN
        FOR r IN(SELECT column_id,column_name
                 FROM   &CHECK_ACCESS_COLS
                 WHERE  owner=schem
                 AND    table_name=regexp_replace(part1,'^G?V_?\$','GV_$')
                 ORDER  BY column_id) LOOP
            cols := cols || CASE WHEN r.column_id > 1 THEN ',' END || r.column_name;
            IF mod(r.column_id,10)=0 THEN
                cols := cols || chr(10) || '        ';
            END IF;
        END LOOP;

        IF cols IS NOT NULL THEN
            cols := 'CREATE OR REPLACE VIEW ' || schem || '.' ||
                    regexp_replace(part1,'^G?V_?\$','GV_$') || '(' ||
                    trim(',' FROM cols) || ') AS ' || chr(10);
        END IF;

        IF &expand=1 THEN
            BEGIN
                $IF dbms_db_version.version > 11 OR &CHECK_ACCESS_EXP=1 $THEN
                    vw := 'SELECT * FROM ' || schem || '.' || part1;
                    dbms_output.put_line(vw);
                    &ver..expand_sql_text(vw,txt);
                $ELSE
                    name := regexp_replace(part1,'^G?V_?\$','GV_$');
                    EXECUTE IMMEDIATE q'[SELECT VIEW_NAME,VIEW_DEFINITION FROM V$FIXED_VIEW_DEFINITION WHERE VIEW_NAME=:1]'
                        INTO   vw,txt USING name;
                $END
                IF txt IS NOT NULL THEN
                    txt := trim(',' FROM cols) || regexp_replace(txt,' from ',chr(10) || 'FROM ',1,1,'i') || ';';
                    txt := regexp_replace(txt,',[ ]+',',');
                END IF;
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
        END IF;
        IF txt IS NULL THEN
            FOR r IN(SELECT text
                     FROM   &CHECK_ACCESS_OBJ
                     WHERE  owner=schem
                     AND    view_name=part1) LOOP
                IF r.text IS NOT NULL THEN
                    txt := cols || r.text || ';';
                END IF;
            END LOOP;
        END IF;
    END IF;

    IF txt IS NULL THEN
        dbms_metadata.set_transform_param(v_default,'DEFAULT',TRUE);
        dbms_metadata.set_transform_param(v_default,'SQLTERMINATOR',TRUE);
        dbms_metadata.set_transform_param(v_default,'SEGMENT_ATTRIBUTES',&seg);
        dbms_metadata.set_transform_param(v_default,'STORAGE',&st);
        dbms_metadata.set_transform_param(v_default,'TABLESPACE',TRUE);
        dbms_metadata.set_transform_param(v_default,'SPECIFICATION',TRUE);
        dbms_metadata.set_transform_param(v_default,'BODY',TRUE);
        dbms_metadata.set_transform_param(v_default,'CONSTRAINTS',TRUE);
        dbms_metadata.set_transform_param(v_default,'CONSTRAINTS_AS_ALTER',TRUE);
        $IF dbms_db_version.version > 10 $THEN
            dbms_metadata.set_transform_param(v_default,'PARTITIONING',&pt);
        $END
        $IF dbms_db_version.version > 11 $THEN
            dbms_metadata.set_transform_param(v_default,'PHYSICAL_PROPERTIES',&pt);
        $END
        BEGIN
            IF part1 IS NULL THEN
                IF :v2 IS NOT NULL THEN
                    part1 := :v1;
                    IF NOT part1 LIKE '%"%' THEN
                        part1 := upper(part1);
                    END IF;
                    IF part1 LIKE '%.%' THEN
                        schem := regexp_substr(part1,'^[^\/.]+');
                        part1 := regexp_substr(part1,'[^\/.]+$');
                    END IF;
                    txt := dbms_metadata.get_ddl(replace(obj_type,' ','_'),part1,schem);
                ELSE
                    raise_application_error(-20001,'Cannot find target object.');
                END IF;
            ELSE
                txt := dbms_metadata.get_ddl(replace(obj_type,' ','_'),part1,schem);
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF sqlcode = -31603 AND obj_type = 'VIEW' AND dbms_db_version.version > 11 THEN --object "%s" of type VIEW not found in schema "SYS"
                    NULL;
                    $IF dbms_db_version.version > 11 $THEN
                        SELECT MAX(text_vc)
                        INTO   txt
                        FROM   &CHECK_ACCESS_OBJ
                        WHERE  owner=schem
                        AND    view_name=part1;

                        IF trim(txt) IS NULL THEN
                            raise;
                        ELSE
                            txt := cols || txt || ';';
                        END IF;
                    $END
                ELSE
                    raise;
                END IF;
        END;
        IF regexp_substr(obj_type,'^\w+') IN ('TABLE','ANALYTIC','HIERARCHY','ATTRIBUTE') THEN
        BEGIN
            dbms_lob.append(txt,dbms_metadata.get_dependent_ddl('INDEX',part1,schem));
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
        END IF;
        
        dbms_metadata.set_transform_param(v_default,'DEFAULT');
        txt := regexp_replace(txt,'\(' || chr(9),'(' || chr(10) || chr(9),1,1);
        IF regexp_substr(obj_type,'^\w+') NOT IN ('TRIGGER','FUNCTION','PROCEDURE','PACKAGE') THEN
            txt := regexp_replace(txt,'"([A-Z][A-Z0-9$#\_]+)"','\1');
        END IF;
    END IF;
    
    IF regexp_substr(obj_type,'^\w+') IN ('TABLE','VIEW','SYNONYM') THEN
    BEGIN
        dbms_lob.append(txt,dbms_metadata.get_dependent_ddl('COMMENT',part1,schem));
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;
    END IF;
    :text := txt;
    :dest := part1 || '.sql';
EXCEPTION
    WHEN OTHERS THEN
        raise_application_error(-20001,sqlerrm);
END;
/

print text
PRO
save text dest
