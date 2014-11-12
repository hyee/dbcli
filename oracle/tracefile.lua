local env=env
local db,grid=env.oracle,env.grid
local trace={}
function trace.get_trace(filename)
    local sql=[[
    DECLARE
        f          VARCHAR2(2000) := :1;
        dir        VARCHAR2(2000);
        text       CLOB;
        trace_file utl_file.file_type;
        buff       VARCHAR2(32767);
        flag       PLS_INTEGER;     
        idx        PLS_INTEGER;       
    BEGIN
        SELECT MAX(directory_name)
        INTO   dir
        FROM   Dba_Directories
        WHERE  f LIKE directory_path || '%'
        AND    NOT regexp_like(SUBSTR(f, LENGTH(directory_path) + 2), '[\\/]');

        IF dir IS NULL THEN
            buff := 'create or replace directory DBCLI_DUMP_DIR as ''' || regexp_replace(f, '[^\\/]+$') || '''';
            dir  := 'DBCLI_DUMP_DIR';
            flag := 1;
            idx  := 1;
            EXECUTE IMMEDIATE buff;            
        END IF;

        f := regexp_substr(f, '[^\\/]+$');
        dbms_lob.createtemporary(text, TRUE);

        flag := 2;
        trace_file := utl_file.fopen(dir, f, 'R', 32767);

        flag := 3;
        BEGIN
            LOOP
                utl_file.get_line(trace_file, buff, 32767);                
                dbms_lob.writeappend(text, nvl(LENGTHB(buff)+1,1), buff||chr(10));
                --dbms_output.put_line(buff);
            END LOOP;
        EXCEPTION
            WHEN no_data_found THEN
                utl_file.fclose(trace_file);
                IF idx=1 THEN                
                    EXECUTE IMMEDIATE 'drop directory ' || dir;
                END IF;
            WHEN OTHERS THEN
                utl_file.fclose(trace_file);
                RAISE;
        END;
        :2 := f;
        :3 := text;
    EXCEPTION WHEN OTHERS THEN        
        IF flag = 1 THEN
            buff:='You don''t have the priv to create directory, pls exec following commands with DBA account:'||chr(10)||'    '||buff;
            buff:=buff||';'||chr(10)||'    grant read on directory DBCLI_DUMP_DIR to '||user||';';
        ELSIF flag = 2 THEN    
            buff:='Unable to open '||f||' under directory '||dir||chr(10)||sqlerrm||')';            
        ELSE
            raise_application_error(-20001,dbms_utility.format_error_stack || dbms_utility.format_error_backtrace);
        END IF;
        :4 := buff;
    END;]]
    env.checkerr(filename,"Please specify the trace file location !")
    db:internal_call("alter session set sql_trace=false")
    if filename:lower()=="default" then
        filename=db:get_value[[ SELECT u_dump.value || '/' || SYS_CONTEXT('userenv','instance_name') || '_ora_' || v$process.spid ||
                                       nvl2(v$process.traceid, '_' || v$process.traceid, NULL) || '.trc' "Trace File"
                                FROM   v$parameter u_dump
                                CROSS  JOIN v$process
                                JOIN   v$session
                                ON     v$process.addr = v$session.paddr
                                WHERE  u_dump.name = 'user_dump_dest'
                                AND    v$session.audsid = sys_context('userenv', 'sessionid')]]
    end
    local args={filename,"#VARCHAR","#CLOB","#VARCHAR"}
    db:internal_call(sql,args)
    env.checkerr(args[2],args[4])
    print("Result written to file "..env.write_cache(args[2],args[3]))
end

env.set_command(nil,"loadtrace","Download Oracle trace file into local directory. Usage: loadtrace <trace_file|default>",trace.get_trace,false,2)

return trace