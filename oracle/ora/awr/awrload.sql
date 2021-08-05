/*[[Import AWR repository dump. Usage: @@NAME <directory_name> <file_name> [<new_dbid>]
    --[[
        @ARGS: 2
    --]]
]]*/
SET SQLTIMEOUT 7200

DECLARE
    dir   VARCHAR2(128) := :V1;
    file  VARCHAR2(512) := :V2;
    did   INT := :V3;
    root  VARCHAR2(512);
    dump  BFILE;
    len   NUMBER;
    stage VARCHAR2(30) := 'DBCLI_AWR';
BEGIN
    SELECT MAX(directory_name), MAX(directory_path)
    INTO   dir, root
    FROM   ALL_DIRECTORIES
    WHERE  upper(directory_name) = upper(dir);
    IF dir IS NULL THEN
        raise_application_error(-20001, 'Cannot access directory: ' || :V1);
    END IF;

    IF NOT regexp_like(root, '[\\/]$') THEN
        root := root || CASE WHEN root LIKE '%/%' THEN '/' ELSE '\' END;
    END IF;

    dump := bfilename(dir, file||'.dmp');
    BEGIN 
        dbms_lob.fileopen(dump);
        len := dbms_lob.getlength(dump);
        dbms_lob.fileclose(dump);
    EXCEPTION WHEN OTHERS THEN 
        raise_application_error(-20001, 'Cannot access file: ' || root || file || '.dmp');
    END;

    $IF DBMS_DB_VERSION.VERSION>18 $THEN
        sys.dbms_workload_repository.awr_imp(dmpfile => file, dmpdir => dir, new_dbid => did);
    $ELSE
        BEGIN
            stage := CASE sys_context('userenv', 'con_name') WHEN 'CDB$ROOT' THEN 'C##' END || stage;
        EXCEPTION WHEN OTHERS NULL;
        END;
        $IF DBMS_DB_VERSION.VERSION>17 $THEN
            sys.dbms_workload_repository.load(schname => stage, dmpfile => file, dmpdir => dir, new_dbid => did);
        $ELSE
            dbms_swrf_internal.awr_load(schname  => stage,dmpfile  => file, dmpdir => dir);
            dbms_swrf_internal.move_to_awr(schname  => stage, new_dbid => did);
            dbms_swrf_internal.clear_awr_dbid;
        $END
    $END
    dbms_output.put_line('AWR repository is imported from ' || root || file || '.dmp');
END;
/