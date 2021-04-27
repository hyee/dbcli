/*[[Flush a SQL from out of shared pool, you can also rebuild related index to accomplish the same purpose. Usage: @@NAME <sql_id>
    --[[
        @version: 12.1={1} 11.1={0} 10.2.0.4={} 
        @ARGS: 1
        @CHECK_ACCESS_DIAG: SYS.DBMS_SQLDIAG_INTERNAL={1} DEFAULT={&version}
    ]]--
]]*/
SET FEED OFF
DECLARE
    NAME    VARCHAR2(128);
    version VARCHAR2(3);
    sq_id   VARCHAR2(128) := :V1;
    sq_text CLOB;
    cnt     PLS_INTEGER;
BEGIN
    SELECT regexp_replace(version, '\..*') INTO version FROM v$instance;
    BEGIN
        SELECT address || ',' || hash_value,sql_fulltext
        INTO   name,sq_text
        FROM   v$sqlarea 
        WHERE  sql_id = sq_id 
        AND    rownum<2;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN 
            dbms_output.put_line('SQL not foud: '||sq_id);
            return;
    END;

    IF version + 0 = 10 THEN
        EXECUTE IMMEDIATE q'[alter session set events '5614566 trace name context forever']'; -- bug fix for 10.2.0.4 backport
    END IF;
    sys.dbms_shared_pool.unkeep(name, flag => 'C');
    sys.dbms_shared_pool.purge(name, 'C',64);
    sys.dbms_shared_pool.purge(name, 'C');
    IF version + 0 = 10 THEN
        EXECUTE IMMEDIATE q'[alter session set events '5614566 trace name context off']';
        RETURN;
    END IF;

    dbms_output.put_line('Purging SQL: '||sq_id);

    SELECT COUNT(1) INTO   cnt
    FROM   v$sql
    WHERE  sql_id = sq_id;
    IF cnt >0 THEN
        NULL;
        -- create fake sql patch to invalidate the cursors
        dbms_output.put_line('Creating/dropping fake SQL Patch: '||sq_id);
        $IF DBMS_DB_VERSION.VERSION=11 AND &CHECK_ACCESS_DIAG=1 $THEN
            SYS.DBMS_SQLDIAG_INTERNAL.I_CREATE_PATCH (
                 sql_text => sq_text,
                 hint_text => 'NULL',
                 name => 'purge_'||sq_id,
                 description => 'PURGE CURSOR',
                 category => 'DEFAULT',
                 validate => TRUE);
        $END

        $IF DBMS_DB_VERSION.VERSION>12 OR DBMS_DB_VERSION.VERSION=12 AND DBMS_DB_VERSION.RELEASE>1 $THEN
            name:=DBMS_SQLDIAG.CREATE_SQL_PATCH (
                     sql_text => sq_text,
                     hint_text => 'NULL',
                     name => 'purge_'||sq_id,
                     description => 'PURGE CURSOR',
                     category => 'DEFAULT',
                     validate => TRUE);
        $END

        $IF DBMS_DB_VERSION.VERSION>10 AND &CHECK_ACCESS_DIAG=1 $THEN
            SYS.DBMS_SQLDIAG.DROP_SQL_PATCH (
                 name   => 'purge_'||sq_id, 
                 ignore => TRUE);
        $END
    END IF;
END;
/