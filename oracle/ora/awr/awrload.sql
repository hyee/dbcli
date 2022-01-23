/*[[Import AWR repository dump or sql monitor dump. Usage: @@NAME <directory_name> <file_name> [<new_dbid>|<sqlmon_table>]
    For SQL Monitor dump:
        * the file name must match the syntax: sqlmon_[<num>_]<num>_<num>_<source_schema>.dmp
        * the table names are: AWR_DUMP_REPORTS,AWR_DUMP_REPORTS_DETAILS
    <new_dbid>    : The new dbid to import the AWR dump
    <sqlmon_table>: The table name to store the SQL Monitor reports
    --[[
        @ARGS: 2
    --]]
]]*/
SET SQLTIMEOUT 7200

DECLARE
    dir   VARCHAR2(128) := :V1;
    file  VARCHAR2(512) := :V2;
    did   INT := regexp_substr(:V3,'^\d+$');
    tab   VARCHAR2(512) := upper(regexp_substr(:V3,'^\D.*$'));
    root  VARCHAR2(2000);
    dump  BFILE;
    len   NUMBER;
    stage VARCHAR2(30) := 'DBCLI_AWR';
    hdl   NUMBER;
    res   CLOB;
    job   VARCHAR2(128) := 'AWRLOAD_'||to_char(SYSDATE,'YYMMDDHH24MISS');
    own   VARCHAR2(128);
    own1  VARCHAR2(128);
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
    
    <<CHECK_FILE>>
    dump := bfilename(dir, file||'.dmp');
    BEGIN 
        dbms_lob.fileopen(dump);
        len := dbms_lob.getlength(dump);
        dbms_lob.fileclose(dump);
    EXCEPTION WHEN OTHERS THEN
        IF regexp_like(file,'\.dmp$') THEN
            file := regexp_replace(file,'\.dmp$');
            GOTO CHECK_FILE;
        ELSE
            raise_application_error(-20001, 'Cannot access file: ' || root || file || '.dmp');
        END IF;
    END;
    
    IF instr(file,'sqlmon')>0 THEN
        hdl := null;
        $IF DBMS_DB_VERSION.VERSION>11 $THEN
            own := upper(regexp_substr(file,'_\d+_\d+_(\D.*)$',1,1,'i',1));
            IF own IS NULL THEN
                raise_application_error(-20001,'Cannot find schema name in file name:'||file);
            END IF;
            BEGIN
                hdl := sys.dbms_datapump.attach(job, sys_context('userenv', 'current_schema'));
                sys.dbms_datapump.stop_job(hdl, 1, 0, 10);
                sys.dbms_datapump.detach(job);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            own1 := sys_context('userenv','current_schema');
            IF tab IS NOT NULL AND instr(tab,'.')>0 THEN
                own1 := regexp_substr('[^.+]',1,1);
                tab  := regexp_substr('[^.+]',1,2);
            END IF;
            own1:= regexp_replace(own1,'^SYS$','SYSTEM');
            hdl := sys.dbms_datapump.open(operation   => 'IMPORT',
                                          job_mode    => 'TABLE',
                                          job_name    => job,
                                          version     => '12');
            
            BEGIN
                sys.dbms_datapump.add_file(handle    => hdl,
                                           filetype  => sys.dbms_datapump.KU$_FILE_TYPE_DUMP_FILE,
                                           filename  => file||'.dmp',
                                           directory => dir);
                sys.dbms_datapump.add_file(handle    => hdl,
                                           filetype  => sys.dbms_datapump.KU$_FILE_TYPE_LOG_FILE,
                                           filename  => file||'_imp.log',
                                           directory => dir);
                IF own != own1 and own!='SYSTEM' THEN
                    sys.dbms_datapump.metadata_remap(hdl,'REMAP_SCHEMA',own,own1);
                    own := own1;
                END IF;
                BEGIN
                    EXECUTE IMMEDIATE 'CREATE TABLE '||own||'.AWR_DUMP_REPORTS AS SELECT * FROM SYS.DBA_HIST_REPORTS WHERE 1=2';
                    EXECUTE IMMEDIATE 'CREATE TABLE '||own||'.AWR_DUMP_REPORTS_DETAILS AS SELECT * FROM SYS.DBA_HIST_REPORTS_DETAILS WHERE 1=2';
                    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own||'.UK_AWR_DUMP_REPORTS ON '||own||'.AWR_DUMP_REPORTS(DBID,REPORT_ID)';
                    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own||'.UK_AWR_DUMP_REPORTS_DETAILS ON '||own||'.AWR_DUMP_REPORTS_DETAILS(DBID,REPORT_ID)';
                EXCEPTION WHEN OTHERS THEN NULL; END;
                sys.dbms_datapump.set_parameter(hdl, name => 'TABLE_EXISTS_ACTION', value => 'APPEND');
                sys.dbms_datapump.start_job(hdl);
                sys.dbms_datapump.wait_for_job(hdl, res);
                IF tab IS NOT NULL AND (tab!='AWR_DUMP_REPORTS' OR own!=own1) THEN
                    BEGIN
                        EXECUTE IMMEDIATE 'CREATE TABLE '||own1||'.'||tab||' AS SELECT * FROM SYS.DBA_HIST_REPORTS WHERE 1=2';
                        EXECUTE IMMEDIATE 'CREATE TABLE '||own1||'.'||tab||'_DETAILS AS SELECT * FROM SYS.DBA_HIST_REPORTS_DETAILS WHERE 1=2';
                        EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own1||'.UK_'||tab||' ON '||own1||'.'||tab||'(DBID,REPORT_ID)';
                        EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own1||'.UK_'||tab||'_DETAILS ON '||own1||'.'||tab||'_DETAILS(DBID,REPORT_ID)';
                    EXCEPTION WHEN OTHERS THEN NULL; END;
                    EXECUTE IMMEDIATE 'INSERT /*+IGNORE_ROW_ON_DUPKEY_INDEX(A UK_'||tab||') DISABLE_PARALLEL_DML*/ INTO '||own1||'.'||tab||' A SELECT * FROM '||own||'.AWR_DUMP_REPORTS';
                    EXECUTE IMMEDIATE 'INSERT /*+IGNORE_ROW_ON_DUPKEY_INDEX(A UK_'||tab||'_DETAILS) DISABLE_PARALLEL_DML*/ INTO '||own1||'.'||tab||'_DETAILS A SELECT * FROM '||own||'.AWR_DUMP_REPORTS_DETAILS';
                    COMMIT;
                    EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS PURGE';
                    EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS_DETAILS PURGE';
                    own := own1;
                ELSE
                    tab := 'AWR_DUMP_REPORTS';
                END IF;
                dbms_output.put_line('SQL Monitor reports are imported into '||own||'.'||tab||' and '||own||'.'||tab||'_DETAILS.');
            EXCEPTION WHEN OTHERS THEN
                root := dbms_utility.format_error_stack||dbms_utility.format_error_backtrace;
                BEGIN
                    sys.dbms_datapump.stop_job(hdl, 1, 0, 10);
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
                dbms_output.put_line(root);
            END;
        $END
    ELSE
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
    END IF;
END;
/