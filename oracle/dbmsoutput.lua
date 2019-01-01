local env,loader=env,loader
local snoop,cfg,default_db=env.event.snoop,env.set,env.db
local flag = 1

local output={}
local prev_transaction
local enabled='on'
local autotrace='off'
local default_args={enable=enabled,buff="#VARCHAR",txn="#VARCHAR",lob="#CLOB",con_name="#VARCHAR",con_id="#NUMBER",stats='#CURSOR'}
local prev_stats

function output.setOutput(db)
    local flag=cfg.get("ServerOutput")
    local stmt="begin dbms_output."..(flag=="on" and "enable(null)" or "disable()")..";end;"
    pcall(function() (db or env.getdb()):internal_call(stmt) end)
end

output.trace_sql=[[select /*INTERNAL_DBCLI_CMD*/ name,value from v$mystat natural join v$statname where value>0]]

output.stmt=[[/*INTERNAL_DBCLI_CMD*/
        DECLARE
            l_line   VARCHAR2(32767);
            l_done   PLS_INTEGER := 32767;
            l_max    PLS_INTEGER := 0;
            l_buffer VARCHAR2(32767);
            l_arr    dbms_output.chararr;
            l_lob    CLOB;
            l_enable VARCHAR2(3)  := :enable;
            l_trace  VARCHAR2(30) := :autotrace;
            l_sql_id VARCHAR2(15) := :sql_id;
            l_size   PLS_INTEGER;
            l_cont   varchar2(50);
            l_cid    PLS_INTEGER;
            l_stats  SYS_REFCURSOR;
            l_sep    varchar2(10) := chr(1)||chr(2)||chr(3)||chr(10); 
            procedure wr is
            begin
                l_size   := length(l_buffer);
                IF l_size + 255 > 30000 THEN
                    IF l_lob IS NULL THEN
                        dbms_lob.createtemporary(l_lob, TRUE);
                    END IF;
                    dbms_lob.writeappend(l_lob, l_size, l_buffer) ;
                    l_buffer := NULL;
                END IF;
            end;
        BEGIN
            --if l_trace not in ('sql_id','statistics','off') then
                open l_stats for select name,value from v$mystat natural join v$statname where value>0 order by name;
            --end if;
            dbms_output.get_lines(l_arr, l_done);
            IF l_enable = 'on' THEN
                FOR i IN 1 .. l_done LOOP
                    l_buffer := l_buffer || l_arr(i) || chr(10);
                    wr;
                END LOOP;
            END IF;

            IF l_trace NOT IN('off','statistics') THEN
                BEGIN
                    l_done := 0;
                    FOR r IN(SELECT * FROM TABLE(dbms_xplan.display('v$sql_plan_statistics_all',NULL,'ALLSTATS LAST','sql_id=''' || l_sql_id ||''''))) LOOP
                        l_done := l_done + 1;
                        if r.plan_table_output not like 'Error%' then
                            if l_done = 1 then
                                l_buffer := l_buffer || l_sep;
                            end if;
                            if trim(r.plan_table_output) is not null then
                                l_max := greatest(l_max,length(r.plan_table_output));
                                l_buffer := l_buffer || replace(r.plan_table_output,'Plan hash value:','SQL ID: '||l_sql_id||'   Plan hash value:') || chr(10);
                                wr;
                            end if;
                        elsif l_done = 1 then
                            l_buffer := l_buffer || 'SQL_ID: '||l_sql_id||chr(10);
                        end if;
                    END LOOP;
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            ELSIF l_trace='sql_id' THEN
                l_buffer := l_buffer || 'SQL_ID: '||l_sql_id||chr(10);
            END IF;

            if l_lob is not null and l_buffer is not null then
                dbms_lob.writeappend(l_lob, length(l_buffer), l_buffer) ;
                l_buffer := null;
            end if;

            if l_max > 0 then
                l_buffer := replace(l_buffer,l_sep,rpad('=',l_max,'=')||chr(10));
                l_lob := replace(l_lob,l_sep,rpad('=',l_max,'=')||chr(10));
            end if;

            $IF dbms_db_version.version > 11 $THEN 
                l_cont:=sys_context('userenv', 'con_name'); 
                l_cid :=sys_context('userenv', 'con_id'); 
            $END
            :buff    := l_buffer;
            :txn     := dbms_transaction.local_transaction_id;
            :con_name := l_cont;
            :con_id  := l_cid;
            :lob     := l_lob;
            :stats   := l_stats;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;]]

local DML={SELECT=1,WITH=1,UPDATE=1,DELETE=1,MERGE=1}
function output.getOutput(item)
    local db,sql=item[1],item[2]
    if not db or not sql then return end
    local typ=db.get_command_type(sql)
    if DML[typ] and #env.RUNNING_THREADS > 2 and autotrace=='off' then return end
    if not (sql:lower():find('internal',1,true) and not sql:find('%s')) and not db:is_internal_call(sql) then
        local args=table.clone(default_args)
        args.sql_id=output.LAST_SQL_ID
        args.autotrace=autotrace
        local done,err=pcall(db.exec_cache,db,output.stmt,args,'Internal_GetDBMSOutput')
        if not done then 
            return print(err) 
        end
        if autotrace =='traceonly' or autotrace=='on' or autotrace=='statistics' then
            local stats=db:compute_delta(args.stats,output.prev_stats,'1','2')
            local rows=env.grid.new()
            rows:add{"Value","Name",'|',"Value","Name"}
            local n={}
            local counter=0
            for k,row in ipairs(stats) do
                if tonumber(row[2]) and tonumber(row[2])>0 then
                    counter=counter+1
                    local idx=math.fmod(counter-1,2)*3
                    if idx==3 then 
                        n[3]='|' 
                        rows:add(n)
                        n={}
                    end
                    n[idx+1],n[idx+2]=row[2],row[1]
                end
            end
            if #n>0 then rows:add(n) end
            rows:print()
        end

        local result=args.lob or args.buff
        if enabled == "on" and result and result:match("[^\n%s]+") then
            result=result:gsub("\r\n","\n"):gsub("%s+$","")
            if result~="" then print(result) end
        end

        db.props.container=args.cont
        db.props.container_id=args.con_id
        local title={args.con_name and ("Container: "..args.con_name..'('..args.con_id..')')}
        if args.txn and cfg.get("READONLY")=="on" then
            db:rollback()
            env.raise("DML in read-only mode is disallowed, transaction is rollbacked.")
        end
        title[#title+1]=args.txn and ("TXN_ID: "..args.txn)
        title=table.concat(title,"   ")
        if prev_transaction~=title then
            prev_transaction=title
            env.set_title(title)
        end
        
    end
    output.prev_sql=sql
end

function output.getSQLID(info)
    local db,sql=info[1],info[2]
    if sql and not (sql:lower():find('internal',1,true) and not sql:find('%s')) and not db:is_internal_call(sql) then
        output.LAST_SQL_ID=loader:computeSQLIdFromText(sql)
        if autotrace =='traceonly' or autotrace=='on' or autotrace=='statistics' then
            local done,result=pcall(db.exec_cache,db,output.trace_sql,{},'Internal_GetSQLSTATS')
            if done then 
                output.prev_stats=result
            end
        end
    end
end

function output.get_error_output(info)
    if info.db:is_connect() then
        output.getOutput({info.db,info.sql})
    end
    return info
end

function output.onload()
    snoop("ON_SQL_ERROR",output.get_error_output,nil,40)
    snoop("AFTER_ORACLE_CONNECT",output.setOutput)
    snoop("BEFORE_DB_EXEC",output.getSQLID,nil,50)
    snoop("AFTER_DB_EXEC",output.getOutput,nil,50)
    cfg.init('AUTOTRACE','off',function(name,value)
        autotrace=value
        return value
    end,'oracle','Automatically get a report on the execution path used by the SQL optimizer and the statement execution statistics',
    'on,off,explain,statistics,traceonly,sql_id')

    cfg.init({"ServerOutput",'SERVEROUT'},
        "on",
        function(name,value)
            enabled=value
            return value
        end,
        "oracle",
        "Print Oracle dbms_output after each execution",
        "on,off")
end

return output