/*[[
    Tune or explain query rewrite on target materialized view. Usage: @@NAME {[-tune|-xplan] <mview_name> | -rw <sql_id>} <select statement>
    -xplan   : default,execute DBMS_MVIEW.EXPLAIN_REWRITE for target SQL with existing MVIEW
    -tune    : execute DBMS_ADVISOR.TUNE_MVIEW to generate the DDLs for relative MVIEW and MVIEW logs.
    -rw      : execute DBMS_ADVANCED_REWRITE.DECLARE_REWRITE_EQUIVALENCE in `general` mode to rewrite target SQL ID as the query.
               needs to set QUERY_REWRITE_INTEGRITY = TRUSTED/STALE_TOLERATED, the SQL will be rewritten only in the same parsing SCHEMA(CURRENT_SCHEMA)
               Other rewrite_modes(refer to the docs for the meanings):
               -rewrite  : general, same to option `-rw`
               -disable  : disabled
               -recursive: recursive
               -text     : text_match
               -mv       : tune_mview
               -drop     : drop rewrite equivalance
    <select> : support EOF syntax. For DBMS_ADVANCED_REWRITE.DECLARE_REWRITE_EQUIVALENCE interface:
               * if <select> is a SQL_Id then auto get SQL text
               * if <select> is NULL and target rewrite equivalance exists:
                 ** if `rewrite_modes` is different, then change the `rewrite_modes`
    --[[
        @ARGS: 2
        &tune: xplan={0} tune={1} rewrite={2} rw={2} mv={2} disable={2} recursive={2} text={2} drop={2}
        &wrap: xplan={100} tune={180}
        &mode: rewrite={general} rw={general} mv={tune_mview} disable={disabled} recursive={recursive} text={text_match} drop={drop}
        @check_access_rewrite: SYS.DBMS_ADVANCED_REWRITE={1} DEFAULT={0}
    --]]
]]*/
ora _find_object "&V1" 1
COL QUERY_TEXT,REWRITTEN_TEXT,MV_OWNER,MV_NAME NOPRINT
SET COLWRAP &wrap AUTOHIDE COL
set feed off verify off
COL QUERY_BLOCK_NO HEAD QB#
COL SEQUENCE HEAD #
col ORIGINAL_COST,REWRITTEN_COST FOR K5
VAR C REFCURSOR
VAR rw REFCURSOR "REWRITTEN TEXT";
VAR create_script CLOB;
VAR undo_script CLOB;
VAR script_suffix VARCHAR2
DECLARE
    MSG   SYS.REWRITEARRAYTYPE := SYS.REWRITEARRAYTYPE();
    stmt  CLOB          := :V2;
    own   VARCHAR2(128) := nvl(:OBJECT_OWNER,SYS_CONTEXT('USERENV','CURRENT_SCHEMA'));
    src   VARCHAR2(256) := :V1;
    name  VARCHAR2(256) := '"'||:OBJECT_OWNER||'"."'||:OBJECT_NAME||'"';
    sq_id VARCHAR2(13)  := regexp_substr(:v2,'^\w{13}$');
    flag  BOOLEAN       := FALSE;
    task  VARCHAR2(256) :='TUNE_MV_'||to_char(sysdate,'sssss');
    code  INT;
    err   VARCHAR2(3000);
    C     SYS_REFCURSOR;
    FUNCTION get_text(sq_id VARCHAR2,err BOOLEAN) RETURN CLOB IS
        txt CLOB;
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT SQL_FULLTEXT
            FROM   (SELECT SQL_FULLTEXT
                    FROM   gv$sqlarea
                    WHERE  SQL_ID = :sq_id
                    UNION ALL
                    SELECT SQL_TEXT
                    FROM   dba_hist_sqltext
                    WHERE  SQL_ID = :sq_id
                    UNION ALL
                    SELECT SQL_TEXT
                    FROM   dba_sqlset_statements
                    WHERE  SQL_ID = :sq_id)
            WHERE rownum < 2'
        INTO txt USING sq_id,sq_id,sq_id;
        RETURN txt;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            IF err THEN
                raise_application_error(-20001,'Cannot find SQL text of '||sq_id);
            ELSE
                RETURN NULL;
            END IF;
    END;
BEGIN
    IF SYS_CONTEXT('USERENV', 'CURRENT_USER') != own THEN
        flag := TRUE;
    END IF;

    IF sq_id IS NOT NULL THEN
        stmt := get_text(sq_id,&tune!=2);
    ELSIF stmt IS NULL AND &tune~=2 THEN
        raise_application_error(-20001,'Please input target SQL Text');
    ELSE
        stmt := REGEXP_REPLACE(stmt, '[;/]+\s*$');
    END IF;

    IF &tune=1 THEN
        IF :OBJECT_OWNER IS NULL THEN
            name := '"'||sys_context('userenv','current_schema')||'"."'||upper(src)||'"';
        END IF;
        stmt := 'CREATE MATERIALIZED VIEW '||name||' REFRESH FAST ENABLE QUERY REWRITE AS '|| stmt;
        --dbms_output.put_line(stmt);
        BEGIN DBMS_ADVISOR.DELETE_TASK(task); EXCEPTION WHEN OTHERS THEN NULL;END;
        BEGIN
            DBMS_ADVISOR.TUNE_MVIEW(task,stmt);
            OPEN C FOR replace(q'~
                SELECT SCRIPT_TYPE,REGEXP_REPLACE(STATEMENT,'  +',' ')||';' STATEMENT
                FROM   dba_tune_mview 
                WHERE  task_name = :task
                ORDER BY action_id~',
                'dba_',CASE WHEN flag THEN 'dba_' ELSE 'user_' END) 
            USING task;
            :create_script := DBMS_ADVISOR.GET_TASK_SCRIPT(task);
            :undo_script   := DBMS_ADVISOR.GET_TASK_SCRIPT(task,'UNDO');
            :script_suffix := lower(task);
            DBMS_ADVISOR.DELETE_TASK(task);
        EXCEPTION WHEN OTHERS THEN NULL;
            code := sqlcode;
            err  := sqlerrm||chr(10)||dbms_utility.format_error_backtrace;
            dbms_output.put_line(err);
            BEGIN DBMS_ADVISOR.DELETE_TASK(task); EXCEPTION WHEN OTHERS THEN NULL;END;
            IF flag AND sqlcode = -942 THEN
                raise_application_error(-20001,'ORA-00942: table or view does not exist possible due to CURRENT_USER is not '||own);
            ELSE
                raise_application_error(-20001,err);
            END IF;
        END;
    ELSIF &tune=2 THEN
        IF &check_access_rewrite=0 THEN
            raise_application_error(-20001,'Need execution access right on package SYS.DBMS_ADVANCED_REWRITE');
        ELSE
            EXECUTE IMMEDIATE q'~
                DECLARE
                    sq_id  VARCHAR2(32) := :src;
                    sq_txt CLOB         := :sq_txt;
                    sq_new CLOB         := trim(:sq_new);
                    own    VARCHAR2(99) := :own;
                    nam    VARCHAR2(99);
                    typ    VARCHAR2(30);
                    flag   BOOLEAN := false;
                BEGIN
                    SELECT max(owner),lower(max(rewrite_mode)),max(name)
                    INTO   own,typ,nam
                    FROM (
                        SELECT *
                        FROM   all_rewrite_equivalences
                        WHERE  name in ('SQL_'||sq_id,sq_id,upper(sq_id))
                        ORDER  BY decode(owner,own,1,user,2,3)
                    );
                    nam := '"'||nvl(own,sys_context('userenv','current_schema'))||'"."'||nvl(nam,sq_id)||'"';
                    IF typ IS NOT NULL THEN
                        IF '&mode'='drop' THEN
                            SYS.DBMS_ADVANCED_REWRITE.DROP_REWRITE_EQUIVALENCE(nam);
                            flag := true;
                        ELSIF '&mode'!=typ AND sq_new IS NULL THEN
                            SYS.DBMS_ADVANCED_REWRITE.ALTER_REWRITE_EQUIVALENCE(nam,'&mode');
                            flag := true;
                        ELSE
                            SYS.DBMS_ADVANCED_REWRITE.DROP_REWRITE_EQUIVALENCE(nam);
                        END IF;
                    END IF;

                    IF NOT flag AND sq_new IS NULL OR INSTR(sq_new,' ')=0 THEN
                        raise_application_error(-20001,'Please input target SQL Text');
                    END IF;

                    IF NOT flag THEN
                        SYS.DBMS_ADVANCED_REWRITE.DECLARE_REWRITE_EQUIVALENCE
                            (name             => nam,
                             source_stmt      => sq_txt,
                             destination_stmt => sq_new,
                             validate         => FALSE,
                             rewrite_mode     => '&mode'); --disabled,text_match,general,recursive,tune_mview
                    END IF;

                    OPEN :cur FOR 
                        SELECT  OWNER,REWRITE_MODE,NAME,REWRITE_MODE,
                                to_char(substr(trim(regexp_replace(SOURCE_STMT,'\s+',' ')),1,80))||CASE WHEN LENGTH(SOURCE_STMT)>80 THEN '...' END SOURCE_STMT,
                                to_char(substr(trim(regexp_replace(DESTINATION_STMT,'\s+',' ')),1,80))||CASE WHEN LENGTH(DESTINATION_STMT)>80 THEN '...' END DESTINATION_STMT
                        FROM   all_rewrite_equivalences
                        WHERE  name  in ('SQL_'||sq_id,sq_id,upper(sq_id));
                END;~' 
            USING src,get_text(lower(regexp_substr(src,'\w{13}$')),FALSE),stmt,own, IN OUT c;
        END IF;
    ELSE
        IF :OBJECT_OWNER IS NULL OR :OBJECT_TYPE!='MATERIALIZED VIEW' THEN
            raise_application_error(-20001,'Cannot find mview:'||src);
        END IF;
        
        BEGIN
            DBMS_MVIEW.EXPLAIN_REWRITE(mv => name, query => stmt, msg_array => msg);
        EXCEPTION WHEN OTHERS THEN 
            IF flag AND sqlcode = -942 THEN
                raise_application_error(-20001,'ORA-00942: table or view does not exist possible due to CURRENT_USER is not '||own);
            ELSE
                raise;
            END IF;
        END;
        IF msg.count > 0 AND MSG(1).QUERY_TEXT != MSG(1).REWRITTEN_TEXT THEN
            stmt := MSG(1).REWRITTEN_TEXT;
            OPEN :rw FOR
                SELECT stmt NEW_TEXT FROM DUAL;
        END IF;
        OPEN C FOR
            SELECT * FROM TABLE(MSG);
    END IF;
    :c := c;
END;
/


print rw
print c

save create_script ddl_&script_suffix..sql
save undo_script rollback_&script_suffix..sql