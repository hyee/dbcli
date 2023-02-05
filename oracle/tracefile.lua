local env=env
local db,grid=env.getdb(),env.grid
local trace={}
function trace.get_trace(filename,mb,from_mb)
    local sql=[[
    DECLARE
        org        VARCHAR2(2000) := :1;
        f          VARCHAR2(2000) := org;
        vw         VARCHAR2(61)   := :5;
        al         VARCHAR2(61)   := :6;
        dir        VARCHAR2(200);
        tmp        varchar2(200);
        buff       VARCHAR2(32767);
        text       CLOB;
        tmptext    CLOB;
        trace_file BFILE;
        flag       PLS_INTEGER;
        MBs        INT := :mb * 1024 * 1024;
        from_MB    INT := :from_mb * 1024 * 1024 - 1;
        fsize      INT := 0;
        pos        INT := 0;
        startpos   PLS_INTEGER:=0;
        lang_ctx   PLS_INTEGER:=0;
        csid       PLS_INTEGER:=0;
        warn       PLS_INTEGER:=0;
        type       t is table of varchar2(8000);
        t1         t;
        cur        sys_refcursor;
        PROCEDURE drop_dir IS
        BEGIN
            EXECUTE IMMEDIATE 'drop directory DBCLI_DUMP_DIR';
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
        @lz_compress@
    BEGIN
        dir := regexp_substr(f, '.*[\\/]');
        f   := substr(f, length(dir) + 1);
        tmp := dir;
        BEGIN
            flag := -1;
            BEGIN
                EXECUTE IMMEDIATE replace(q'[
                    SELECT MAX(directory_name)
                    FROM   Dba_Directories
                    WHERE  lower('@t') LIKE lower(directory_path) || '%'
                    AND    length('@t') - length(directory_path) < 2]','@t',tmp)
                INTO dir;
            EXCEPTION WHEN OTHERS THEN
                SELECT MAX(directory_name)
                INTO   dir
                FROM   All_Directories
                WHERE  lower(tmp) LIKE lower(directory_path) || '%'
                AND    length(tmp) - length(directory_path) < 2;
            END;
        
            flag := 0;
            IF dir IS NULL THEN
                IF :readonly = 'off' THEN 
                    buff := 'create or replace directory DBCLI_DUMP_DIR as ''' || tmp || '''';
                    dir  := 'DBCLI_DUMP_DIR';
                    flag := 0;
                    EXECUTE IMMEDIATE buff;
                ELSE
                    GOTO FILE_FROM_DICT;
                END IF;
            END IF;
        
            flag       := 1;
            trace_file := bfilename(dir, f);
            flag       := 2;
            --consider _disable_directory_link_check/_kolfuseslf=true in case symbolic links issue
            dbms_lob.fileopen(trace_file);
            fsize := dbms_lob.getlength(trace_file);
            IF fsize = 0 THEN
                raise_application_error(-20001, '1');
            END IF;
            flag := 3;
        
            IF from_MB IS NULL THEN
                from_MB := fsize - MBs + 1;
            END IF;
        
            IF from_MB < 1 THEN
                from_MB := 1;
            ELSIF from_MB > fsize THEN
                from_MB := fsize;
            END IF;
        
            startpos := 1;
            pos      := from_MB;
            MBs      := least(MBs, fsize - from_MB + 1);
            dbms_lob.createtemporary(text, true);
            dbms_lob.loadclobfromfile(text, trace_file, MBs, startpos, pos, csid, lang_ctx, warn);
            dbms_lob.fileclose(trace_file);
            drop_dir;

            tmp := 'File Size: ' || round(fsize/1024/1024, 3) || ' MB        Extract Size: ' || round(length(text)/1024/1024, 3) ||
                    ' MB        Start Extract Position: ' || round(from_MB/1024/1024, 3) || ' MB';
            base64encode(text);
        EXCEPTION
            WHEN OTHERS THEN
                text := null;
                buff := dbms_utility.format_error_stack || dbms_utility.format_error_backtrace;
                buff := regexp_replace(regexp_replace(buff,' *['||CHR(10)||CHR(13)||']+',','),',([A-Z]+\-\d+)',CHR(10)||'\1');
                IF trace_file IS NOT NULL AND DBMS_LOB.FILEISOPEN(trace_file) = 1 THEN
                    dbms_lob.fileclose(trace_file);
                END IF;
                drop_dir;
                IF flag = -1 THEN
                    buff := 'You cannot access view dba_directories, please grant the relative access right!';
                ELSIF flag = 0 THEN
                    buff := 'You don''t have the priv to create directory, pls exec following commands with DBA account:' || chr(10) || buff || ';' ||
                            chr(10) || 'grant read on directory DBCLI_DUMP_DIR to ' || USER || ';';
                ELSIF flag = 1 THEN
                    buff := 'File ' || f || ' under directory ' || tmp || ' does not exist!';
                ELSIF flag = 2 THEN
                    buff := regexp_substr(buff,'([A-Z]+\-\d+)[^'||CHR(10)||']+')||'[dir="'||tmp||'" file="'||f||'"]';
                END IF;
        END;

        <<FILE_FROM_DICT>>
        IF text IS NULL THEN
            dir  := regexp_replace(regexp_replace(tmp,'[\\/]trace[\\/]$'),'[\\/]$');
            IF al IS NOT NULL THEN
                OPEN cur FOR 'SELECT rtrim(message_text) FROM table(gv$(CURSOR(SELECT * FROM V$DIAG_ALERT_EXT WHERE filename LIKE :d1)))' USING dir||'%';
            ELSIF vw IS NOT NULL THEN
                OPEN cur FOR 'select rtrim(payload) from ' || vw || '_CONTENTS where ADR_HOME=:d and TRACE_FILENAME=:f' USING dir, f;
            END IF;
        
            IF cur IS NOT NULL THEN
                flag := -2;
                fsize := 0;
                dbms_lob.createtemporary(text, true);
                LOOP
                    FETCH cur BULK COLLECT
                        INTO t1 LIMIT 1000;
                    EXIT WHEN t1.count = 0;
                    pos  := 0;
                    buff := '';
                    FOR i IN 1 .. t1.count LOOP
                        t1(i) := rtrim(regexp_replace(t1(i), '[' || chr(10) || chr(13) || ']+')) || chr(10);
                        pos := pos + length(t1(i));
                        buff:= buff||t1(i);
                        if pos >=25000 then
                            fsize := fsize + pos;
                            dbms_lob.writeappend(text, pos,buff);
                            pos := 0;
                            buff:= '';
                        end if;
                    END LOOP;
                    IF pos > 0 THEN
                        fsize := fsize + pos;
                        dbms_lob.writeappend(text, pos,buff);
                    END IF;
                    pos := fsize - startpos;
                    IF pos > MBs THEN
                        IF from_MB IS NULL OR startpos < from_MB THEN
                            pos := pos - MBs+1;
                            dbms_lob.createtemporary(tmptext, true);
                            dbms_lob.copy(tmptext,text,MBs,1,pos);
                            dbms_lob.freetemporary(text);
                            text:= tmptext;
                            startpos := fsize - MBs;
                        ELSE
                            MBs := pos;
                            EXIT;
                        END IF;
                    END IF;
                END LOOP;
                CLOSE cur;
            
                IF fsize > 0 THEN
                    IF from_MB IS NULL THEN
                        from_MB := fsize - MBs + 1;
                    END IF;
                    IF from_MB < 1 THEN
                        from_MB := 1;
                    ELSIF from_MB > fsize THEN
                        from_MB := fsize;
                    END IF;
                    MBs := least(MBs, fsize - from_MB + 1);
                END IF;
                
                tmp := 'File Size: > ' || round(fsize/1024/1024, 3) || ' MB        Extract Size: ' 
                        || round(length(text)/1024/1024, 3) ||' MB        Start Extract Position: ' 
                        || round(from_MB/1024/1024, 3) || ' MB';
                base64encode(text);
            END IF;
        END IF;
        :res := tmp;
        :2   := f;
        :3   := text;
    END;]]
    local target_view
    target_view=db:check_obj("GV$DIAG_TRACE_FILE",1)
    if not target_view then target_view=db:check_obj("V$DIAG_TRACE_FILE",1) end
    if not filename then
        if target_view and db.props.version>=12 then 
            target_view=target_view.target
            db:query([[SELECT * FROM(select ADR_HOME||regexp_substr(ADR_HOME,'[\\/]')||'trace'||regexp_substr(ADR_HOME,'[\\/]')||TRACE_FILENAME LAST_30_TRACE_FILES,CHANGE_TIME from ]]..target_view.." order by CHANGE_TIME desc) WHERE ROWNUM<=30")
        end
        env.checkhelp(filename)
    end 

    local traceoff=[[
    BEGIN
        EXECUTE IMMEDIATE 'alter session set events ''10053 trace name context off:10046 trace name context off''';
        @ALTER_SESSION@
        EXECUTE IMMEDIATE 'alter session set events ''sql_trace off:trace off''';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;]]

    if filename:lower()~="default" then
        traceoff=traceoff:gsub('@ALTER_SESSION@',[[
            EXECUTE IMMEDIATE 'alter session set tracefile_identifier=CLEANUP';
            EXECUTE IMMEDIATE 'alter session set tracefile_identifier=''''';]])
    else
        traceoff=traceoff:gsub('@ALTER_SESSION@','')
    end
    pcall(db.internal_call(db,traceoff))

    local lv=nil
    if filename:find("^%d+$") then lv=tonumber(filename) end
    if filename:lower()=="default" or lv then
        if lv then
            pcall(db.internal_call(db,"alter session set tracefile_identifier='dbcli_"..math.random(1e6).."'"));
        end
            if db.props.version>11 then
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
                pcall(db.internal_call(db,"alter session set events '10046 trace name context forever, level "..lv.."'"))
            else
                print("Trace off: "..filename)
            end
            return
        else
            pcall(db.internal_call(db,[[
                BEGIN
                    EXECUTE IMMEDIATE 'alter session set tracefile_identifier=CLEANUP';
                    EXECUTE IMMEDIATE 'alter session set tracefile_identifier=''''';
                EXCEPTION WHEN OTHERS THEN NULL;
                END;]]))
        end
    elseif filename:lower()=="alert" then
        if db.props.version<=11 then
            filename=db:get_value[[SELECT u_dump.value || '/alert_' || SYS_CONTEXT('userenv', 'instance_name') || '.log' "Trace File"
                                   FROM   v$parameter u_dump
                                   WHERE  u_dump.name = 'background_dump_dest']]
        else
            filename=db:get_value[[select value|| '/alert_' || SYS_CONTEXT('userenv', 'instance_name') || '.log' from v$diag_info where name='Diag Trace']]
        end
    elseif not filename:find('[\\/]') then
        if db.props.version<=11 then
            filename=db:get_value([[select value from v$parameter WHERE name = 'user_dump_dest']])..'/'..filename
        else
            env.checkerr(target_view and target_view.synonym,'Cannot access V$DIAG_TRACE_FILE to find the file!')
            filename=db:get_value([[select ADR_HOME||regexp_substr(ADR_HOME,'[\\/]')||'trace'||regexp_substr(ADR_HOME,'[\\/]')||TRACE_FILENAME from ]]..target_view.synonym.." WHERE TRACE_FILENAME='"..filename.."' AND ROWNUM<2")
            env.checkerr(filename,'Cannot find target file in %s!',target_view.synonym)
        end
    end

    local alert_view
    if filename:lower():find('alert.*.log') then
        alert_view=db:check_obj("V$DIAG_ALERT_EXT",1)
    end

    local args={filename,"#VARCHAR","#CLOB","#VARCHAR",target_view and target_view.synonym or '',alert_view and alert_view.synonym or '',mb=mb or 8,from_mb=from_mb or '',res='#VARCHAR',readonly=env.set.get("readonly")}
    db:internal_call(sql,args)
    env.checkerr(args[2],args[4])
    env.checkerr(args[3] and args[3]~='','Target file %s does not exists!',filename)
    print(args.res);
    args[3]=loader:Base64ZlibToText(args[3]:split('\n'));
    filename=env.write_cache(args[2],args[3])
    print("Result written to file "..filename)
    return filename,args[3]
end

function trace.onload()
    env.set_command(nil,{"loadtrace","dumptrace"},[[
        Download Oracle trace file into local directory. Usage: @@NAME {<trace_file|default|alert|0/1/4/8/12> [MB] [begin_MB]}
        This command *could* requires the "create directory" privilige.
        
        Parameters:
            trace_file: 1) The absolute path of the target trace file, or
                        2) "default" to extract current session's trace, or
                        4) 0/1/4/8/12 to enable 10046 trace with specific level
                        3) "alert" to extract local instance's alert log.
            MB        : MegaBytes to extract, default as 2 MB.
            begin_MB  : The start file position(in MB) to extract, default as "total_MB - <MB>"
        ]],trace.get_trace,false,4)
end

return trace