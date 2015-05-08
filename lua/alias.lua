local env,globalcmds=env,env._CMDS
local alias={command_dir=env.WORK_DIR.."aliases"..env.PATH_DEL,cmdlist={}}
alias.db_dir=alias.command_dir
local comment="(.-)[\n\r\b\t%s]*$"

function alias.rehash()
    for k,v in pairs(alias.cmdlist) do
        if v.active then 
            globalcmds[k]=nil
            env.remove_command(k)
        end
    end
    
    alias.cmdlist={}
    for k,v in ipairs(env.list_dir(alias.command_dir,"alias",comment)) do
        if(v[2]:lower()==(alias.command_dir..v[1]..'.alias'):lower()) then
            alias.set(v[1],v[3],false)
        end
    end

    if alias.db_dir~=alias.command_dir then
        for k,v in ipairs(env.list_dir(alias.db_dir,"alias",comment)) do
            if(v[2]:lower()==(alias.db_dir..v[1]..'.alias'):lower()) then
                alias.set(v[1],v[3],false)
            end
        end
    end
end

function alias.parser(s,default_value)
    if s~="*" then
        local v=tonumber(s)
        if not alias.args[v] and default_value then alias.args[v]=default_value end
        if v<1 or v>9 or not alias.args[v] then return ("$"..s)..(default_value and '['..default_value..']' or '') end
        alias.rest[v]=""
        return alias.args[v]
    else
        local res= table.concat(alias.rest," ")
        alias.rest={}
        return res
    end
end

function alias.run_command(...)
    local name=env.CURRENT_CMD
    name=name:upper()    
    if alias.cmdlist[name] then
        local target=alias.cmdlist[name].text
        if type(target)=="function" then target=target(alias) end
        target=target.." $*"
        alias.args={...}
        alias.rest={}
        for i,v in ipairs(alias.args) do
            v=v or ""
            if v:find("[%s\n\r\b\t]") and not v:find('"') then v='"'..v..'"' end
            alias.args[i]=v
            alias.rest[i]=v
        end
        target=target:gsub("%$(%d+)%[(.-)%]",alias.parser)
        target=target:gsub("%$([%d%*]+)",alias.parser)
        target=target:gsub("'%$[1-9]'",''):gsub("%$[1-9]",''):gsub("[%s\n\r\b\t]+$","")
        if not target:find(env.END_MARKS[2]..'$') and not target:find(env.END_MARKS[1]..'$') then target=target..env.END_MARKS[1] end
        if type(alias.cmdlist[name].text) == "string" and not target:find('[\n\r]') then
            print('$ '..target)
        end

        env.internal_eval(target)     
    end
end

function alias.set(name,cmd,write)
    if not name and write~=false then
        return exec_command("HELP",{"ALIAS"})
    end

    name=name:upper()

    if name=="-R" then 
        return alias.rehash() 
    elseif name=="-E" and cmd then
        local text=alias.cmdlist[cmd:upper()]
        if not text then
            return print("Error: Cannot find this alias :"..cmd)
        end
        if type(text.text)=="function" then
            return print("Error: Command has been encrypted: "..cmd)
        end
        local  du = 1
        alias.set(cmd,packer.unpack_str(text.text))        
    elseif not cmd then
        if not alias.cmdlist[name] then return end
        if alias.cmdlist[name].active then 
            globalcmds[name]=nil
            env.remove_command(name)
        end    
        alias.cmdlist[name]=nil        
        os.remove(alias.command_dir..name:lower()..".alias")
        os.remove(alias.db_dir..name:lower()..".alias")
        print('Alias "'..name..'" is removed.')
    else
        if not name:match("^[%w_]+$") then
            return print("Alias '"..name.."' is invalid. ")
        end

        local target_dir=alias.command_dir
        local sub_cmd=env.parse_args(2,cmd)[1]:upper()
        if env._CMDS[sub_cmd] then
            local file=env._CMDS[sub_cmd].FILE or ""
            file=file:match('[\\/]([^#]+)')
            if file==env.CURRENT_DB then target_dir=alias.db_dir end
        end

        if write ~= false then
            os.remove(alias.command_dir..name:lower()..".alias")
            os.remove(alias.db_dir..name:lower()..".alias")
            local f=io.open(target_dir..name:lower()..".alias","w")
            f:write(cmd)
            f:close()
        end
        
        if not alias.cmdlist[name] then             
            alias.cmdlist[name]={}
        end

        local desc
        if cmd:sub(1,5)~="FUNC:" then
            desc=cmd:gsub("[\n\r]+[%s\t]*"," "):sub(1,300)
        else
            cmd=packer.unpack(cmd)
            desc=cmd
        end
        if type(desc)=="string" then desc=desc:gsub(env.END_MARKS[1]..'+$','')  end
        alias.cmdlist[name].desc=desc
        alias.cmdlist[name].text=cmd
        alias.cmdlist[name].active=false
        if not globalcmds[name]  then
            env.set_command(nil,name, "#Alias command("..sub_cmd..")",alias.run_command,false,99,false,true)
            alias.cmdlist[name].active=true
        elseif globalcmds[name].FUNC==alias.run_command then
            alias.cmdlist[name].active=true
        end
    end
end

function alias.helper()
    local help=[[
    Set a shortcut of other existing commands. Usage: alias [-r | <name> [parameters] | -e <alias name>]
    1) Set/modify alias: alias <name> <command>. Available wildchars: $1 - $9, or $*
    2) Remove alias    : alias <name>
    3) Reload alias    : alias -r
    4) Encrypt alias   : alias -e <alias name>

    All aliases are permanently stored in the "aliases" folder.
    Example:
         aliase test pro $1
         aliase test conn $1/$2@$3
    Current aliases:
    ================]]
    local grid,rows=env.grid,{{"Name","Active?","Command"}}
    local active
    for k,v in pairs(alias.cmdlist) do
        if not env._CMDS[k]['FILE']:match("alias") then 
            active='No'
        else
            active='Yes'
        end
        alias.cmdlist[k].active=active
        table.insert(rows,{k,active,tostring(alias.cmdlist[k].desc)})
    end
    grid.sort(rows,1,true)
    for _,k in ipairs(grid.format(rows)) do
        help=help..'\n'..k
    end
    return help
end

function alias.load_db_aliases(db_name)
    alias.db_dir=alias.command_dir..db_name..env.PATH_DEL
    env.host.mkdir(alias.db_dir)
    alias.rehash()
end

function alias.onload()
    --alias.rehash()
    env.event.snoop('ON_ENV_LOADED',alias.rehash,nil,1)
    env.event.snoop('ON_DATABASE_ENV_LOADED',alias.load_db_aliases,nil,1)
    env.set_command(nil,"alias", alias.helper,alias.set,'__SMART_PARSE__',3)
end

return alias