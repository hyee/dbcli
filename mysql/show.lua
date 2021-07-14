local env=env
local db=env.getdb()
local words,abbrs={
    'AUTHORS','BINARY','BINLOG','CHARACTER','CODE','COLLATION','COLUMNS','CONTRIBUTORS','CREATE',
    'DATABASE','DATABASES','ENGINE','ERRORS','EVENT','FROM','FULL','FUNCTION',
    'GLOBAL','GRANTS','HOSTS','INDEX','LIMIT','LOGS','MASTER','OPEN','PLUGINS','PRIVILEGES',
    'PROCEDURE','PROCESSLIST','PROFILE','SESSION','SLAVE','STATUS','STORAGE','TABLE',
    'TRIGGER','VARIABLES','VIEW','WARNINGS','LIKE','WHERE'}

local show={name="SHOW"}

function show.run(...)
    local args={...}
    env.checkhelp(args[1])
    db:assert_connect()
    local cmd={"SHOW"}
    env.set.set("printsize",10000)
    for i,k in ipairs(args) do
        cmd[#cmd+1]=i<3 and abbrs[k:upper()] or k
        local c=cmd[#cmd]:upper()
        if c=="VARIABLES" or c=="STATUS" or c=="COLLATION" then
            local text=(args[i+1] or ""):upper()
            if text~="" and not text:find("^LIKE") and not text:find("^WHERE") then
                if k:upper()=='VAR' or k:upper()=='STATUS' then
                    local vars=db:get_rows("SHOW SESSION "..c..";SHOW GLOBAL "..c)
                    local names={}
                    local rows={}
                    local key=args[i+1]:gsub('%%','.-'):lower()
                    for idx,dict in ipairs(vars) do
                        table.remove(dict,1)
                        for i,row in ipairs(dict) do
                            local name=row[1]
                            if name~='tidb_config' then
                                local rec=names[name:lower()]
                                if not rec then
                                    rec={name}
                                    names[name:lower()]=rec
                                    rows[#rows+1]=rec
                                end
                                if idx==1 then
                                    rec[2]=row[2]
                                else
                                    if row[2]==rec[2] then
                                        rec[3]='<same>'
                                    else
                                        rec[3]=row[2]
                                    end
                                end
                            end
                        end
                    end
                    for i=#rows,1,-1 do
                        local row=rows[i]
                        local found=false
                        for j=1,3 do
                            local val=row[j]
                            if not val then 
                                row[j]=''
                            else
                                if #val>50 and val:sub(1,128):find('=.-,') then
                                    row[j]=table.concat(val:split(' *, *'),',\n')
                                end
                                if val:lower():match(key) then 
                                    found=true
                                end
                            end
                        end
                        if not found then table.remove(rows,i) end
                    end
                    table.insert(rows,1,{"Variable Name","Session Value","Global Value"})
                    return grid.print(rows)
                end
                env.printer.set_grep(text)
                break
            end
        end
    end
    cmd=table.concat(cmd,' ')
    if cmd~="SHOW "..table.concat(args,' ') then print("Command: "..cmd) end
    db:query(cmd)
end

function show.help(...)
    return env.help.help_offline(table.concat({...}," "))
end

function show.onload()
    abbrs={}
    for _,k in ipairs(words) do
        abbrs[k:sub(1,2)],abbrs[k:sub(1,3)]=k,k
    end
    abbrs["TBS"]="TABLES"
    abbrs["EVS"]="EVENTS"
    abbrs["DBS"]="DATABASES"
    abbrs["ENS"]="ENGINES"
    abbrs["POS"]="PROFILES"
    abbrs["TRS"]="TRIGGERS"
    abbrs["CLT"]="COLLATION"
    env.set_command(nil,show.name, {"MySQL `SHOW` command. External Usage: @@NAME <VAR|STATUS> <keyword>",show.help},show.run,false,10)
end

return show