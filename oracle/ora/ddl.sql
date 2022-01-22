/*[[
   Get DDL statement. Usage: @@NAME {[owner.]<object_name> [<object_type>] [-seg|-storge|-part]}
   -seg    : remove segment attributes
   -storage: remove storage clause
   -part   : remove partition clause
   --[[
        @CHECK_ACCESS_OBJ: dba_views={dba_views}, default={all_views}
        @CHECK_ACCESS_COLS: dba_tab_cols={dba_tab_cols} default={all_tab_cols}
        @CHECK_ACCESS_EXP : sys.dbms_sql2={1} default={0}
        @ver: 12.1={dbms_utility} default={sys.dbms_sql2}
        @ARGS: 1
        &seg: default={true} seg={false}
        &st: default={true} storage={false}
        &pt: default={true} part={false}
   --]]
]]*/


SET FEED OFF VERIFY OFF
VAR TEXT CLOB;
VAR DEST VARCHAR2
ora _find_object "&V1" 1

DECLARE
    v_default     NUMBER := DBMS_METADATA.SESSION_TRANSFORM;
    schem         VARCHAR2(128):= :object_owner;
    part1         VARCHAR2(128):= :object_name;
    name          VARCHAR2(128); 
    obj_type      VARCHAR2(128):= nvl(upper(:V2),:object_type);
    txt           CLOB;
    vw            VARCHAR2(256);
    cols          VARCHAR2(32767);
BEGIN
    IF :V1 IS NULL THEN
        raise_application_error(-20001,'Please specify the object name!');
    END IF;
    IF obj_type in('VIEW','SYNONYM') THEN
        for r in(select column_id,column_name from &CHECK_ACCESS_COLS where owner=schem and table_name=regexp_replace(part1,'^G?V_?','GV_') order by column_id) loop
            cols:=cols||case when r.column_id>1 then ',' end||r.column_name;
            if mod(r.column_id,10)=0 then
                cols:=cols||chr(10)||'        ';
            end if;
        end loop;

        IF cols IS NOT NULL THEN
            cols:='CREATE OR REPLACE VIEW '||schem||'.'||regexp_replace(part1,'^G?V_?','GV_')||'('||trim(',' from cols)||') AS '||chr(10);
        END IF;

        BEGIN
            /*$IF DBMS_DB_VERSION.VERSION>11 OR &CHECK_ACCESS_EXP=1 $THEN
                vw := 'SELECT * FROM '||schem||'.'||part1;
                &ver..expand_sql_text(vw,txt);
            $ELSE*/
                name := regexp_replace(part1,'^G?V_?','GV');
                EXECUTE IMMEDIATE q'[SELECT VIEW_NAME,VIEW_DEFINITION FROM V$FIXED_VIEW_DEFINITION WHERE VIEW_NAME=:1]'
                    INTO vw,txt USING name;
            --$END
            IF txt is not null then
                txt:=trim(',' from cols)||regexp_replace(txt,' from ',chr(10)||'from ',1,1,'i') ||';';
                txt:=regexp_replace(txt,',[ ]+',',');
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;

        IF txt IS NULL THEN
            FOR R IN(SELECT TEXT FROM &CHECK_ACCESS_OBJ WHERE OWNER=schem AND VIEW_NAME=part1) LOOP
                IF r.text IS NOT NULL THEN 
                    txt := cols || r.text ||';';
                END IF;
            END LOOP;
        END IF;
    END IF;

    IF txt IS NULL THEN
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'DEFAULT', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SQLTERMINATOR', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SEGMENT_ATTRIBUTES', &seg);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'STORAGE', &st);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'TABLESPACE', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SPECIFICATION', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'BODY', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'CONSTRAINTS', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'CONSTRAINTS_AS_ALTER', TRUE);
        $IF DBMS_DB_VERSION.VERSION>10 $THEN
            DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'PARTITIONING', &pt);
        $END
        $IF DBMS_DB_VERSION.VERSION>11 $THEN
            DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'PHYSICAL_PROPERTIES', &pt);
        $END
        BEGIN
            IF part1 IS NULL THEN
                IF :V2 IS NOT NULL THEN
                    part1:=:V1;
                    IF NOT part1 LIKE '%"%' THEN
                        part1 := UPPER(part1);
                    END IF;
                    IF part1 LIKE '%.%' THEN
                        schem := regexp_substr(part1,'^[^\/.]+');
                        part1 := regexp_substr(part1,'[^\/.]+$');
                    END IF;
                    txt := dbms_metadata.get_ddl(REPLACE(obj_type, ' ', '_'), part1,schem);
                ELSE 
                    raise_application_error(-20001,'Cannot find target object.');
                END IF;
            ELSE
                txt := dbms_metadata.get_ddl(REPLACE(obj_type, ' ', '_'), part1, SCHEM);
            END IF;
        EXCEPTION WHEN OTHERS THEN
            IF sqlcode=-31603 AND obj_type='VIEW' AND DBMS_DB_VERSION.VERSION>11 THEN --object "%s" of type VIEW not found in schema "SYS"
                NULL;
                $IF DBMS_DB_VERSION.VERSION>11 $THEN
                    SELECT MAX(TEXT_VC) 
                    into   txt
                    FROM   &CHECK_ACCESS_OBJ 
                    WHERE OWNER=schem 
                    AND VIEW_NAME=part1;

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
        IF REGEXP_SUBSTR(obj_type,'[^ +]') in ('TABLE','ANALYTIC','HIERARCHY','ATTRIBUTE') THEN
            BEGIN
                dbms_lob.append(txt,dbms_metadata.GET_DEPENDENT_DDL('INDEX', part1, SCHEM));
                NULL;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END IF;
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'DEFAULT');
        txt := regexp_replace(txt, '\(' || chr(9), '(' || chr(10) || chr(9), 1, 1);
        IF REGEXP_SUBSTR(obj_type,'[^ +]') NOT IN('TRIGGER','FUNCTION','PROCEDURE','PACKAGE') THEN
            txt := regexp_replace(txt, '"([A-Z][A-Z0-9$#\_]+)"', '\1');
        END IF;
    END IF;
    :text := txt;
    :dest := part1 || '.sql';
EXCEPTION WHEN OTHERS THEN
    raise_application_error(-20001,sqlerrm);
END;
/

print text
PRO
save text dest