/*[[explain/gather/execute SQL. Usage: @@NAME [-exec|-gather] {<sql_id> [<parsing_schema>|<child_number>]} | <sql_text>
    --[[
        @ARGS: 1
        &opt: default={2} exec={1} gather={8} obj={4} diag={66}
    --]]
]]*/
set verify off feed off
var plan_id NUMBER;
var sql_id VARCHAR2(30);
var cur REFCURSOR;
col ela for usmhd2
col cpu for pct2
col buff,reads,dxwrites,rows# for tmb2

DECLARE
    cur     SYS_REFCURSOR;
    own     VARCHAR2(128):=regexp_substr(:v2,'^\S+$');
    sq_text CLOB:=trim(:V1);
    sq_id   VARCHAR2(20):= regexp_substr(sq_text,'^\S{10,20}$');
    sig     INT;
    stmt    SYS.SQLSET_ROW;
    bw      RAW(2000);
    err     VARCHAR2(32767);
    $IF DBMS_DB_VERSION.VERSION>12 $THEN
        PROCEDURE I_PROCESS_SQL_CALLOUT(
            STMT         IN OUT SQLSET_ROW,
            EXEC_USERID  IN PLS_INTEGER:=sys_context('USERENV','CURRENT_USERID'),
            ACTION       IN BINARY_INTEGER,
            TIME_LIMIT   IN POSITIVE,
            CTRL_OPTIONS IN XMLTYPE:=null,
            EXTRA_RESULT OUT CLOB,
            ERR_CODE     OUT BINARY_INTEGER,
            ERR_MESG     OUT VARCHAR2) IS
            EXTERNAL NAME "kestsProcessSqlCallout"
            WITH CONTEXT
            PARAMETERS(CONTEXT     ,
                       STMT        ,
                       STMT         INDICATOR STRUCT,
                       STMT         DURATION OCIDURATION,
                       EXEC_USERID  UB4,
                       ACTION       UB4,
                       TIME_LIMIT   UB4,
                       CTRL_OPTIONS,
                       CTRL_OPTIONS INDICATOR SB2,
                       EXTRA_RESULT OCILOBLOCATOR,
                       EXTRA_RESULT INDICATOR SB2,
                       ERR_CODE     SB4,
                       ERR_CODE     INDICATOR SB2,
                       ERR_MESG     OCISTRING,
                       ERR_MESG     INDICATOR SB2)
            LIBRARY SYS.DBMS_SQLTUNE_LIB;
    $ELSE
        PROCEDURE I_PROCESS_SQL_CALLOUT(
            STMT         IN OUT SQLSET_ROW, 
            ACTION       IN     BINARY_INTEGER, 
            TIME_LIMIT   IN     POSITIVE,
            CTRL_OPTIONS IN     XMLTYPE:=NULL,
            EXTRA_RESULT OUT    CLOB,
            ERR_CODE     OUT    BINARY_INTEGER,
            ERR_MESG     OUT    VARCHAR2)
          IS EXTERNAL NAME "kestsProcessSqlCallout" 
          WITH CONTEXT
          PARAMETERS (CONTEXT, 
                      STMT, STMT INDICATOR STRUCT, STMT DURATION OCIDURATION,
                      ACTION UB4,
                      TIME_LIMIT UB4, 
                      CTRL_OPTIONS, CTRL_OPTIONS INDICATOR SB2, 
                      EXTRA_RESULT OCILOBLOCATOR, EXTRA_RESULT INDICATOR SB2,
                      ERR_CODE SB4, ERR_CODE INDICATOR SB2,
                      ERR_MESG OCISTRING, ERR_MESG INDICATOR SB2)
          LIBRARY SYS.DBMS_SQLTUNE_LIB;   
    $END
BEGIN
    IF sq_id IS NOT NULL THEN
    BEGIN
        SELECT nvl(regexp_replace(own,'^\d+$'),nam),txt,sig,br
        INTO own,sq_text,sig,bw
        FROM (
            SELECT parsing_schema_name nam, sql_fulltext txt,force_matching_signature sig,bind_data br
            FROM   gv$sql a
            WHERE  sql_id = sq_id
            AND    child_number=nvl(0+regexp_substr(own,'^\d+$'),child_number)
            AND    rownum < 2
            UNION ALL
            SELECT parsing_schema_name, sql_text,force_matching_signature sig,bind_data
            FROM   dba_sqlset_statements a
            WHERE  sql_id = sq_id
            AND    rownum < 2
            UNION ALL
            SELECT parsing_schema_name, sql_text,force_matching_signature sig,bind_data
            FROM   dba_hist_sqltext
            JOIN   (SELECT *
                    FROM   (SELECT dbid, sql_id, parsing_schema_name,force_matching_signature,bind_data
                            FROM   dba_hist_sqlstat
                            WHERE  sql_id = sq_id
                            ORDER  BY decode(dbid, sys_context('userenv', 'dbid'), 1, 2), snap_id DESC)
                    WHERE  rownum < 2)
            USING  (dbid, sql_id)
            WHERE  sql_id = sql_id
        ) WHERE ROWNUM<2;
    EXCEPTION WHEN OTHERS THEN
        raise_application_error(-20001,'Cannot find SQL Text for SQL Id: '||sq_id);
    END;
    ELSE
        IF sq_text LIKE '%/' THEN
            sq_text := trim(trim('/' from sq_text));
        ELSIF sq_text LIKE '%;' AND UPPER(sq_text) NOT LIKE '%END;' THEN
            sq_text := trim(trim(';' from sq_text));
        END IF;
        sq_id  := SYS.dbms_sqltune_util0.sqltext_to_sqlid(sq_text);
        sig    := SYS.dbms_sqltune_util0.sqltext_to_signature(sq_text,1);
        own    := nvl(regexp_replace(own,'^\d+$'),sys_context('userenv','current_schema'));
    END IF;

    stmt := SYS.SQLSET_ROW(sq_id,sig,sq_text,null,bw,own);

    I_PROCESS_SQL_CALLOUT(stmt=>stmt,action=>&opt,time_limit=>86400,extra_result=>sq_text,err_code=>sig,err_mesg=>err);

    IF err IS NOT NULL THEN
        raise_application_error(-20001,err);
    END IF;

    IF stmt.sql_plan is not null and stmt.sql_plan.count>0 THEN
        SELECT nvl(max(PLAN_ID),COUNT(1))
        INTO   sig
        FROM   TABLE(stmt.sql_plan);

        DELETE PLAN_TABLE
        WHERE  PLAN_ID=sig
        OR     STATEMENT_ID='INTERNAL_DBCLI_CMD';

        INSERT INTO PLAN_TABLE
            (STATEMENT_ID,
             PLAN_ID,
             TIMESTAMP,
             REMARKS,
             OPERATION,
             OPTIONS,
             OBJECT_NODE,
             OBJECT_OWNER,
             OBJECT_NAME,
             OBJECT_ALIAS,
             OBJECT_INSTANCE,
             OBJECT_TYPE,
             OPTIMIZER,
             SEARCH_COLUMNS,
             ID,
             PARENT_ID,
             DEPTH,
             POSITION,
             COST,
             CARDINALITY,
             BYTES,
             OTHER_TAG,
             PARTITION_START,
             PARTITION_STOP,
             PARTITION_ID,
             DISTRIBUTION,
             CPU_COST,
             IO_COST,
             TEMP_SPACE,
             ACCESS_PREDICATES,
             FILTER_PREDICATES,
             PROJECTION,
             TIME,
             QBLOCK_NAME,
             OTHER_XML)
        SELECT 'INTERNAL_DBCLI_CMD',
               SIG,
               TIMESTAMP,
               REMARKS,
               OPERATION,
               OPTIONS,
               OBJECT_NODE,
               OBJECT_OWNER,
               OBJECT_NAME,
               OBJECT_ALIAS,
               OBJECT_INSTANCE,
               OBJECT_TYPE,
               OPTIMIZER,
               SEARCH_COLUMNS,
               ID,
               PARENT_ID,
               DEPTH,
               POSITION,
               COST,
               CARDINALITY,
               BYTES,
               OTHER_TAG,
               PARTITION_START,
               PARTITION_STOP,
               PARTITION_ID,
               DISTRIBUTION,
               CPU_COST,
               IO_COST,
               TEMP_SPACE,
               ACCESS_PREDICATES,
               FILTER_PREDICATES,
               PROJECTION,
               TIME,
               QBLOCK_NAME,
               OTHER_XML
        FROM   TABLE(stmt.sql_plan);
    ELSE 
        sig := -1;
    END IF;

    IF stmt.elapsed_time>0 THEN
        OPEN cur FOR
            SELECT stmt.sql_id,
                   stmt.force_matching_signature force_signature,
                   stmt.executions execs,
                   stmt.fetches,
                   stmt.elapsed_time ela,
                   round(stmt.cpu_time/stmt.elapsed_time,4) cpu,
                   stmt.buffer_gets buff,
                   stmt.disk_reads reads,
                   stmt.direct_writes dxwrites,
                   stmt.rows_processed "rows#"
            from dual;
    END IF;
    :plan_id := sig;
    :sql_id  := '-'||sq_id;
    :cur     := cur;
END;
/

xplan &sql_id &plan_id

print cur
