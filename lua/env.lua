--init a global function to store CLI variables
local _G = _ENV or _G

local reader,coroutine,os,string,table,math,io=reader,coroutine,os,string,table,math,io

local getinfo, error, rawset, rawget,math = debug.getinfo, error, rawset, rawget,math
--[[
local global_vars,global_source,env={},{},{}
_G['env']=env
local global_meta=getmetatable(_G) or {}
function global_meta.__newindex(self,key,value) rawset(global_vars,key,value) end
function global_meta.__index(self,key) return rawget(global_vars,key) or rawget(_G,key) end
function global_meta.__newindex(self,key,value) rawset(global_vars,key,value) end
function global_meta.__pairs(self) return pairs(global_vars) end
global_meta.__call=global_meta.__newindex

debug.setmetatable(env,global_meta)
setmetatable(_G,global_meta)
--]]


local env=setmetatable({},{
    __call =function(self, key, value)
            rawset(self,key,value)
            _G[key]=value
        end,
    __index=function(self,key) return _G[key] end,
    __newindex=function(self,key,value) self(key,value) end
})
_G['env']=env

local mt = getmetatable(_G)

if mt == nil then
    mt = {}
    setmetatable(_G, mt)
end

mt.__declared = {}

mt.__newindex = function (t, n, v)
    if not mt.__declared[n] and env.WORK_DIR then
        rawset(mt.__declared, n,env.callee())
    end
    rawset(t, n, v)
end

env.globals=mt.__declared


local function abort_thread()
    if coroutine.running () then
        debug.sethook()
        --print(env.CURRENT_THREAD)
        --print(debug.traceback())
    end
end

_G['TRIGGER_ABORT']=function()
    env.safe_call(env.event and env.event.callback,5,"ON_COMMAND_ABORT")
end



local dbcli_stack,dbcli_cmd_history={level=0,id=0},{}
local dbcli_current_item,dbcli_last_id=dbcli_stack,dbcli_stack.id
env.__DBCLI__STACK,env.__DBCLI__CMD_HIS=dbcli_stack,dbcli_cmd_history
local function push_stack(cmd)
    local item,callee
    if type(cmd)~="boolean" then --stack end
        item,callee={},env.callee(4)
        for k,v in pairs(dbcli_current_item) do
            if type(k) ~="number" then item[k]=v end
        end
        item.closed,item.last=nil
        dbcli_last_id=dbcli_last_id+1
        item.clock,item.command,item.callee,item.parent,item.level,item.id=os.clock(),cmd,callee,dbcli_current_item,dbcli_current_item.level+1,dbcli_last_id
        item.parent[item.id],dbcli_current_item=item,item
        dbcli_stack.last=item
    else
        item,callee=dbcli_current_item,env.callee()
        dbcli_current_item=item.parent or dbcli_stack
        item.closer,item.parent,item.clock=callee,nil,os.clock()-item.clock
        dbcli_current_item[item.id],dbcli_stack.closed=nil,item
    end
end

local function push_history(cmd)
    cmd=cmd:gsub("%s+"," "):gsub("^%+",""):sub(1,200)
    dbcli_cmd_history[#dbcli_cmd_history+1]=("%d: %s%s"):format(dbcli_current_item.level, string.rep("   ",dbcli_current_item.level-1),cmd)
    while #dbcli_cmd_history>1000 do
        table.remove(dbcli_cmd_history,1)
    end
end

function env.print_stack()
    local stack=table.concat({"CURRENT_ID:",dbcli_current_item.id,"   CURRENT_LEVEL:",dbcli_current_item.level,"   CURRENT_COMMAND:",dbcli_current_item.command}," ")
    stack=stack..'\n'..table.dump(dbcli_stack)
    stack=stack..'\n'.."Historical Commands:\n===================="
    stack=stack..'\n'..table.concat(dbcli_cmd_history,'\n')
    print(stack)
end

--Build command list
env._CMDS=setmetatable({___ABBR___={}},{
    __index=function(self,key)
        if not key then return nil end
        local abbr=rawget(self,'___ABBR___')
        local value=rawget(abbr,key)
        return value and rawget(abbr,value) or value
    end,

    __newindex=function(self,key,value)
        local abbr=rawget(self,'___ABBR___')
        if not key then return end
        if rawget(abbr,key) then
            if type(value)=="table" then
                rawset(abbr,key,value)
            else
                local cmd=rawget(abbr,key)
                rawset(abbr,key,value)
                if type(cmd)=="string" then
                    for k,v in pairs(abbr) do
                        if v==cmd then rawset(abbr,k,value) end
                    end
                end
            end
        else
            rawset(self,key,value)
        end
    end,

    __pairs=function(self)
        local p,abbr={},rawget(self,'___ABBR___')
        for k,v in pairs(abbr) do
            if not abbr[v] then p[k]=v end
        end
        return pairs(p)
    end
})

--
env.space="    "
local _CMDS=env._CMDS
function env.list_dir(file_dir,file_ext,text_macher)
    local dir
    local keylist={}

    local filter=file_ext and "*."..file_ext or "*"
    file_dir=file_dir:gsub("[\\/]+",env.PATH_DEL)
    if env.OS=="windows" then
        dir=io.popen('dir /B/S/A:-D "'..file_dir..'" 2>nul & dir /B/S/A:-D "'..file_dir..'.'..file_ext..'" 2>nul')
    else
        dir=io.popen('find "'..file_dir..'" -iname '..filter..' -print')
    end

    for n in dir:lines() do
        local name,ext=n:match("([^\\/]+)$")
        if file_ext then
            name,ext=name:match("(.+)%.(%w+)$")
            if ext:upper()~=file_ext:upper() and file_ext~="*" then name=nil end
        end
        if name and name~="" then
            local comment
            if  text_macher then
                local f=io.open(n)
                if f then
                    local txt=f:read("*a")
                    f:close()
                    if type(text_macher)=="string" then
                        comment=txt:match(text_macher) or ""
                    elseif type(text_macher)=="function" then
                        comment=text_macher(txt) or ""
                    end
                end
            end
            keylist[#keylist+1]={name,n,comment}
        end
    end
    return keylist
end

function env.file_type(file_name)
    local result=os.execute('dir /B "'..file_name..'" 1>nul 2>nul')
    --file not exists
    if result ~= true then return nil end
    --is file
    result=os.execute('dir /B /A:D "'..file_name..'" 1>nul 2>nul')
    if result then return 'folder' end
    return 'file'
end

local previous_prompt
function env.set_subsystem(cmd,prompt)
    if cmd~=nil then
        env.set_prompt(cmd,prompt or cmd,false,9)
        env._SUBSYSTEM=cmd
    else
        env.set_prompt(cmd,nil,false,9)
        env._SUBSYSTEM,_G._SUBSYSTEM=nil,nil
    end
end

function env.check_cmd_endless(cmd,other_parts)
    if not _CMDS[cmd] then
        return true,other_parts
    end
    local p1=env.END_MARKS[1]..'%s*$'
    if not _CMDS[cmd].MULTI then
        return true,other_parts and other_parts:gsub(p1,"")
    elseif type(_CMDS[cmd].MULTI)=="function" then
        return _CMDS[cmd].MULTI(cmd,other_parts)
    elseif _CMDS[cmd].MULTI=='__SMART_PARSE__' then
        return env.smart_check_endless(cmd,other_parts,_CMDS[cmd].ARGS)
    end


    local p2=env.END_MARKS[2]..'%s*$'
    local match = (other_parts:match(p1) and 1) or (other_parts:match(p2) and 2) or false
    --print(match,other_parts)
    if not match then
        return false,other_parts
    end
    return true,other_parts:gsub(match==1 and p1 or p2,"")
end

function env.smart_check_endless(cmd,rest,from_pos)
    local args=env.parse_args(from_pos,rest)
    if not args[from_pos-1] then return true,rest:gsub('['..env.END_MARKS[1]..' \t]+$',"") end
    if env.check_cmd_endless(args[from_pos-1]:upper(),args[from_pos] or "") then
        return true,rest:gsub('%s+$',"")
    else
        return false,rest
    end
end

function env.set_command(obj,cmd,help_func,call_func,is_multiline,paramCount,dbcmd,allow_overriden)
    local abbr={}

    if not paramCount then
        env.raise("Incompleted command["..cmd.."], number of parameters is not defined!")
    end

    if type(cmd)~="table" then cmd={cmd} end
    local tmp=cmd[1]:upper()

    for i=1,#cmd do
        cmd[i]=cmd[i]:upper()
        if _CMDS[cmd[i]] then
            if _CMDS[cmd[i]].ISOVERRIDE~=true then
                env.raise("Command '"..cmd[i].."' is already defined in ".._CMDS[cmd[i]]["FILE"])
            else
                _CMDS[cmd[i]]=nil
            end
        end
        if i>1 then table.insert(abbr,cmd[i]) end
    end

    for i=1,#cmd do _CMDS.___ABBR___[cmd[i]]=tmp  end

    cmd=tmp

    local src=env.callee()
    local desc=help_func
    local args= obj and {obj,cmd} or {cmd}
    if type(help_func) == "function" then
        desc=help_func(table.unpack(args))
    end

    if type(desc)=="string" then
        desc = desc:gsub("^%s*[\n\r]+","")
        desc = desc:match("([^\n\r]+)")
    elseif desc then
        print(cmd..': Unexpected command definition, the description should be a function or string, but got '..type(desc))
        desc=nil
    end

    _CMDS[cmd]={
        OBJ       = obj,          --object, if the connected function is not a static function, then this field is used.
        FILE      = src,          --the file name that defines & executes the command
        DESC      = desc,         --command short help without \n
        HELPER    = help_func,    --command detail help, it is a function
        FUNC      = call_func,    --command function
        MULTI     = is_multiline,
        ABBR      = table.concat(abbr,','),
        ARGS      = paramCount,
        DBCMD     = dbcmd,
        ISOVERRIDE= allow_overriden
    }
end

function env.remove_command(cmd)
    cmd=cmd:upper()
    if not _CMDS[cmd] then return end
    local src=env.callee()
    --if src:gsub("#%d+","")~=_CMDS[cmd].FILE:gsub("#%d+","") then
    --    env.raise("Cannot remove command '%s' from %s, it was defined in file %s!",cmd,src,_CMDS[cmd].FILE)
    --end

    _CMDS[cmd]=nil
    for k,v in pairs(_CMDS.___ABBR___) do
        if(v==cmd) then _CMDS.___ABBR___[k]=nil end
    end
end

function env.callee(idx)
    if type(idx)~="number" then idx=3 end
    local info=getinfo(idx)
    if not info then return nil end
    local src=info.short_src
    if src:lower():find(env.WORK_DIR:lower(),1,true) then
        src=src:sub(#env.WORK_DIR+1)
    end
    return src:gsub("%.%w+$","#"..info.currentline)
end

function env.format_error(src,errmsg,...)
    errmsg=(tostring(errmsg) or ""):gsub('^.*%s([^%: ]+Exception%:%s*)','%1')
        :gsub(".*[IS][OQL]+Exception:%s*","")
            :gsub("^.*000%-00000%:%s*","")
                :gsub("%s+$","")
    if src then
        local name,line=src:match("([^\\/]+)%#(%d+)$")
        if name then
            name=name:upper():gsub("_",""):sub(1,3)
            errmsg='000-00000:'..name.."-"..string.format("%05i",tonumber(line))..": "..errmsg
        end
    end
    if select('#',...)>0 then errmsg=errmsg:format(...) end
    return errmsg
end

function env.warn(...)
    local str,count=env.format_error(nil,...):gsub("[^\n\r]*(%u%u%u+%-[^\n\r]*)",'%1')
    print(env.ansi and env.ansi.mask('HIR',str) or str)
end

function env.raise(...)
    local str=env.format_error(env.callee(),...)
    return error(str)
end

function env.raise_error(...)
    local str=env.format_error(nil,...)
    return error('000-00000:'..str)
end

function env.checkerr(result,msg,...)
    if not result then
        local str=env.format_error(env.callee(),msg,...)
        return error(str)
    end
end

local writer=writer
function env.exec_command(cmd,params)
    local result
    local name=cmd:upper()
    cmd=_CMDS[cmd]
    local stack=table.concat(params," ")
    if not cmd then
        return print("No such comand["..name.." "..stack.."]!")
    end
    stack=(cmd.ARGS==1 and stack or name.." "..stack)
    push_history(stack)
    if not cmd.FUNC then return end
    env.CURRENT_CMD=name
    local _,isMain=coroutine.running()


    local event=env.event and env.event.callback
    if event then
        event("BEFORE_COMMAND",name,params)
        if isMain then
            event("BEFORE_ROOT_COMMAND",name,params)
            env.CURRENT_ROOT_CMD=name
        end
    end

    local args= cmd.OBJ and {cmd.OBJ,table.unpack(params)} or {table.unpack(params)}

    local funs=type(cmd.FUNC)=="table" and cmd.FUNC or {cmd.FUNC}
    for _,func in ipairs(funs) do
        if writer then
            writer:print(env.ansi.mask("NOR",""))
            writer:flush()
        end

        local co=coroutine.create(func)
        local res={coroutine.resume(co,table.unpack(args))}

        --local res = {pcall(func,table.unpack(args))}
        if not res[1] then
            result=res
            env.warn(res[2])
        elseif not result then
            result=res
        end
    end

    if event then
        if not env.IS_INTERNAL_EVAL then event("AFTER_SUCCESS_COMMAND",name,params,result[1]) end
        if isMain then event("AFTER_ROOT_COMMAND",name,params,result[1]) end
    end
    env.IS_INTERNAL_EVAL=false
    if not isMain and not result[1] then error('000-00000:') end
    return table.unpack(result)
end

local is_in_multi_state=false
local curr_stmt=""
local multi_cmd

local cache_prompt,fix_prompt

local prompt_stack={_base="SQL"}

function env.set_prompt(class,default,is_default,level)
    if not env._SUBSYSTEM and default then
        default=default:upper()
    elseif default then
        default=default--:gsub(".*[\27\33].-%a","")
    end
    class=class or "default"
    level=level or (class=="default" or default==prompt_stack._base) and 0 or 3
    if prompt_stack[class] and prompt_stack[class]>level then prompt_stack[prompt_stack[class]]=nil end
    prompt_stack[level],prompt_stack[class]=default,level

    for i=9,0,-1 do
        if prompt_stack[i] then
            default=prompt_stack[i]
            break
        end
    end

    if default and not default:match("[%w]%s*$") then 
        env.PRI_PROMPT=default 
    else
        env.PRI_PROMPT=(default or "").."> "
    end
    env.CURRENT_PROMPT,env.MTL_PROMPT=env.PRI_PROMPT,(" "):rep(#env.PRI_PROMPT)
    return default
end

function env.pending_command()
    return curr_stmt and curr_stmt~=""
end

function env.clear_command()
    if env.pending_command() then
        multi_cmd,curr_stmt=nil,nil
        env.CURRENT_PROMPT=env.PRI_PROMPT
    end
    local prompt=env.PRI_PROMPT

    if env.ansi then
        local prompt_color="%s%s"..env.ansi.get_color("NOR").."%s"
        prompt=prompt_color:format(env.ansi.get_color("PROMPTCOLOR"),prompt,env.ansi.get_color("COMMANDCOLOR"))
    end
    env.reader:resetPromptLine(prompt,"",0)
    env.reset_input("")
end

function env.parse_args(cmd,rest)
    --deal with the single-line commands
    local arg_count
    if type(cmd)=="number" then
        arg_count=cmd+1
    else
        if not cmd then
            cmd,rest=rest:match('([^%s'..env.END_MARKS[1]..']+)%s*(.*)')
            cmd = cmd and cmd:upper() or "_unknown_"
        end
        env.checkerr(_CMDS[cmd],'Unknown command "'..cmd..'"!')
        arg_count=_CMDS[cmd].ARGS
    end

    local args={}
    if arg_count == 1 then
        args[#args+1]=cmd..(rest:len()> 0 and (" "..rest) or "")
    elseif arg_count == 2 then
        args[#args+1]=rest
    elseif rest then
        local piece=""
        local quote='"'
        local is_quote_string = false
        for i=1,#rest,1 do
            local char=rest:sub(i,i)
            if is_quote_string then--if the parameter starts with quote
                if char ~= quote then
                    piece = piece .. char
                elseif (rest:sub(i+1,i+1) or " "):match("^%s*$") then
                    --end of a quote string if next char is a space
                    args[#args+1]=(piece..char):gsub('^"(.*)"$','%1')
                    piece,is_quote_string='',false
                else
                    piece=piece..char
                end
            else
                if char==quote then
                    --begin a quote string, if its previous char is not a space, then bypass
                    is_quote_string,piece = true,piece..quote
                elseif not char:match("(%s)") then
                    piece = piece ..char
                elseif piece ~= '' then
                    args[#args+1],piece=piece,''
                end
            end
            if #args>=arg_count-2 then--the last parameter
                piece=rest:sub(i+1):gsub("^(%s+)",""):gsub('^"(.*)"$','%1')
                args[#args+1],piece=piece,''
                break
            end
        end
        --If the quote is not in couple, then treat it as a normal string
        if piece:sub(1,1)==quote then
            for s in piece:gmatch('(%S+)') do
                args[#args+1]=s
            end
        elseif piece~='' then
            args[#args+1]=piece
        end
    end

    for i=#args,1,-1 do
        if args[i]=="" then table.remove(args,i) end
        break
    end
    return args,cmd
end

function env.force_end_input()
    if curr_stmt then
        local stmt={multi_cmd,env.parse_args(multi_cmd,curr_stmt)}
        multi_cmd,curr_stmt=nil,nil
        env.CURRENT_PROMPT=env.PRI_PROMPT
        if exec~=false then
            env.exec_command(stmt[1],stmt[2])
        else
            push_stack(false)
            return stmt[1],stmt[2]
        end
    end
    push_stack(false)
    multi_cmd,curr_stmt=nil,nil
    return
end

function env.eval_line(line,exec)
    if type(line)~='string' or line:gsub('%s+','')=='' then return end
    local subsystem_prefix=""
    --Remove BOM header
    if not env.pending_command() then
        push_stack(line)
        subsystem_prefix=env._SUBSYSTEM and (env._SUBSYSTEM.." ") or ""
        if dbcli_current_item.skip_subsystem then
            subsystem_prefix=""
        elseif #subsystem_prefix>0 then
            if line:lower():find(subsystem_prefix:lower(),1,true)== 1 then
                subsystem_prefix=""
            else
                local cmd=env.parse_args(2,line)[1]
                if cmd:len()>1 and cmd:sub(1,1)=='.' and _CMDS[cmd:upper():sub(2)] then
                    subsystem_prefix=""
                    dbcli_current_item.skip_subsystem=true
                end
            end
        end
        line=(subsystem_prefix..line:gsub("^%.","",1)):gsub('^[%z\128-\255 \t]+','')
        if line:match('^([^%w])') then
            local cmd=""
            for i=math.min(#line,5),1,-1 do
                cmd=line:sub(1,i)
                if _CMDS[cmd] then
                    if #line>i and not line:sub(i+1,i+1):find('%s') then
                        line=cmd..' '..line:sub(i+1)
                    end
                    break
                end
            end
        end
    end

    local done
    local function check_multi_cmd(lineval)
        curr_stmt = curr_stmt ..lineval
        done,curr_stmt=env.check_cmd_endless(multi_cmd,curr_stmt)
        if done then
            return env.force_end_input()
        end
        curr_stmt = curr_stmt .."\n"
        return multi_cmd
    end

    if multi_cmd then return check_multi_cmd(line) end

    local cmd,rest=line:match('^%s*([^ \t]+)[ \t]*(.*)')
    if not cmd then return end
    cmd=subsystem_prefix=="" and cmd:gsub(env.END_MARKS[1]..'+$',''):upper() or cmd
    env.CURRENT_CMD=cmd
    if not (_CMDS[cmd]) then
        push_stack(false)
        return print("No such command["..cmd.."], please type 'help' for more information.")
    elseif _CMDS[cmd].MULTI then --deal with the commands that cross-lines
        multi_cmd=cmd
        env.CURRENT_PROMPT=env.MTL_PROMPT
        curr_stmt = ""
        return check_multi_cmd(rest)
    end

    --print('Command:',cmd,table.concat (args,','))
    rest=subsystem_prefix=="" and rest:gsub("["..env.END_MARKS[1].."%s]+$","") or rest
    local args=env.parse_args(cmd,rest)

    if exec~=false then
        env.exec_command(cmd,args,local_stack)
        push_stack(false)
    else
        push_stack(false)
        return cmd,args
    end
end

function env.internal_eval(line,exec)
    env.IS_INTERNAL_EVAL=true
    env.eval_line(line,exec)
    env.IS_INTERNAL_EVAL=false
end

function env.testcmd(...)
    local args,cmd={...}
    for k,v in pairs(args) do
        if v:find(" ") and not v:find('"') then
            args[k]='"'..v..'"'
        end
    end
    cmd,args=env.eval_line(table.concat(args,' ')..env.END_MARKS[1],false)
    if not cmd then return end
    print("Command    : "..cmd.."\nParameters : "..#args..' - '..(_CMDS[cmd].ARGS-1).."\n============================")
    for k,v in ipairs(args) do
        print(string.format("%-2s = %s",k,v))
    end
end

function env.safe_call(func,...)
    if not func then return end
    local res,rtn=pcall(func,...)
    if not res then
        return env.warn(tostring(rtn):gsub(env.WORK_DIR,""))
    end
    return rtn
end

function env.set_endmark(name,value)
    if value:gsub('\\[nrt]',''):match('[%w]') then return print('Cannot be alphanumeric characters. ') end;
    value=value:gsub("\\+",'\\')
    local p1=value:sub(1,1)
    local p2=value:sub(2):gsub('\\(%w)',function(s)
        return s=='n' and '\n[ \t]*' or s=='r' and '\r[ \t]*' or s=='t' and '\t[ \t]*' or '\\'..s
    end) or p1

    env.END_MARKS={p1,p2}
    return value
end

local end_marks=(";\\n/"):gsub("\\+",'\\')
env.set_endmark(nil,end_marks)

function env.check_comment(cmd,other_parts)
    print(cmd,other_parts)
    if not other_parts:find("*/",1,true) then
        return false,other_parts
    end
    return true,other_parts
end

function env.onload(...)
    env.__ARGS__={...}
    env.init=require("init")
    env.init.init_path()
    for _,v in ipairs({'jit','ffi','bit'}) do   
        if v=="jit" then
            table.new=require("table.new")
            table.clear=require("table.clear")
            env.jit.on()
            env.jit.profile=require("jit.profile")
            env.jit.util=require("jit.util")
            env.jit.opt.start(3)
        elseif v=='ffi' then
            env.ffi=require("ffi")
        end
    end

    os.setlocale('',"all")

    env.set_command(nil,"RELOAD","Reload environment, including variables, modules, etc",env.reload,false,1)
    env.set_command(nil,"LUAJIT","#Switch to luajit interpreter, press Ctrl+Z to exit.",function() os.execute(('"%sbin%sluajit"'):format(env.WORK_DIR,env.PATH_DEL)) end,false,1)
    env.set_command(nil,"-P","#Test parameters. Usage: -p <command> [<args>]",env.testcmd,false,99)

    env.init.onload()

    env.set_prompt(nil,prompt_stack._base,0)
    if env.set and env.set.init then
        env.set.init("Prompt",prompt_stack._base,env.set_prompt,
                  "core","Define command's prompt, if value is 'timing' then will record the time cost(in second) for each execution.")
        env.set.init("COMMAND_ENDMARKS",end_marks,env.set_endmark,
                  "core","Define the symbols to indicate the end input the cross-lines command. Cannot be alphanumeric characters.")
    end
    if  env.ansi and env.ansi.define_color then
        env.ansi.define_color("Promptcolor","HIY","core","Define prompt's color")
        env.ansi.define_color("PromptSubcolor","MAG","core","Define the prompt color for subsystem.")
        env.ansi.define_color("commandcolor","HIC","core","Define command line's color")
    end
    if env.event then
        env.event.snoop("ON_COMMAND_ABORT",env.clear_command)
        env.event.callback("ON_ENV_LOADED")
    end

    set_command(nil,"/*"    ,   '#Comment',        nil   ,env.check_comment,2)
    set_command(nil,"--"    ,   '#Comment',        nil   ,false,2)
    set_command(nil,"REM"   ,   '#Comment',        nil   ,false,2)
    --load initial settings
    for _,v in ipairs(env.__ARGS__) do
        if v:sub(1,2) == "-D" then
            local key=v:sub(3):match("^([^=]+)")
            local value=v:sub(4+#key)
            java.system:setProperty(key,value)
        else
            v=v:gsub("="," ",1)
            local args=env.parse_args(2,v)
            if args[1] and _CMDS[args[1]:upper()] then
                env.eval_line(v..env.END_MARKS[1])
            end
        end
    end
end

function env.unload()
    if env.event then env.event.callback("ON_ENV_UNLOADED") end
    local e,msg=pcall(env.init.unload,init.module_list,env)
    if not e then print(msg) end
    env.init=nil
    package.loaded['init']=nil
    _CMDS.___ABBR___={}
    if env.jit and env.jit.flush then
        e,msg=pcall(env.jit.flush)
        if not e then print(msg) end
    end
end

function env.reload()
    print("Reloading environemnt ...")
    env.unload()
    java.loader.ReloadNextTime=env.CURRENT_DB
    env.CURRENT_PROMPT="_____EXIT_____"
end

function env.load_data(file,isUnpack)
    if not file:find(env.PATH_DEL) then file=env.WORK_DIR.."data"..env.PATH_DEL..file end
    local f=io.open(file,file:match('%.dat$') and "rb" or "r")
    if not f then
        return {}
    end
    local txt=f:read("*a")
    f:close()
    if not txt or txt:gsub("[\n\t%s\r]+","")=="" then return {} end
    return isUnpack==false and txt or env.MessagePack.unpack(txt)
end

function env.save_data(file,txt)
    file=env.WORK_DIR.."data"..env.PATH_DEL..file
    local f=io.open(file,file:match('%.dat$') and "wb" or "w")
    if not f then
        env.raise("Unable to save "..file)
    end
    env.MessagePack.set_array("always_as_map")
    txt=env.MessagePack.pack(txt)
    f:write(txt)
    f:close()
end

function env.write_cache(file,txt)
    local dest=env._CACHE_PATH..file
    file=dest
    local f=io.open(file,'w')
    if not f then
        env.raise("Unable to save "..file)
    end
    f:write(txt)
    f:close()
    return dest
end

function env.resolve_file(filename,ext)
    if not filename:find('[\\/]') then
        filename= env._CACHE_PATH..filename
    elseif not filename:find('^%a:') then
        filename= env.WORK_DIR..env.PATH_DEL..filename
    end
    filename=filename:gsub('[\\/]+',env.PATH_DEL)

    if ext then
        local exist_ext=filename:lower():match('%.([^%.\\/]+)$')
        local found=false
        if type(ext)=="table" then
            for _,v in ipairs(ext) do
                if v:lower()==exist_ext then
                    found=true
                    break
                end
            end
        else
            found=(exist_ext==ext:lower())
        end
        if not found then filename=filename..'.'..(type(ext)=="table" and ext[1] or exit) end
    end

    return filename
end

local title_list,title_keys={},{}
function env.set_title(title)
    local callee=env.callee():gsub("#%d+$","")
    if not title_list[callee] then
        title_keys[#title_keys+1]=callee
    end
    title_list[callee]=title or ""
    local titles=""
    for _,k in ipairs(title_keys) do
        if (title_list[k] or "")~="" then
            if titles~="" then titles=titles.."    " end
            titles=titles..title_list[k]
        end
    end
    if not titles or titles=="" then titles="DBCLI - Disconnected" end
    os.execute("title "..titles)
end

function env.reset_title()
    for k,v in pairs(title_list) do title_list[k]="" end
    os.execute("title dbcli")
end

return env