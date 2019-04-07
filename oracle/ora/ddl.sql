/*[[
   Get DDL statement. Usage: @@NAME {[owner.]<object_name> [<file_ext>]}
   --[[
        @CHECK_ACCESS_OBJ: dba_objects={dba_views}, default={all_views}
        @CHECK_ACCESS_COLS: dba_tab_cols={dba_tab_cols} default={all_tab_cols}
        @ARGS: 1
   --]]
]]*/


SET FEED OFF VERIFY OFF
VAR TEXT CLOB;
VAR DEST VARCHAR2
ora _find_object &V1

DECLARE
    v_default     NUMBER := DBMS_METADATA.SESSION_TRANSFORM;
    schem         VARCHAR2(128):= :object_owner;
    part1         VARCHAR2(128):= :object_name;
    name          VARCHAR2(128); 
    obj_type      VARCHAR2(128):= :object_type;
    txt           CLOB;
    vw            VARCHAR2(256);
    cols          VARCHAR2(32767);
BEGIN
    IF obj_type in('VIEW','SYNONYM') THEN
        BEGIN
            name := regexp_replace(part1,'^G?V_?','GV');
            EXECUTE IMMEDIATE q'[SELECT VIEW_NAME,VIEW_DEFINITION FROM V$FIXED_VIEW_DEFINITION WHERE VIEW_NAME=:1]'
                INTO vw,txt USING name;
            IF txt is not null then
                for r in(select column_name from dba_tab_cols where owner='SYS' and table_name=regexp_replace(name,'GV','GV_') order by column_id) loop
                    cols:=cols||','||r.column_name;
                end loop;
                txt:='CREATE OR REPLACE VIEW SYS.'||vw||'('||trim(',' from cols)||') AS '||chr(10)||regexp_replace(txt,' from ',chr(10)||'from ',1,1);
                txt:=regexp_replace(txt,',[ ]+',',');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;

        IF txt IS NULL THEN
            FOR R IN(SELECT TEXT FROM &CHECK_ACCESS_OBJ WHERE OWNER=schem AND VIEW_NAME=part1) LOOP
                txt := r.text;
            END LOOP;
        END IF;
    END IF;

    IF txt IS NULL THEN
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'DEFAULT', TRUE);

        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SQLTERMINATOR', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SEGMENT_ATTRIBUTES', true);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'STORAGE', true);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'TABLESPACE', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SPECIFICATION', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'BODY', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'CONSTRAINTS', FALSE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'CONSTRAINTS_AS_ALTER', FALSE);
        --DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'PARTITIONING', FALSE);
        txt := dbms_metadata.get_ddl(REPLACE(obj_type, ' ', '_'), part1, SCHEM);
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
    :dest := part1 || '.'||nvl(:V2,'sql');
EXCEPTION WHEN OTHERS THEN
    raise_application_error(-20001,sqlerrm);
END;
/

print text
PRO
save text dest