local env=env
local db,grid=env.getdb(),env.grid
local trace={}
function trace.get_trace(filename,mb,from_mb)
    local sql=[[
    DECLARE
        f          VARCHAR2(2000) := :1;
        dir        VARCHAR2(2000);
        buff       VARCHAR2(500);
        text       CLOB;
        trace_file BFILE;
        flag       PLS_INTEGER;
        MBs        INT := :mb * 1024 * 1024;
        from_MB    INT := :from_mb * 1024 * 1024 - 1;
        fsize      INT;
        startpos   PLS_INTEGER:=1;
        lang_ctx   PLS_INTEGER:=0;
        csid       PLS_INTEGER:=0;
        warn       PLS_INTEGER:=0;
        PROCEDURE drop_dir IS
        BEGIN
            EXECUTE IMMEDIATE 'drop directory DBCLI_DUMP_DIR';
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    BEGIN
        SELECT MAX(directory_name)
        INTO   dir
        FROM   Dba_Directories
        WHERE  f LIKE directory_path || '%'
        AND    NOT regexp_like(SUBSTR(f, LENGTH(directory_path) + 2), '[\\/]');

        IF dir IS NULL THEN
            buff := 'create or replace directory DBCLI_DUMP_DIR as ''' || regexp_replace(f, '[^\\/]+$') || '''';
            dir  := 'DBCLI_DUMP_DIR';
            flag := 0;
            EXECUTE IMMEDIATE buff;
        END IF;

        flag := 2;
        f          := regexp_substr(f, '[^\\/]+$');
        trace_file := bfilename(dir, f);
        dbms_lob.fileopen(trace_file);
        fsize      := dbms_lob.getlength(trace_file);
        flag       := 3;

        IF from_MB IS NULL THEN
            from_MB := fsize - MBs+1;
        END IF;

        IF from_MB < 1 THEN
            from_MB := 1;
        ELSIF from_MB > fsize THEN
            from_MB := fsize;
        END IF;

        MBs:= least(MBs,fsize-from_MB+1);
        dbms_lob.createtemporary(text,true);
        dbms_lob.loadclobfromfile(text,trace_file,MBs,startpos,from_MB,csid,lang_ctx,warn);
        dbms_lob.fileclose(trace_file);
        drop_dir;
        :2   := f;
        :3   := text;
        :res := 'File Size: ' || round(fsize / 1024 / 1024, 2) || ' MB        Extract Size: '
                ||round(length(text) / 1024 / 1024, 2) || ' MB        Start Extract Position: '
                ||round((from_MB-length(text)) / 1024 / 1024, 2) || ' MB';
    EXCEPTION
        WHEN OTHERS THEN
            IF trace_file IS NOT NULL AND DBMS_LOB.FILEISOPEN(trace_file)=1 THEN
                dbms_lob.fileclose(trace_file);
            END IF;
            drop_dir;
            IF flag = 0 THEN
                buff := 'You don''t have the priv to create directory, pls exec following commands with DBA account:' ||
                        chr(10)||buff|| ';' || chr(10) || 'grant read on directory DBCLI_DUMP_DIR to ' || USER || ';';
            ELSIF flag = 1 THEN
                buff := 'File ' || f || ' under directory ' || dir || ' does not exist!';
            ELSIF flag = 2 THEN
                buff := 'Unable to open ' || f || ' under directory(' || dir || chr(10) || SQLERRM || ')';
            ELSE
                raise_application_error(-20001,dbms_utility.format_error_stack||dbms_utility.format_error_backtrace);
            END IF;
            :4 := buff;
    END;]]

    env.checkhelp(filename)
    if not db.props.db_version then env.raise_error('Database is not connected!') end;
    db:internal_call("alter session set events '10046 trace name context off'")
    db:internal_call("alter session set tracefile_identifier=CLEANUP")
    db:internal_call("alter session set tracefile_identifier=''")
    filename=filename:lower()
    local lv=nil
    if filename:find("^%d+$") then lv=tonumber(filename) end
    if filename=="default" or lv then
        if lv then
            db:internal_call("alter session set tracefile_identifier='dbcli_"..math.random(1e6).."'");
        end
        if db.props.db_version>'10' then
            filename=db:get_value[[select value from v$diag_info where name='Default Trace File']]
        else
            filename=db:get_value[[SELECT u_dump.value || '/' || SYS_CONTEXT('userenv','instance_name') || '_ora_' || p.spid ||
                                           nvl2(p.traceid, '_' || p.traceid, NULL) || '.trc' "Trace File"
                                    FROM   v$parameter u_dump
                                    CROSS  JOIN v$process p
                                    JOIN   v$session s
                                    ON     p.addr = s.paddr
                                    WHERE  u_dump.name = 'user_dump_dest'
                                    AND    s.audsid = sys_context('userenv', 'sessionid')]]
        end
        if lv then
            if lv > 0 then
                print("Trace on: "..filename)
                db:internal_call("alter session set events '10046 trace name context forever, level "..lv.."'")
            else
                print("Trace off: "..filename)
            end
            return
        end
    elseif filename=="alert" then
        if db.props.db_version<'11' then
            filename=db:get_value[[SELECT u_dump.value || '/alert_' || SYS_CONTEXT('userenv', 'instance_name') || '.log' "Trace File"
                                   FROM   v$parameter u_dump
                                   WHERE  u_dump.name = 'background_dump_dest']]
        else
            filename=db:get_value[[select value|| '/alert_' || SYS_CONTEXT('userenv', 'instance_name') || '.log' from v$diag_info where name='Diag Trace']]
        end
    end
    local args={filename,"#VARCHAR","#CLOB","#VARCHAR",mb=mb or 2,from_mb=from_mb or '',res='#VARCHAR'}
    db:internal_call(sql,args)
    env.checkerr(args[2],args[4])
    print(args.res);
    print("Result written to file "..env.write_cache(args[2],args[3]))
end

env.set_command(nil,{"loadtrace","dumptrace"},[[
    Download Oracle trace file into local directory. Usage: @@NAME <trace_file|default|alert|0/1/4/8/12> [MB [begin_MB] ]
    This command requires the "create directory" privilige.
    Parameters:
        trace_file: 1) The absolute path of the target trace file, or
                    2) "default" to extract current session's trace, or
                    4) 0/1/4/8/12 to enable 10046 trace with specific level
                    3) "alert" to extract local instance's alert log.
        MB        : MegaBytes to extract, default as 2 MB.
        begin_MB  : The start file position(in MB) to extract, default as "total_MB - <MB>"
    ]],trace.get_trace,false,4)

return trace