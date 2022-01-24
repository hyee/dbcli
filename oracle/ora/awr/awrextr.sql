/*[[Export AWR repository. Usage: @@NAME <directory_name> <begin_snap|YYMMDDHH24MI> <end_snap|YYMMDDHH24MI> [<dbid>] [-sqlmon|-awr]
    -sqlmon: extract sql monitor reports only
    -awr   : extract awr dump only
    --[[
        @ARGS: 3
        &V4: default={&dbid}
        @check_access_sqlmon: DBA_HIST_REPORTS_DETAILS={1} default={0}
        &awr: default={0} awr={1} sqlmon={2}
    --]]
]]*/
SET SQLTIMEOUT 86400

DECLARE
    dir  VARCHAR2(128) := :V1;
    file VARCHAR2(512);
    root VARCHAR2(512);
    expr VARCHAR2(512);
    dump BFILE;
    len  NUMBER;
    std  DATE;
    edd  DATE;
    st   INT := :V2;
    ed   INT := :V3;
    did  INT := :V4;
    hdl  NUMBER;
    res  CLOB;
    job  VARCHAR2(128) := 'AWREXTR_'||to_char(SYSDATE,'YYMMDDHH24MISS');
    own  VARCHAR2(128);
    val  VARCHAR2(30);
BEGIN
    dbms_output.enable(null);
    SELECT MAX(directory_name), MAX(directory_path)
    INTO   dir, root
    FROM   ALL_DIRECTORIES
    WHERE  upper(directory_name) = upper(dir);
    IF dir IS NULL THEN
        raise_application_error(-20001, 'Cannot access directory: ' || :V1);
    END IF;

    $IF dbms_db_version.version>17 $THEN
        IF dbms_utility.directory_has_symlink(dir)=1 THEN
            raise_application_error(-20001, 'Directory('||root||') has symbolic link, please change to the real path.');
        END IF;
    $END

    dbms_output.put_line('Export path: '||root);

    IF NOT regexp_like(root, '[\\/]$') THEN
        root := root || CASE WHEN root LIKE '%/%' THEN '/' ELSE '\' END;
    END IF;

    IF did IS NULL THEN
        SELECT MAX(dbid) INTO did FROM V$DATABASE;
        $IF DBMS_DB_VERSION.VERSION>11 $THEN
            did := sys_context('userenv', 'con_dbid');
        $END
    END IF;
    BEGIN
        std := to_date(st,'YYMMDDHH24MI');
        edd := to_date(ed,'YYMMDDHH24MI');
    EXCEPTION WHEN OTHERS THEN NULL;END;
    
    IF &awr IN(0,1) THEN
        SELECT MIN(snap_id), MAX(snap_id)
        INTO   st, ed
        FROM   SYS.DBA_HIST_SNAPSHOT
        JOIN   SYS.DBA_HIST_WR_CONTROL
        USING  (dbid)
        WHERE  dbid = did
        AND    (edd IS NOT NULL OR snap_id IN (st, ed))
        AND    (edd IS NULL OR end_interval_time+0 between std and edd);

        IF st IS NULL OR ed IS NULL OR st = ed THEN
            $IF DBMS_DB_VERSION.VERSION>11 $THEN
                IF sys_context('userenv', 'con_id')>1 AND did=sys_context('userenv', 'con_dbid') THEN
                    SELECT UPPER(NVL(MAX(value),'FALSE')) 
                    INTO   val
                    FROM   v$parameter
                    WHERE  name='awr_pdb_autoflush_enabled';
                    
                    IF VAL!='TRUE' THEN
                        raise_application_error(-20001, 'No such snapshots, please make sure parameter awr_pdb_autoflush_enabled=true to enable AWR PDB level flushing, or connect to container CDB$ROOT.');
                    END IF;
                END IF;
            $END
            raise_application_error(-20001, 'Invalid snapshot range(' || :v2 || '-' || :v3 || ') for dbid ' || did);
        END IF;

        file := 'awrdat_' || did || '_' || st || '_' || ed;
        
        dump := bfilename(dir, file||'.dmp');
        BEGIN 
            sys.dbms_lob.fileopen(dump);
            len := dbms_lob.getlength(dump);
            sys.dbms_lob.fileclose(dump);
        EXCEPTION WHEN OTHERS THEN NULL; END;
        
        IF len > 0 THEN
            raise_application_error(-20001, 'File already exists: ' || root || file || '.dmp');
        END IF;
        BEGIN
        $IF DBMS_DB_VERSION.VERSION>17 $THEN
            sys.dbms_workload_repository.extract(dmpfile => file, dmpdir => dir, dbid => did, bid => st, eid => ed);
        $ELSE
            sys.dbms_swrf_internal.awr_extract(dmpfile => file, dmpdir => dir, dbid => did, bid => st, eid => ed);
        $END
        EXCEPTION WHEN OTHERS THEN
            IF sqlcode not in(-31623) THEN
                raise;
            END IF;
        END;
        dbms_output.put_line('AWR repository is extracted into ' || root || file || '.dmp');
    END IF;
    $IF &check_access_sqlmon=1 AND (&awr=0 OR &awr=2) $THEN
    BEGIN
        own := regexp_replace(sys_context('userenv','current_schema'),'^SYS$','SYSTEM');
        expr:='WHERE '||did||' IN (CON_DBID,DBID) AND ';
        IF edd IS NULL THEN
            expr := expr || 'SNAP_ID BETWEEN '||st||' AND '||ed;
        ELSE
            expr := expr || 'GENERATION_TIME BETWEEN TO_DATE('''||st||''',''YYMMDDHH24MI'') AND TO_DATE('''||ed||''',''YYMMDDHH24MI'')';
        END IF;

        BEGIN
            EXECUTE IMMEDIATE 'CREATE TABLE '||own||'.AWR_DUMP_REPORTS AS SELECT * FROM SYS.CDB_HIST_REPORTS '||expr;
            EXECUTE IMMEDIATE 'CREATE TABLE '||own||'.AWR_DUMP_REPORTS_DETAILS AS SELECT * FROM SYS.CDB_HIST_REPORTS_DETAILS '||expr;
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE!=-955 THEN
                RAISE;
            END IF;
        END;

        BEGIN
            hdl := sys.dbms_datapump.attach(job, sys_context('userenv', 'current_schema'));
            sys.dbms_datapump.stop_job(hdl, 1, 0, 10);
            sys.dbms_datapump.detach(job);
        EXCEPTION WHEN OTHERS THEN END;
        hdl := null;
        BEGIN
            hdl := sys.dbms_datapump.open(operation   => 'EXPORT',
                                          job_mode    => 'TABLE',
                                          job_name    => job,
                                          version     => '12');
            file := 'sqlmon_'||did||'_'||st||'_'||ed||'_'||lower(own)||'.dmp';
            sys.dbms_datapump.add_file(handle    => hdl,
                                       filetype  => sys.dbms_datapump.KU$_FILE_TYPE_DUMP_FILE,
                                       filename  => file,
                                       directory => dir,
                                       reusefile => 1);
            sys.dbms_datapump.add_file(handle    => hdl,
                                       filetype  => sys.dbms_datapump.KU$_FILE_TYPE_LOG_FILE,
                                       filename  => replace(file,'.dmp','.log'),
                                       directory => dir,
                                       reusefile => 1);
            sys.dbms_datapump.metadata_filter(handle => hdl,
                                              name   => 'NAME_LIST',
                                              value  => '''AWR_DUMP_REPORTS'',''AWR_DUMP_REPORTS_DETAILS''');
            sys.dbms_datapump.metadata_filter(handle => hdl,
                                              name   => 'SCHEMA_EXPR',
                                              value  => '='''||own||'''');
            sys.dbms_datapump.set_parameter(handle => hdl, name => 'COMPRESSION', value => 'ALL');
            sys.dbms_datapump.start_job(hdl);
            sys.dbms_datapump.wait_for_job(hdl, res);
            dbms_output.put_line('SQL Monitor reports are extracted into ' || root || file);
        EXCEPTION WHEN OTHERS THEN
            IF hdl IS NOT NULL THEN
                BEGIN
                    sys.dbms_datapump.stop_job(hdl, 1, 0, 0);
                    sys.dbms_datapump.detach(hdl);
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END IF;
            BEGIN
                EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS PURGE';
                EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS_DETAILS PURGE';
            EXCEPTION WHEN OTHERS THEN NULL; END;
            raise;
        END;
        BEGIN
            EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS PURGE';
            EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS_DETAILS PURGE';
        EXCEPTION WHEN OTHERS THEN NULL; END;
    END;
    $END
END;
/