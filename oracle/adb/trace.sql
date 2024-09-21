/*[[
    Turn SQL Trace on,execute SQL, then turn trace off. Usage: @@NAME <SQL script>
    SQL script support EOF input, for example: @@NAME <<!...
    DEFAULT_CREDENTIAL/DEFAULT_LOGGING_BUCKET must be defined to use the SQL Trace feature in Autonomous Database (view database_properties)
    --[[
        @ARGS: 1
    --]]
]]*/
SET FEED OFF VERIFY OFF
VAR ctx CLOB;
DECLARE
    c INT;
    bucket VARCHAR2(1000);
    ctx CLOB:=:V1;
BEGIN
    SELECT COUNT(1),
           MAX(decode(property_name,'DEFAULT_LOGGING_BUCKET',property_value))
    INTO   c,bucket
    FROM   DATABASE_PROPERTIES
    WHERE  property_name IN('DEFAULT_CREDENTIAL','DEFAULT_LOGGING_BUCKET')
    AND    trim(property_value) IS NOT NULL;

    IF c<2 THEN
        raise_application_error(-20001,'DEFAULT_CREDENTIAL/DEFAULT_LOGGING_BUCKET is not defined by "ALTER DATABASE PROPERTY SET" command.'); 
    END IF;
    c := ROUND(DBMS_RANDOM.VALUE(1,1E6));
    DBMS_SESSION.SET_IDENTIFIER('dbcli');
    dbms_application_info.set_module(c,'');
    dbms_output.put_line('Trace file will be created under '||trim('/' from bucket)||'/sqltrace/dbcli/'||c);
    ctx := regexp_replace(ctx,'[[:space:][:cntrl:]]+$');
    IF not regexp_like(substr(ctx,-64),'end;') then
        IF substr(ctx,-1)!=';' then
            ctx := ctx ||';';
        END IF;
    ELSE
        ctx := ctx || chr(10)||'/';
    END IF;
    :ctx := ctx;
END;
/

set internal on ONERREXIT OFF
ALTER SESSION SET SQL_TRACE=TRUE;
&ctx
ALTER SESSION SET SQL_TRACE=FALSE;
set internal off ONERREXIT On

VAR nam VARCHAR2(128)
VAR ctx CLOB;
DECLARE
    ctx     CLOB;
    c       PLS_INTEGER := 0;
    piece   VARCHAR2(32767);
    isbreak BOOLEAN := FALSE;
    pattern VARCHAR2(100) := '^[[:space:][:cntrl:]]*(.*?)\s*$';
    @lz_compress@
BEGIN
    DBMS_SESSION.SET_IDENTIFIER('');
    dbms_lob.createtemporary(ctx, TRUE);
    FOR r IN (SELECT trace FROM SESSION_CLOUD_TRACE ORDER BY row_number) LOOP
        --handle unexpected line breaks in the view
        piece := regexp_replace(r.trace, pattern, '\1');
        IF substr(piece, 1, 6) = 'STAT #' AND substr(piece, -1) != '''' THEN
            IF isbreak THEN
                piece := chr(10) || piece;
            END IF;
            isbreak := TRUE;
        ELSIF isbreak THEN
            IF piece IS NULL OR instr(substr(piece, 1, 32), ' #') > 0 OR instr(substr(piece, 1, 32), '===') > 0 THEN
                isbreak := FALSE;
                piece   := chr(10) || piece || chr(10);
            ELSIF substr(piece, -1) = '''' THEN
                isbreak := FALSE;
                piece   := piece || chr(10);
            END IF;
        ELSE
            piece := piece || chr(10);
        END IF;
        dbms_lob.writeappend(ctx, length(piece), piece);
        c := c + lengthb(piece);
        EXIT WHEN c > 32 * 1024 * 1024;
    END LOOP;
    base64encode(ctx, NULL, TRUE);
    SELECT regexp_substr(value, '[^/]+$') INTO :nam FROM v$diag_info WHERE NAME = 'Default Trace File';
    :ctx := ctx;
END;
/

PRO Trace can be directly viewed at SESSION_CLOUD_TRACE. You may need to reconnect for using new trace file identifier.
SAVE ctx nam