local env=env
local db,grid=env.oracle,env.grid
local trace={}
function trace.get_trace(filename,mb,from_mb)
    local sql=[[
    DECLARE
        f          VARCHAR2(2000) := :1;
        dir        VARCHAR2(2000) ;
        text       CLOB;
        trace_file utl_file.file_type;
        buff       VARCHAR2(32767);
        flag       PLS_INTEGER;     
        MBs        INT:=:mb*1024*1024;
        from_MB    INT:=:from_mb*1024*1024-1; 
        counter    INT:=0;
        isexists   BOOLEAN;
        fsize      INT;
        bsize      INT;        
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

        f := regexp_substr(f, '[^\\/]+$');
        
        flag := 1;
        UTL_FILE.FGETATTR(dir,f, isexists, fsize, bsize);
        IF NOT isexists THEN
            raise_application_error(-20001,'1');
        END IF;

        flag := 2;
        trace_file := utl_file.fopen(dir, f, 'R', 32767);

        flag := 3;
                        
        if from_MB is null then
            from_MB := fsize-MBs;
        end if;
        
        if from_MB <0 then
            from_MB := 0;
        elsif from_MB > fsize then
            from_MB := fsize;
        end if;
        
        utl_file.fseek(trace_file,from_MB);
        
        dbms_lob.createtemporary(text, TRUE);
        BEGIN
            LOOP
                utl_file.get_line(trace_file, buff, 32767);
                counter := counter+nvl(lengthb(buff)+1,1);
                dbms_lob.writeappend(text, nvl(length(buff)+1,1), buff||chr(10));   
                EXIT WHEN counter>MBs;               
            END LOOP;
        EXCEPTION
            WHEN no_data_found THEN
                null;
            WHEN OTHERS THEN
                utl_file.fclose(trace_file);
                RAISE;
        END;
        
        utl_file.fclose(trace_file);
        :2   := f;
        :3   := text;
        :res := 'File Size: '||round(fsize/1024/1024,2)||' MB        Extract Size: '||round(counter/1024/1024,2)||' MB        Start Extract Position: '||round(from_MB/1024/1024,2)||' MB';
        BEGIN EXECUTE IMMEDIATE 'drop directory ' || dir; EXCEPTION WHEN OTHERS THEN NULL;END;
    EXCEPTION WHEN OTHERS THEN        
        IF flag = 0 THEN
            buff:='You don''t have the priv to create directory, pls exec following commands with DBA account:'||chr(10)||'    '||buff;
            buff:=buff||';'||chr(10)||'    grant read on directory DBCLI_DUMP_DIR to '||user||';';
        ELSIF flag = 1 THEN
            buff:='File '||f||' under directory '||dir||' does not exist!';
        ELSIF flag = 2 THEN    
            buff:='Unable to open '||f||' under directory '||dir||chr(10)||sqlerrm||')';            
        ELSE
            raise_application_error(-20001,dbms_utility.format_error_stack || dbms_utility.format_error_backtrace);
        END IF;
        :4 := buff;
    END;]]
    
    env.checkerr(filename,"Please specify the trace file location !")
    if not db.props.db_version then env.raise_error('Database is not connected!') end;
    db:internal_call("alter session set sql_trace=false")
    filename=filename:lower()
    if filename=="default" then
        if db.props.db_version>'11' then
            filename=db:get_value[[select value from v$diag_info where name='Default Trace File']]
        else
            filename=db:get_value[[ SELECT u_dump.value || '/' || SYS_CONTEXT('userenv','instance_name') || '_ora_' || v$process.spid ||
                                           nvl2(v$process.traceid, '_' || v$process.traceid, NULL) || '.trc' "Trace File"
                                    FROM   v$parameter u_dump
                                    CROSS  JOIN v$process
                                    JOIN   v$session
                                    ON     v$process.addr = v$session.paddr
                                    WHERE  u_dump.name = 'user_dump_dest'
                                    AND    v$session.audsid = sys_context('userenv', 'sessionid')]]
            end
    elseif filename=="alert" then
        if db.props.db_version<='11' then
            filename=db:get_value[[SELECT u_dump.value || '/alert_' || SYS_CONTEXT('userenv', 'instance_name') || '.log' "Trace File"
                                   FROM   v$parameter u_dump
                                   WHERE  u_dump.name = 'background_dump_dest']] 
        else
            filename=db:get_value[[select value|| '/alert_' || SYS_CONTEXT('userenv', 'instance_name') || '.log' from v$diag_info where name='Diag Trace']]
        end   
    end
    local args={filename,"#VARCHAR","#CLOB","#VARCHAR",mb=mb or 4,from_mb=from_mb or '',res='#VARCHAR'}
    db:internal_call(sql,args)
    env.checkerr(args[2],args[4])
    print(args.res);
    print("Result written to file "..env.write_cache(args[2],args[3]))
end

env.set_command(nil,"loadtrace",[[
    Download Oracle trace file into local directory. Usage: loadtrace <trace_file|default|alert> [MB [begin_MB] ] 
    This command requires the "create directory" and "utl_file" priviliges.
    Parameters:
        trace_file: 1) The absolute path of the target trace file, or
                    2) "default" to extract current session's trace, or 
                    3) "alert" to extract local instance's alert log.
        MB        : MegaBytes to extract, default to 4 MB.
        begin_MB  : The start file position(in MB) which is excluded into extract list, default as "total_MB - <MB>"
    ]],trace.get_trace,false,4)

return trace