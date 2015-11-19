--init a global function to store CLI variables
local _G = _ENV or _G

local reader,coroutine,os,string,table,math,io,select,xpcall,pcall=reader,coroutine,os,string,table,math,io,select,xpcall,pcall

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
local record_maker=false

local mt = getmetatable(_G)

if mt == nil then
    mt = {}
    setmetatable(_G, mt)
end

mt.__declared = {}

mt.__newindex = function (t, n, v)
    if not mt.__declared[n] and env.WORK_DIR then
        --if record_maker then print('Detected unexpected global var "'..n..'" with', debug.traceback()) end
        rawset(mt.__declared, n,env.callee(5))
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

local function pcall_error(e)
    return tostring(e) .. '\n' .. debug.traceback()
end

function env.ppcall(f, ...)
    return xpcall(f, pcall_error, ...)
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
    local dir,dirs
    local keylist={}
    
    local filter=file_ext and "*."..file_ext or "*"
    
    file_dir=file_dir:gsub("[\\/]+",env.PATH_DEL):gsub("[\\/]+$","")
    local exists=os.exists(file_dir)
    if not exists then return keylist end
    if exists==1 then 
        dir={file_dir}
    else
        dir={}
        if env.OS=="windows" then
            dirs=io.popen('dir /B/S/A:-D "'..file_dir..env.PATH_DEL..filter.. '" 2>nul')
        else
            dirs=io.popen('find "'..file_dir..'" -iname '..filter..' -print >/dev/null')
        end
        for n in dirs:lines() do dir[#dir+1]=n end
    end

    for _,n in ipairs(dir) do
        local name,ext=n:match("([^\\/]+)$")
        if file_ext then
            name,ext=name:match("(.+)%.(%w+)$")
            if ext and ext:upper()~=file_ext:upper() and file_ext~="*" then name=nil end
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
    if #args==0 then return true,rest:gsub('['..env.END_MARKS[1]..' \t]+$',"") end
    for k=1,#args do
        if not env.check_cmd_endless(args[k]:upper(),table.concat(args,' ',k+1)) then
            return false,rest
        end
    end
    return true,rest:gsub('*%s*$',"")
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
    if not errmsg then return end
    errmsg=(tostring(errmsg) or "")
    local HIR,NOR,count="",""
    if env.ansi and env.set and env.set.exists("ERRCOLOR") then
        HIR,NOR=env.ansi.get_color(env.set.get("ERRCOLOR")),env.ansi.get_color('NOR')
        errmsg=env.ansi.strip_ansi(errmsg)
    end
    errmsg,count=errmsg:gsub('^.-(%u%u%u%-%d%d%d%d%d)','%1') 
    if count==0 then
        errmsg=errmsg:gsub('^.*%s([^%: ]+Exception%:%s*)','%1'):gsub(".*[IS][OQL]+Exception:%s*","")
    end
    errmsg=errmsg:gsub("^.*000%-00000%:%s*",""):gsub("%s+$","")
    if src then
        local name,line=src:match("([^\\/]+)%#(%d+)$")
        if name then
            name=name:upper():gsub("_",""):sub(1,3)
            errmsg=string.format("%s-%05i: %s",name,tonumber(line),errmsg)
        end
    end
    if select('#',...)>0 then errmsg=errmsg:format(...) end
    return errmsg=="" and errmsg or HIR..errmsg..NOR
end

function env.warn(...)
    local str,count=env.format_error(nil,...)
    if str and str~='' then print(str,'__BYPASS_GREP__') end
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
        if type(msg)=="function" then msg=msg(...) end
        local str=env.format_error(env.callee(),msg,...)
        return error(str)
    end
end


function _exec_command(name,params)
    local result
    local cmd=_CMDS[name:upper()]
    local stack=table.concat(params," ")
    if not cmd then
        return env.warn("No such comand '%s'!",name)
    end
    stack=(cmd.ARGS==1 and stack or name.." "..stack)
    push_history(stack)
    if not cmd.FUNC then return end
    local args= cmd.OBJ and {cmd.OBJ,table.unpack(params)} or {table.unpack(params)}

    local funs=type(cmd.FUNC)=="table" and cmd.FUNC or {cmd.FUNC}
    for _,func in ipairs(funs) do
        env.register_thread()
        local co=coroutine.create(func)
        env.register_thread(co)
        local res={coroutine.resume(co,table.unpack(args))}
        env.register_thread()
        --local res = {pcall(func,table.unpack(args))}
        if not res[1] then
            result=res
            env.log_debug("CMD",res[2])
            env.warn(res[2])
        elseif not result then
            result=res
        end
    end

    if not result[1] then error('000-00000:') end
    
    return table.unpack(result)
end

local writer=writer
env.RUNNING_THREADS={}

function env.register_thread(this,isMain)
    local threads=env.RUNNING_THREADS
    if not this then this,isMain=coroutine.running() end
    if isMain then
        threads[this],threads[1]=1,this
    end
    if not threads[this] then
        threads[this],threads[#threads+1]=#threads+1,this
    else
        for i=threads[this]+1,#threads do 
            threads[i],threads[threads[i]]=nil,nil
        end
    end
    return this,isMain,#threads
end

function env.exec_command(cmd,params,is_internal)
    local name=cmd:upper()
    local event=env.event and env.event.callback
    local this,isMain=env.register_thread()

    env.CURRENT_CMD=name
    if event then
        if isMain then
            if writer then
                writer:print(env.ansi.mask("NOR",""))
                writer:flush()
            end
            env.log_debug("CMD",name,params)
        end
        
        if event and not is_internal then 
            name,params=table.unpack((event("BEFORE_COMMAND",{name,params,is_internal}))) 
        end
    end
    local res={pcall(_exec_command,name,params)}
    if event and not is_internal then 
        event("AFTER_COMMAND",name,params,res[2],is_internal)
    end
    if not isMain and not res[1] and (not env.set or env.set.get("OnErrExit")=="on") then error() end
    if event and not is_internal then 
        event("AFTER_SUCCESS_COMMAND",name,params,res[2],is_internal)
    end
    return table.unpack(res,2)
end

local is_in_multi_state=false
local curr_stmt=""
local multi_cmd

local cache_prompt,fix_prompt

local prompt_stack={_base="SQL"}

function env.set_prompt(class,default,is_default,level)
    if default then
        if not env._SUBSYSTEM  then default=default:upper() end
        if env.ansi then default=env.ansi.convert_ansi(default) end
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

    if  not default:match("[%a] *$") then 
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

function env.parse_args(cmd,rest,is_cmd)
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
    if rest then rest=rest:gsub("%s+$","") end
    if rest=="" then rest = nil end

    local args={}
    if arg_count == 1 then
        args[#args+1]=cmd..(rest and #rest> 0 and (" "..rest) or "")
    elseif arg_count == 2 then
        args[#args+1]=rest
    elseif rest then
        local piece=""
        local quote='"'
        local is_quote_string = false
        local count=#args
        for i=1,#rest,1 do
            local char=rest:sub(i,i)
            if is_quote_string then--if the parameter starts with quote
                if char ~= quote then
                    piece = piece .. char
                elseif rest:sub(i+1,i+1):match("%s") or #rest==i then
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
                elseif not char:match("%s") then
                    piece = piece ..char
                elseif piece ~= '' then
                    args[#args+1],piece=piece,''
                end
            end

            if count ~= #args then
                count=#args
                local name=args[count]:upper()
                local is_multi_cmd=is_cmd==true and _CMDS[name] and _CMDS[name].MULTI
                if count>=arg_count-2 or is_multi_cmd then--the last parameter
                    piece=rest:sub(i+1):gsub("^(%s+)",""):gsub('^"(.*)"$','%1')
                    if is_multi_cmd and _CMDS[name].ARGS==1 then
                        args[count],piece=args[count]..' '..piece,''
                    elseif piece~='' then
                        args[count+1],piece=piece,''
                    end
                    break
                end

            end
        end
        --If the quote is not in couple, then treat it as a normal string
        if piece:sub(1,1)==quote then
            for s in piece:gmatch('(%S+)') do
                args[#args+1]=s
            end
        elseif not piece:match("^%s*$") then
            args[#args+1]=piece
        end
    end

    return args,cmd
end

function env.force_end_input(exec,is_internal)
    if curr_stmt then
        local stmt={multi_cmd,env.parse_args(multi_cmd,curr_stmt,true)}
        multi_cmd,curr_stmt=nil,nil
        env.CURRENT_PROMPT=env.PRI_PROMPT
        if exec~=false then
            env.exec_command(stmt[1],stmt[2],is_internal)
        else
            push_stack(false)
            return stmt[1],stmt[2]
        end
    end
    push_stack(false)
    multi_cmd,curr_stmt=nil,nil
    return
end

function env.eval_line(line,exec,is_internal)
    if type(line)~='string' or line:gsub('%s+','')=='' then return end
    local subsystem_prefix=""
    --Remove BOM header
    if not env.pending_command() then
        line=line:gsub('^%s+','')
        push_stack(line)
        subsystem_prefix=env._SUBSYSTEM and (env._SUBSYSTEM.." ") or ""
        local cmd=env.parse_args(2,line)[1]
        if dbcli_current_item.skip_subsystem then
            subsystem_prefix=""
        elseif cmd:sub(1,1)=='.' and _CMDS[cmd:upper():sub(2)] then
            subsystem_prefix=""
            dbcli_current_item.skip_subsystem=true
            line=line:sub(2)
        elseif cmd:lower()==subsystem_prefix:lower() then
            subsystem_prefix=""
        end
        line=(subsystem_prefix..line):gsub('^[%z\128-\255 \t]+','')
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
        if done or is_internal then
            return env.force_end_input(exec,is_internal)
        end
        curr_stmt = curr_stmt .."\n"
        return multi_cmd
    end

    if multi_cmd then return check_multi_cmd(line) end

    local cmd,rest=line:match('^%s*(%S+)%s*(.*)')
    if env.event then 
        cmd,rest=table.unpack(env.event.callback('BEFORE_EVAL',{cmd,rest}))
        if not (_CMDS[cmd]) then  cmd,rest=(cmd.." ".. rest):match('^%s*(%S+)%s*(.*)') end
    end
    if not cmd then return end
    cmd=(subsystem_prefix=="" and cmd:gsub(env.END_MARKS[1]..'+$',''):upper() or cmd):upper()
    env.CURRENT_CMD=cmd
    if not (_CMDS[cmd]) then
        push_stack(false)
        return env.warn("No such command '%s', please type 'help' for more information.",cmd)
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
        env.exec_command(cmd,args,local_stack,is_internal)
        push_stack(false)
    else
        push_stack(false)
        return cmd,args
    end
end

function env.testcmd(command)
    env.checkerr(command,"Usage: -p <other command>")
    local args,cmd=env.eval_line(command,false,true)
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
    if not other_parts:find("*/",1,true) then
        return false,other_parts
    end
    return true,other_parts
end

local print_debug
local debug_group={ALL="all"}
function env.log_debug(name,...)
    name=name:upper()
    if not debug_group[name] then debug_group[name]=env.callee(3) end
    if not print_debug or env.set.get('debug')=="off" then return end
    local value=env.set.get('debug'):upper()
    local args={'['..name..']'}
    for i=1,select('#',...) do
        local v=select(i,...)
        if v==nil then
            args[i+1]='nil'
        elseif type(v)=="table" then 
            args[i+1]=table.dump(v)
        else
            args[i+1]=v
        end
    end
    if value=="all" or value==name then print_debug(table.unpack(args)) end
end

function set_debug(name,value)
    value=value:upper()
    if env.grid then
        local rows=env.grid.new()
        rows:add{"Name","Source","Enabled"}
        for k,v in pairs(debug_group) do
            rows:add{k,v,k==value and "Yes" or "No"}
        end
        rows:sort(1,true)
        rows:print()
    end
    return value
end

local function set_cache_path(name,path)
    path=path:gsub("[\\/]+",env.PATH_DEL):gsub("[\\/]$","")..env.PATH_DEL
    env.checkerr(os.exists(path)==2,"No such path: "..path)
    env['_CACHE_BASE'],env["_CACHE_PATH"]=path,path
    return path
end

function env.onload(...)
    record_maker=false
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
    env.set_command(nil,"LUAJIT","#Switch to luajit interpreter, press Ctrl+Z to exit.",function() os.execute(('"%slib%sx86%sluajit"'):format(env.WORK_DIR,env.PATH_DEL,env.PATH_DEL)) end,false,1)
    env.set_command(nil,"-P","#Test parameters. Usage: -p <command> [<args>]",env.testcmd,'__SMART_PARSE__',2)

    env.init.onload()
    
    env.set_prompt(nil,prompt_stack._base,0)
    if env.set and env.set.init then
        env.set.init({"Prompt","SQLPROMPT","SQLP"},prompt_stack._base,env.set_prompt,
                  "core","Define command's prompt, if value is 'timing' then will record the time cost(in second) for each execution.")
        env.set.init("COMMAND_ENDMARKS",end_marks,env.set_endmark,
                  "core","Define the symbols to indicate the end input the cross-lines command. Cannot be alphanumeric characters.")
        env.set.init("Debug",'off',set_debug,"core","Indicates the option to print debug info, 'all' for always, 'off' for disable, others for specific modules.")
        env.set.init("OnErrExit",'on',nil,"core","Indicates whether to continue the remaining statements if error encountered.","on,off")
        env.set.init("TEMPPATH",'cache',set_cache_path,"core","Define the dir to store the temp files.","*")
        print_debug=print
    end
    if  env.ansi and env.ansi.define_color then
        env.ansi.define_color("Promptcolor","HIY","ansi.core","Define prompt's color, type 'ansi' for more available options")
        env.ansi.define_color("ERRCOLOR","HIR","ansi.core","Define color of the error messages, type 'ansi' for more available options")
        env.ansi.define_color("PromptSubcolor","MAG","ansi.core","Define the prompt color for subsystem, type 'ansi' for more available options")
        env.ansi.define_color("commandcolor","HIC","ansi.core","Define command line's color, type 'ansi' for more available options")
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
    record_maker=true
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
    print("Reloading environment ...")
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