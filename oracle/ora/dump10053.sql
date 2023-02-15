/*[[
    Dump the 10053 trace for the specific SQL ID. Usage: @@NAME {<sql_id> [<child_number>|<plan_hash_value>] | <sql_text> | <incident_no>} [-c|-e"<directory>"]
    Note: In RAC environment, it only supports dumping the SQL ID in local node(view v$sqlarea).
    -c: Generate SQL Compiler trace file, otherwise generate 10053 trace file
    -e: Export SQL test case without generating data pump file
    -u: Don't generate the metadata as a dump file, and don't compress the output files
    --[[
        @version: 11.0={}
        @ALIAS  : DUMPCASE
        &opt    : default={Optimizer}, c={Compiler}, e={&0}
        &opt1   : default={3} c={2} e={1}
        &z      : default={} u={--}
        &z1     : default={--} u={}
        @ARGS   : 1
    --]]
]]*/
set feed off verify off sqltimeout 7200
var file VARCHAR2(500);
var file1 VARCHAR2(500);
var c refcursor;
DECLARE
    sq_id     VARCHAR2(32767) := :V1;
    sq_text   CLOB;
    nam       VARCHAR2(128):= trim(:opt);
    file      VARCHAR2(500); 
    dir       VARCHAR2(300);
    sep       VARCHAR2(1);
    child_num INT := regexp_substr(:V2, '^\d+$');
    phv       INT;
    res       CLOB;
    xml       XMLTYPE;
    fixctl    PLS_INTEGER;
    ctrlOptions VARCHAR2(2000):='<parameters><parameter name="compress">yes</parameter><parameter name="capture">with_runtime_info</parameter><parameter name="diag_event">SQLEXEC_HIGHEST</parameter><parameter name="problem_type">PERFORMANCE</parameter></parameters>';
BEGIN
    IF instr(sq_id,' ')>0 THEN
        sq_text := sq_id;
        sq_id   := NULL;
    END IF;
    IF NOT regexp_like(sq_id,'^\d+$') THEN
        SELECT /*+no_expand*/
               MAX(child_number) KEEP(dense_rank LAST ORDER BY TIMESTAMP),
               MAX(plan_hash_value) KEEP(dense_rank LAST ORDER BY TIMESTAMP)
        INTO   child_num, phv
        FROM   v$sql_plan_statistics_all a
        WHERE  a.sql_id = sq_id
        AND    (child_num IS NULL OR child_num IN (plan_hash_value, child_number));

        IF phv IS NULL THEN
            BEGIN
                SELECT SQL_TEXT INTO sq_text
                FROM (
                    SELECT SQL_FULLTEXT SQL_TEXT
                    FROM   GV$SQLAREA
                    WHERE  SQL_ID=sq_id
                    AND    rownum<2
                    UNION ALL
                    SELECT SQL_TEXT
                    FROM   DBA_HIST_SQLTEXT
                    WHERE  SQL_ID=sq_id
                    AND    rownum<2
                ) WHERE rownum<2;
                sq_id := NULL;
            EXCEPTION WHEN OTHERS THEN 
                raise_application_error(-20001, 'Cannot find target SQL in v$sql_plan_statistics_all: '||sq_id);
            END;
        END IF;
    END IF;
    BEGIN
        fixctl := sys.dbms_sqldiag.get_fix_control(16923858);
        IF fixctl=6 THEN
            EXECUTE IMMEDIATE q'{alter session set "_fix_control"='16923858:5'}';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    IF :opt1 = 1 OR regexp_like(sq_id,'^\d+$') THEN
        IF nam IS NULL THEN
            raise_application_error(-20001, 'Please specify the target directory name');
        END IF;

        SELECT MAX(directory_path), MAX(directory_name)
        INTO   dir, nam
        FROM   all_directories
        WHERE  upper(directory_name) = upper(nam)
        AND    rownum < 2;

        IF dir IS NULL THEN
            raise_application_error(-20001, 'No access to the directory or target directory does not exist: ' || nam);
        END IF;

        $IF dbms_db_version.version>17 $THEN
            IF dbms_utility.directory_has_symlink(nam)=1 THEN
                raise_application_error(-20001, 'Directory('||dir||') has symbolic link, please change to the real path.');
            END IF;
        $END
        
        IF regexp_like(sq_id,'^\d+$') THEN
            sys.dbms_sqldiag.export_sql_testcase(directory       => nam,
                                             incident_id     => sq_id,
                                             exportData      => false,
                                             &z exportMetadata  => false,
                                             &z ctrlOptions=> ctrlOptions,
                                             testcase        => res);
        ELSIF phv IS NULL THEN
            IF sq_id IS NOT NULL THEN
                sys.dbms_sqldiag.export_sql_testcase(directory       => nam,
                                                 sql_id          => sq_id,
                                                 exportData      => false,
                                                 &z exportMetadata  => false,
                                                 &z ctrlOptions  => ctrlOptions,
                                                 testcase        => res);
            ELSE
                sys.dbms_sqldiag.export_sql_testcase(directory       => nam,
                                                 sql_text        => sq_text,
                                                 user_name       => sys_context('userenv','current_schema'),
                                                 exportData      => false,
                                                 &z exportMetadata  => false,
                                                 &z ctrlOptions  => ctrlOptions,
                                                 testcase        => res);
            END IF;
        ELSE
            sys.dbms_sqldiag.export_sql_testcase(directory       => nam,
                                             sql_id          => sq_id,
                                             plan_hash_value => phv,
                                             exportData      => false,
                                             &z exportMetadata  => false,
                                             &z ctrlOptions     => ctrlOptions,
                                             testcase        => res);
        END IF;
        sep := regexp_substr(dir, '[\\/]');

        $IF DBMS_DB_VERSION.VERSION > 11 $THEN
        SELECT regexp_replace(max(adr_home||'/'||trace_filename) keep(dense_rank last ORDER BY modify_time), '[\\/]+', sep)
        INTO   file
        FROM   v$diag_trace_file
        WHERE  TRACE_FILENAME LIKE '%\_tcb\_diag.trc' ESCAPE '\';
        $END
        
        :file := file;
        SELECT max(case when name like '%.html' then regexp_replace(dir || sep || name, '[\\/]+', sep) end)
        INTO   :file1
        FROM   xmltable('//FILE' passing(xmltype(res)) columns TYPE path 'TYPE', goal path 'GOAL', NAME path 'NAME');
        
        OPEN :c FOR
            SELECT type,goal,regexp_replace(dir || sep || NAME, '[\\/]+', sep) name
            FROM   xmltable('//FILE' passing(xmltype(res)) columns TYPE path 'TYPE', goal path 'GOAL', NAME path 'NAME')
            UNION  ALL
            SELECT 'DIAG','TRACE_FILE',:file FROM dual
            ORDER  BY 1,2,3;
    ELSE
        IF phv IS NULL THEN
            raise_application_error(-20001, 'Please specify a valid SQL ID that exists in v$sql_plan_statistics_all.');
        ELSE
            BEGIN
                EXECUTE IMMEDIATE 'ALTER SESSION SET tracefile_identifier='''||ROUND(DBMS_RANDOM.VALUE(1,1E6))||'''';
            EXCEPTION WHEN OTHERS THEN NULL;
                DBMS_SESSION.SET_IDENTIFIER(ROUND(DBMS_RANDOM.VALUE(1,1E6)));
            END;
            sys.dbms_sqldiag.dump_trace(sq_id, child_num, nam);
        END IF;
        :file := 'default';
    END IF;
END;
/
print c
&z1 loadtrace &file1;
loadtrace &file 64;