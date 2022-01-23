/*  Import AWR repository or SQL Monitor reports from DATA PUMP.
    For db version lower than 12c, the script requires SYSDBA privilege; for 12.1 onwards, requires DBA priviledge.
    
    Usage: @awrload <directory_name> <dump_file> [<new_dbid>|<sqlmon_table>]
    * directory_name: the directory name that can be found in all_directories, current schema must has the read/write access, and the path must not be symbolic link
    * dump_file     : the data pump file name under the directory
    * new_dbid      : optional, used for specifying new dbid of the target AWR dump file
    * sqlmon_table  : optional, the target table name to import the SQL Monitor dump file, default as "AWR_DUMP_REPORTS"
                      Be noted that to import SQL Monitor report, the dump file name must matches:  sqlmon.*_<number>_<number>_<export_schema>.dmp
    Examples:
        1) @awrload awrdump_dir awrdat_834293_11_12.dmp                             (import awr dump file)   
        2) @awrload awrdump_dir awrdat_834293_11_12.dmp 200                         (remap the dbid to 200)
        3) @awrload awrdump_dir sqlmon_834293_11_12_system.dmp                      (import sql monitor dump file)    
        4) @awrload awrdump_dir sqlmon_834293_11_12_system.dmp admin.sqlmon_reports (import sql monitor into admin.sqlmon_reports from dump file)    
*/

COLUMN 3 NEW_VALUE 3
COLUMN did new_value did
SET TERMOUT OFF VERIFY OFF FEED OFF ARRAYSIZE 1000 PAGES 0 lines 200
SELECT  '' "3" FROM dual WHERE ROWNUM = 0;
SELECT nvl('&3','AWR_DUMP_REPORTS') did from dual;
SET SERVEROUTPUT ON TERMOUT ON

DECLARE
    dir   VARCHAR2(128) := '&1';
    file  VARCHAR2(512) := '&2';
    did   INT := regexp_substr('&did','^\d+$');
    tab   VARCHAR2(512) := upper(regexp_substr('&did','^\D.*$'));
    root  VARCHAR2(2000);
    dump  BFILE;
    len   NUMBER;
    stage VARCHAR2(30) := 'STG_AWR';
    hdl   NUMBER;
    res   CLOB;
    job   VARCHAR2(128) := 'AWRLOAD_'||to_char(SYSDATE,'YYMMDDHH24MISS');
    own   VARCHAR2(128);
    own1  VARCHAR2(128);
    tab1  VARCHAR2(128);
BEGIN
    SELECT MAX(directory_name), MAX(directory_path)
    INTO   dir, root
    FROM   ALL_DIRECTORIES
    WHERE  upper(directory_name) = upper(dir);
    IF dir IS NULL THEN
        dbms_output.put_line('Cannot access directory: &1');
        RETURN;
    END IF;

    $IF dbms_db_version.version>17 $THEN
        IF dbms_utility.directory_has_symlink(dir)=1 THEN
            dbms_output.put_line('Directory('||root||') has symbolic link, please change to the real path.');
            RETURN;
        END IF;
    $END

    dbms_output.put_line('Importing path: '||root);

    IF NOT regexp_like(root, '[\\/]$') THEN
        root := root || CASE WHEN root LIKE '%/%' THEN '/' ELSE '\' END;
    END IF;
    
    <<CHECK_FILE>>
    dump := bfilename(dir, file||'.dmp');
    BEGIN 
        sys.dbms_lob.fileopen(dump);
        len := dbms_lob.getlength(dump);
        sys.dbms_lob.fileclose(dump);
    EXCEPTION WHEN OTHERS THEN
        IF regexp_like(file,'\.dmp$') THEN
            file := regexp_replace(file,'\.dmp$');
            GOTO CHECK_FILE;
        ELSE
            dbms_output.put_line('Cannot access file: ' || root || file || '.dmp');
            RETURN;
        END IF;
    END;
    
    IF instr(file,'sqlmon')>0 THEN
        hdl := null;
        $IF DBMS_DB_VERSION.VERSION>11 $THEN
            own := upper(regexp_substr(file,'_\d+_\d+_(\D.*)$',1,1,'i',1));
            IF own IS NULL THEN
                dbms_output.put_line('Cannot find schema name in file name:'||file);
                RETURN;
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
                    EXECUTE IMMEDIATE 'CREATE TABLE '||own||'.AWR_DUMP_REPORTS AS SELECT * FROM SYS.CDB_HIST_REPORTS WHERE 1=2';
                    EXECUTE IMMEDIATE 'CREATE TABLE '||own||'.AWR_DUMP_REPORTS_DETAILS AS SELECT * FROM SYS.CDB_HIST_REPORTS_DETAILS WHERE 1=2';
                    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own||'.UK_AWR_DUMP_REPORTS ON '||own||'.AWR_DUMP_REPORTS(DBID,REPORT_ID)';
                    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own||'.UK_AWR_DUMP_REPORTS_DETAILS ON '||own||'.AWR_DUMP_REPORTS_DETAILS(DBID,REPORT_ID)';
                EXCEPTION WHEN OTHERS THEN NULL; END;
                sys.dbms_datapump.set_parameter(hdl, name => 'TABLE_EXISTS_ACTION', value => 'APPEND');
                sys.dbms_datapump.start_job(hdl);
                sys.dbms_datapump.wait_for_job(hdl, res);
                IF tab IS NOT NULL AND (tab!='AWR_DUMP_REPORTS' OR own!=own1) THEN
                    len  := 128;
                    tab1 := tab||'_DETAILS';
                    $IF DBMS_DB_VERSION.VERSION<12 OR (DBMS_DB_VERSION.VERSION=12 AND DBMS_DB_VERSION.RELEASE=1) $THEN
                        len := 30;
                        IF LENGTH(TAB1)>30 THEN
                            tab1 := tab||'_DTL';
                        END IF;
                        IF LENGTH(TAB1)>30 THEN
                            dbms_output.put_line('Identifier is too long: '||tab1);
                            RETURN;
                        END IF;
                    $END
                    BEGIN
                        EXECUTE IMMEDIATE 'CREATE TABLE '||own1||'.'||tab ||' AS SELECT * FROM SYS.AWR_DUMP_REPORTS WHERE 1=2';
                        EXECUTE IMMEDIATE 'CREATE TABLE '||own1||'.'||tab1||' AS SELECT * FROM SYS.AWR_DUMP_REPORTS_DETAILS WHERE 1=2';
                        EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own1||'.UK_'||substr(tab ,1,len-3)||' ON '||own1||'.'||tab ||'(DBID,REPORT_ID)';
                        EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX '||own1||'.UK_'||substr(tab1,1,len-3)||' ON '||own1||'.'||tab1||'(DBID,REPORT_ID)';
                    EXCEPTION WHEN OTHERS THEN NULL; END;
                    EXECUTE IMMEDIATE 'INSERT /*+IGNORE_ROW_ON_DUPKEY_INDEX(A UK_'||substr(tab ,1,len-3)||') DISABLE_PARALLEL_DML*/ INTO '||own1||'.'||tab ||' A SELECT * FROM '||own||'.AWR_DUMP_REPORTS';
                    EXECUTE IMMEDIATE 'INSERT /*+IGNORE_ROW_ON_DUPKEY_INDEX(A UK_'||substr(tab1,1,len-3)||') DISABLE_PARALLEL_DML*/ INTO '||own1||'.'||tab1||' A SELECT * FROM '||own||'.AWR_DUMP_REPORTS_DETAILS';
                    COMMIT;
                    EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS PURGE';
                    EXECUTE IMMEDIATE 'DROP TABLE '||own||'.AWR_DUMP_REPORTS_DETAILS PURGE';
                    own := own1;
                ELSE
                    tab  := 'AWR_DUMP_REPORTS';
                    tab1 := 'AWR_DUMP_REPORTS_DETAILS';
                END IF;
                dbms_output.put_line('SQL Monitor reports are imported into '||own||'.'||tab||' and '||own||'.'||tab1||'.');
            EXCEPTION WHEN OTHERS THEN
                root := dbms_utility.format_error_stack||dbms_utility.format_error_backtrace;
                BEGIN
                    sys.dbms_datapump.stop_job(hdl, 1, 0, 0);
                    sys.dbms_datapump.detach(hdl);
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
                sys.dbms_swrf_internal.awr_load(schname  => stage,dmpfile  => file, dmpdir => dir);
                sys.dbms_swrf_internal.move_to_awr(schname  => stage, new_dbid => did);
                sys.dbms_swrf_internal.clear_awr_dbid;
            $END
        $END
        dbms_output.put_line('AWR repository is imported from ' || root || file || '.dmp');
    END IF;
END;
/