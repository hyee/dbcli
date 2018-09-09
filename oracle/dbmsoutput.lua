local env=env
local snoop,cfg,default_db=env.event.snoop,env.set,env.db
local flag = 1

local output={}
local prev_transaction
local enabled='on'
local default_args={enable=enabled,buff="#VARCHAR",txn="#VARCHAR",lob="#CLOB",con_name="#VARCHAR",con_id="#NUMBER"}

function output.setOutput(db)
    local flag=cfg.get("ServerOutput")
    local stmt="begin dbms_output."..(flag=="on" and "enable(null)" or "disable()")..";end;"
    pcall(function() (db or env.getdb()):internal_call(stmt) end)
end

output.stmt=[[/*INTERNAL_DBCLI_CMD*/
        DECLARE
            l_line   VARCHAR2(32767);
            l_done   PLS_INTEGER := 32767;
            l_buffer VARCHAR2(32767);
            l_arr    dbms_output.chararr;
            l_lob    CLOB;
            l_enable VARCHAR2(3) := :enable;
            l_size   PLS_INTEGER;
            l_cont   varchar2(50);
            l_cid    PLS_INTEGER;
        BEGIN
            dbms_output.get_lines(l_arr, l_done);
            IF l_enable = 'on' THEN
                FOR i IN 1 .. l_done LOOP
                    l_buffer := l_buffer || l_arr(i) || chr(10);
                    l_size   := length(l_buffer);
                    IF l_size + 255 > 30000 OR (l_lob IS NOT NULL AND l_buffer IS NOT NULL AND i = l_done) THEN
                        IF l_lob IS NULL THEN
                            dbms_lob.createtemporary(l_lob, TRUE);
                        END IF;
                        dbms_lob.writeappend(l_lob, l_size, l_buffer) ;
                        l_buffer := NULL;
                    END IF;
                END LOOP;
            END IF;
            $IF dbms_db_version.version > 11 $THEN 
                l_cont:=sys_context('userenv', 'con_name'); 
                l_cid :=sys_context('userenv', 'con_id'); 
            $END
            :buff    := l_buffer;
            :txn     := dbms_transaction.local_transaction_id;
            :con_name := l_cont;
            :con_id  := l_cid;
            :lob     := l_lob;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;]]

function output.getOutput(item)
    local db,sql=item[1],item[2]
    if not db or not sql then return end
    local typ=db.get_command_type(sql)
    if (typ=='SELECT' or typ=='WITH') and #env.RUNNING_THREADS>2 then return end
    if not (sql:lower():find('internal',1,true) and not sql:find('%s')) and not db:is_internal_call(sql) then
        local args=table.clone(default_args)
        if not pcall(db.exec_cache,db,output.stmt,args,'Internal_GetDBMSOutput') then return end

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


function output.get_error_output(info)
    if info.db:is_connect() then
        output.getOutput({info.db,info.sql})
    end
    return info
end

function output.onload()
    snoop("ON_SQL_ERROR",output.get_error_output,nil,40)
    snoop("AFTER_ORACLE_CONNECT",output.setOutput)
    snoop("AFTER_DB_EXEC",output.getOutput,nil,50)

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