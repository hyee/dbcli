/*[[Explain query rewrite on target materialized view. Usage: @@NAME <mview_name> <sql>

    --[[
        @ARGS: 2
    --]]
]]*/
findobj "&V1" "" 1
COL QUERY_TEXT,REWRITTEN_TEXT,MV_OWNER,MV_NAME NOPRINT
SET COLWRAP 100 AUTOHIDE COL
set feed off verify off
COL QUERY_BLOCK_NO HEAD QB#
COL SEQUENCE HEAD #
col ORIGINAL_COST,REWRITTEN_COST FOR K5
VAR C REFCURSOR  "EXPLAIN REWRITE MSGS"
VAR rw REFCURSOR "REWRITTEN TEXT";
DECLARE
    MSG  SYS.REWRITEARRAYTYPE := SYS.REWRITEARRAYTYPE();
    STMT CLOB := :V2;
    name VARCHAR2(128):='"'||:OBJECT_OWNER||'"."'||:OBJECT_NAME||'"';
    flag BOOLEAN := FALSE;
BEGIN
    IF SYS_CONTEXT('USERENV', 'CURRENT_USER') != :OBJECT_OWNER THEN
        flag := TRUE;
    END IF;

    STMT := REGEXP_REPLACE(STMT, '[;/]+\s*$');
    BEGIN
        DBMS_MVIEW.EXPLAIN_REWRITE(mv => name, query => STMT, msg_array => msg);
    EXCEPTION WHEN OTHERS THEN 
        IF flag AND sqlcode = -942 THEN
            raise_application_error(-20001,'ORA-00942: table or view does not exist possible due to CURRENT_USER is not '||:OBJECT_OWNER);
        ELSE
            raise;
        END IF;
    END;
    IF msg.count > 0 AND MSG(1).QUERY_TEXT != MSG(1).REWRITTEN_TEXT THEN
        stmt := MSG(1).REWRITTEN_TEXT;
        OPEN :rw FOR
            SELECT STMT NEW_TEXT FROM DUAL;
    END IF;
    OPEN :C FOR
        SELECT * FROM TABLE(MSG);
END;
/

print rw

print c