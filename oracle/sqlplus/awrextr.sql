/*  Export AWR repository or SQL Monitor reports into DATA PUMP.
    For db version lower than 12c, the script requires SYSDBA privilege; for 12.1 onwards, requires DBA priviledge.
    
    Usage: @awrextr <directory_name> <begin_snap> <end_snap> [awr|sqlmon|both] [<dbid>]
    * directory_name: the directory name that can be found in all_directories, current schema must has the write access, and the path must not be symbolic link
    * begin_snap    : begin snap_id of dba_hist_snapshot, or in "YYMMDD[HH24[MI]]" format
    * end_snap      : end   snap_id of dba_hist_snapshot, or in "YYMMDD[HH24[MI]]" format
    * dbid          : optional, the target dbid to be exported
    * export data   : optional, the data to be exported
        1) awr   : only export the AWR dump, this is the default option
        2) sqlmon: only export the SQL Monitor reports in dba_hist_reports, be noted that this option with temporarily create 2 tables for exporting
        3) both  : export either AWR dump and SQL Monitor reports

    Examples:
        1) @awrextr awrdump_dir 210101     210203      (export via date range)
        2) @awrextr awrdump_dir 21010120   21020320    (export via time range)
        3) @awrextr awrdump_dir 2101012030 2102032030  (export via time range)
        4) @awrextr awrdump_dir 1234 1236              (export via snap_id)
        5) @awrextr awrdump_dir 21010120 21020320 both (export either AWR dump or SQL Monitor reports)
*/

COLUMN 4 NEW_VALUE 4
COLUMN 5 NEW_VALUE 5
COLUMN awr new_value awr
COLUMN did new_value did
SET TERMOUT OFF VERIFY OFF FEED OFF ARRAYSIZE 1000 PAGES 0 lines 200
SELECT  'awr' "4",'' "5" FROM dual WHERE ROWNUM = 0;
SELECT decode(lower('&4'),'sqlmon',2,'both',0,1) awr,'&5' did FROM V$DATABASE;
SET SERVEROUTPUT ON TERMOUT ON

DECLARE
    dir  VARCHAR2(128) := '&1';
    file VARCHAR2(512);
    root VARCHAR2(512);
    expr VARCHAR2(512);
    dump BFILE;
    len  NUMBER;
    std  DATE;
    edd  DATE;
    st   INT := '&2';
    ed   INT := '&3';
    did  INT := '&5';
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
        dbms_output.put_line('Cannot access directory: &1');
        return;
    ELSIF st IS NULL or ed IS NULL THEN
        dbms_output.put_line('Please specify the valid snapshot ids or time range.');
        return;
    END IF;

    $IF dbms_db_version.version>17 $THEN
        IF dbms_utility.directory_has_symlink(dir)=1 THEN
            dbms_output.put_line('Directory('||root||') has symbolic link, please change to the real path.');
            return;
        END IF;
    $END
    
    dbms_output.put_line('Exporting path: '||root);

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
                        dbms_output.put_line('No such snapshots(&2.-&3.),please make sure parameter awr_pdb_autoflush_enabled=true to enable AWR PDB level flushing, or connect to container CDB$ROOT.');
                        return;
                    END IF;
                END IF;
            $END
            dbms_output.put_line('Invalid snapshot range(&2.-&3.) for dbid ' || did);
            return;
        END IF;

        file := 'awrdat_' || did || '_' || st || '_' || ed;
        
        dump := bfilename(dir, file||'.dmp');
        BEGIN 
            sys.dbms_lob.fileopen(dump);
            len := dbms_lob.getlength(dump);
            sys.dbms_lob.fileclose(dump);
        EXCEPTION WHEN OTHERS THEN NULL; END;
        
        IF len > 0 THEN
            dbms_output.put_line('File already exists: ' || root || file || '.dmp');
            return;
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
    $IF dbms_db_version.version>11 AND (&awr=0 OR &awr=2) $THEN
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
        EXCEPTION WHEN OTHERS THEN NULL; END;

        IF len=0 THEN
            RETURN;
        END IF;

        BEGIN
            hdl := sys.dbms_datapump.attach(job, sys_context('userenv', 'current_schema'));
            sys.dbms_datapump.stop_job(hdl, 1, 0, 10);
            sys.dbms_datapump.detach(job);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
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