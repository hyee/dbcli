/*[[
    Tune or explain query rewrite on target materialized view. Usage: @@NAME {[-tune|-xplan] <mview_name> | -rewrite <sql_id>} <select statement>
    -xplan   : default,execute DBMS_MVIEW.EXPLAIN_REWRITE for target SQL with existing MVIEW
    -tune    : execute DBMS_ADVISOR.TUNE_MVIEW to generate the DDLs for relative MVIEW and MVIEW logs.
    -rewrite : execute DBMS_ADVANCED_REWRITE.DECLARE_REWRITE_EQUIVALENCE to rewrite target SQL ID as the query.
               needs to set QUERY_REWRITE_INTEGRITY = TRUSTED
               if <select> is a SQL Id then auto get SQL text
               if <select> is NULL then drop existing rewrites
    <select> : support EOF syntax
    --[[
        @ARGS: 2
        &tune: xplan={0} tune={1} rewrite={2}
        &wrap: xplan={100} tune={180}
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
    MSG  SYS.REWRITEARRAYTYPE := SYS.REWRITEARRAYTYPE();
    stmt CLOB := :V2;
    own  VARCHAR2(128):=nvl(:OBJECT_OWNER,SYS_CONTEXT('USERENV','CURRENT_SCHEMA'));
    src  VARCHAR2(256):=:v1;
    name VARCHAR2(256):='"'||:OBJECT_OWNER||'"."'||:OBJECT_NAME||'"';
    flag BOOLEAN := FALSE;
    task VARCHAR2(256):='TUNE_MV_'||to_char(sysdate,'sssss');
    code INT;
    err  VARCHAR2(3000);
    C    SYS_REFCURSOR;
BEGIN
    IF SYS_CONTEXT('USERENV', 'CURRENT_USER') != own THEN
        flag := TRUE;
    END IF;
    stmt := REGEXP_REPLACE(stmt, '[;/]+\s*$');
    IF &tune=1 THEN
        IF :OBJECT_OWNER IS NULL THEN
            name := '"'||sys_context('userenv','current_schema')||'"."'||upper(src)||'"';
        END IF;
        stmt := 'CREATE MATERIALIZED VIEW '||name||' REFRESH FAST ENABLE QUERY REWRITE AS '|| stmt;
        --dbms_output.put_line(stmt);
        BEGIN DBMS_ADVISOR.DELETE_TASK (task); EXCEPTION WHEN OTHERS THEN NULL;END;
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
        $IF &check_access_rewrite=0 $THEN
            raise_application_error(-20001,'Need execution access right on package SYS.DBMS_ADVANCED_REWRITE');
        $ELSE
            EXECUTE IMMEDIATE q'~
                DECLARE
                    sq_id  VARCHAR2(32) := :src;
                    sq_new CLOB         := TRIM(:sq_new);
                    sq_txt CLOB;
                    id_new VARCHAR2(13) := regexp_substr(sq_new,'^.{13}$');
                    FUNCTION get_text(sq_id VARCHAR2) RETURN CLOB IS
                        txt CLOB;
                    BEGIN
                        SELECT SQL_FULLTEXT
                        INTO   txt
                        FROM   (SELECT SQL_FULLTEXT
                                FROM   gv$sqlarea
                                WHERE  SQL_ID = sq_id
                                UNION ALL
                                SELECT SQL_TEXT
                                FROM   dba_hist_sqltext
                                WHERE  SQL_ID = sq_id
                                UNION ALL
                                SELECT SQL_TEXT
                                FROM   dba_sqlset_statements
                                WHERE  SQL_ID = sq_id)
                        WHERE rownum < 2;
                        RETURN txt;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            raise_application_error(-20001,'Cannot find SQL text of '||sq_id);
                    END;
                BEGIN
                    BEGIN SYS.DBMS_ADVANCED_REWRITE.DROP_REWRITE_EQUIVALENCE(sq_id);EXCEPTION WHEN OTHERS THEN NULL;END;
                    BEGIN SYS.DBMS_ADVANCED_REWRITE.DROP_REWRITE_EQUIVALENCE('SQL_'||sq_id);EXCEPTION WHEN OTHERS THEN NULL;END;
                    IF id_new IS NOT NULL THEN
                        sq_new := get_text(id_new);
                    ELSIF sq_new IS NULL OR INSTR(sq_new,' ')=0 THEN 
                        RETURN; 
                    END IF;
                    sq_txt := get_text(sq_id);
                    SYS.DBMS_ADVANCED_REWRITE.DECLARE_REWRITE_EQUIVALENCE
                        (name             => 'SQL_'||sq_id,
                         source_stmt      => sq_txt,
                         destination_stmt => sq_new,
                         validate         => FALSE,
                         rewrite_mode     => 'general'); --disabled,text_match,general,recursive
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        raise_application_error(-20001,'Cannot find SQL text of '||sq_id);
                    WHEN OTHERS THEN
                        RAISE;
                END;~' USING src,stmt;
            OPEN C FOR q'~
                SELECT  OWNER,REWRITE_MODE,NAME,REWRITE_MODE,
                        to_char(substr(trim(regexp_replace(SOURCE_STMT,'\s+',' ')),1,80))||CASE WHEN LENGTH(SOURCE_STMT)>80 THEN '...' END SOURCE_STMT,
                        to_char(substr(trim(regexp_replace(DESTINATION_STMT,'\s+',' ')),1,80))||CASE WHEN LENGTH(DESTINATION_STMT)>80 THEN '...' END DESTINATION_STMT
                FROM   all_rewrite_equivalences 
                WHERE  name = upper(:task)~'
            USING 'SQL_'||src;
        $END
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