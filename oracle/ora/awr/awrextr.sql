/*[[Export AWR repository. Usage: @@NAME <directory_name> <begin_snap> <end_snap> [<dbid>]

    --[[
        @ARGS: 3
        &V4: default={&dbid}
        @extr: 18.1={dbms_workload_repository.extract} default={dbms_swrf_internal.awr_extract}
    --]]
]]*/
SET SQLTIMEOUT 7200

DECLARE
    dir  VARCHAR2(128) := :V1;
    file VARCHAR2(512);
    root VARCHAR2(512);
    dump BFILE;
    len  NUMBER;
    st   INT := :V2;
    ed   INT := :V3;
    did  INT := :V4;
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

    IF did IS NULL THEN
        SELECT MAX(dbid) INTO did FROM SYS.DBA_HIST_WR_CONTROL;
    END IF;

    SELECT MIN(snap_id), MAX(snap_id)
    INTO   st, ed
    FROM   DBA_HIST_SNAPSHOT
    JOIN   SYS.DBA_HIST_WR_CONTROL
    USING  (dbid)
    WHERE  dbid = did
    AND    snap_id IN (st, ed);

    IF st IS NULL OR ed IS NULL OR st = ed THEN
        raise_application_error(-20001, 'Invalid snapshot range(' || :v2 || '-' || :v3 || ') for dbid ' || did);
    END IF;

    file := 'awrdat_' || did || '_' || st || '_' || ed;
    
    dump := bfilename(dir, file||'.dmp');
    BEGIN 
        dbms_lob.fileopen(dump);
        len := dbms_lob.getlength(dump);
        dbms_lob.fileclose(dump);
    EXCEPTION WHEN OTHERS THEN NULL; END;
    
    IF len > 0 THEN
        raise_application_error(-20001, 'File already exists: ' || root || file || '.dmp');
    END IF;


    sys. &extr(dmpfile => file, dmpdir => dir, dbid => did, bid => st, eid => ed);
    dbms_output.put_line('AWR repository is extracted into ' || root || file || '.dmp');
END;
/