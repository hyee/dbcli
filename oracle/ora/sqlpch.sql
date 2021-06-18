/*[[Create SQL Patch on specify SQL ID. Usage: @@NAME <SQL Id> "<Hint Text>"
	--[[
	@ALIAS  : SQLPATCH
	@ARGS   : 2
    @CHECK_ACCESS_DBA: DBMS_SQLDIAG_INTERNAL={1} SYS.DBMS_SQLDIAG={0}
	]]--
]]*/
SET FEED OFF VERIFY OFF
VAR NAME VARCHAR2;
DECLARE
    sq_id     VARCHAR2(32767) := '&v1';
    hint_text VARCHAR2(32767) := q'!&v2!';
    sq_text   CLOB;
    NAME      VARCHAR2(128);
    to_schema VARCHAR2(128);
    curr      VARCHAR2(128)   := SYS_CONTEXT('USERENV','CURRENT_SCHEMA');
BEGIN
    BEGIN
        SELECT *
        INTO   to_schema, sq_text
        FROM   (SELECT parsing_schema_name, sql_fulltext
                FROM   gv$sqlarea
                WHERE  sql_id = sq_id
                AND    sql_fulltext IS NOT NULL
                AND    rownum < 2
                UNION ALL
                SELECT parsing_schema_name, sql_text
                FROM   dba_hist_sqlstat
                JOIN   dba_hist_sqltext
                USING  (sql_id,dbid)
                WHERE  sql_id = sq_id
                AND    rownum < 2
                UNION ALL
                SELECT username, TO_CLOB(sql_text)
                FROM   gv$sql_monitor
                WHERE  sql_id = sq_id
                AND    IS_FULL_SQLTEXT = 'Y'
                AND    sql_text IS NOT NULL
                AND    rownum < 2)
        WHERE  rownum < 2;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            raise_application_error(-20001, 'Cannot find the SQL text for sql_id: ' || sq_id);
    END;
    NAME := 'sqlpch_' || sq_id;
    BEGIN
        SYS.DBMS_SQLDIAG.DROP_SQL_PATCH(NAME,true);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    $IF DBMS_DB_VERSION.VERSION>11 $THEN
    hint_text := SYS.DBMS_SQLDIAG.CREATE_SQL_PATCH(sql_text    => sq_text,
                                                   hint_text   => hint_text,
                                                   NAME        => NAME,
                                                   category    => 'DEFAULT',
                                                   description => hint_text,
                                                   validate    => true);
    $ELSE
        $IF &CHECK_ACCESS_DBA=0 $THEN
            raise_application_error(-20001,'You must have the access to DBMS_SQLDIAG_INTERNAL.');
        $ELSE
            SYS.DBMS_SQLDIAG_INTERNAL.I_CREATE_PATCH(sql_text    => sq_text,
                                                     hint_text   => hint_text,
                                                     NAME        => NAME,
                                                     category    => 'DEFAULT',
                                                     description => hint_text,
                                                     validate    => true);
        $END
    $END
    --SYS.DBMS_SQLDIAG.ALTER_SQL_PATCH(name,'FORCE_MATCHING','YES');
    :name := name;
    EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA='||to_schema;
    BEGIN
        EXECUTE IMMEDIATE 'EXPLAIN PLAN FOR '||sq_text;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA='||curr;
        raise_application_error(-20001,'Unable to explain target SQL: '||sqlerrm);
    END;
    EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA='||curr;
END;
/
ORA PLAN X -OL

PRO SQL Patch "&name" is created.
PRO Please Use "ora flushsql &V1" to flush the target SQL.
PRO To rollback execute SYS.DBMS_SQLDIAG.DROP_SQL_PATCH('&name',true)