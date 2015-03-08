--init a global function to store CLI variables
local _G = _ENV or _G

local reader,coroutine=reader,coroutine

local getinfo, error, rawset, rawget = debug.getinfo, error, rawset, rawget

local env=setmetatable({},{
    __call =function(self, key, value)            
            rawset(self,key,value) 
            _G[key]=value
        end,
    __index=function(self,key) return _G[key] end,
    __newindex=function(self,key,value) self(key,value) end
})
_G['env']=env


local function abort_thread()
    if coroutine.running () then
        debug.sethook()
        --print(env.CURRENT_THREAD)
        --print(debug.traceback())
    end
end

_G['TRIGGER_ABORT']=function()
local thread=java.require("java.lang.Thread",true)
--thread:currentThread():interrupt()
    env.safe_call(env.event and env.event.callback,"ON_COMMAND_ABORT")
    if env.CURRENT_THREAD then
        --print(table.dump(env.CURRENT_THREAD))
        debug.sethook(abort_thread,"rl")
        env.CURRENT_THREAD=nil
    end
end

local mt = getmetatable(_G)

if mt == nil then
    mt = {}
    setmetatable(_G, mt)
end

mt.__declared = {}

mt.__newindex = function (t, n, v)
    if not mt.__declared[n] and env.WORK_DIR then    
        mt.__declared[n] = env.callee()
    end
    rawset(t, n, v)
end

env.globals=mt.__declared

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
            if ext:upper()~=file_ext:upper() then name=nil end
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


function env.check_cmd_endless(cmd,other_parts)
    
    if not _CMDS[cmd] then
        return true,other_parts
    end
    local p1=';+[%s\t\n]*$'

    if not _CMDS[cmd].MULTI then        
        return true,other_parts and other_parts:gsub(p1,"")
    elseif type(_CMDS[cmd].MULTI)=="function" then
        return _CMDS[cmd].MULTI(cmd,other_parts)
    elseif _CMDS[cmd].MULTI=='__SMART_PARSE__' then
        return env.smart_check_endless(cmd,other_parts,_CMDS[cmd].ARGS)
    end
    
    local p2='\r*\n[%s\r\t\n]*/[%s\t]*$'
    local match = (other_parts:match(p1) and 1) or (other_parts:match(p2) and 2) or false
    --print(match,other_parts)
    if not match then
        return false,other_parts
    end

    return true,other_parts:gsub(match==1 and p1 or p2,"")
end

function env.smart_check_endless(cmd,rest,from_pos)
    local args=env.parse_args(from_pos,rest)
    if not args[from_pos-1] then return true,rest:gsub('[;%s\t]+$',"") end
    if env.check_cmd_endless(args[from_pos-1]:upper(),args[from_pos] or "") then
        return true,rest:gsub('[%s\n\r\t]+$',"")
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

    if desc then
        desc = desc:gsub("^[\n\r%s\t]*[\n\r]+","")
        desc = desc:match("([^\n\r]+)") 
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
end    

function env.callee(idx)
    if type(idx)~="number" then idx=3 end
    local info=getinfo(idx)    
    return info.short_src:gsub(env.WORK_DIR,"",1):gsub("%.%w+$","#"..info.currentline)
end

function env.format_error(src,errmsg,...)  
    errmsg=errmsg or ""  
    if src then
        local name,line=src:match("([^\\/]+)%#(%d+)$")
        if name then
            name=name:upper():gsub("_",""):sub(1,3)
            errmsg=name.."-"..string.format("%05i",tonumber(line))..": "..errmsg
        end
    end
    if select('#',...)>0 then errmsg=errmsg:format(...) end   
    return env.ansi.mask('HIR',errmsg)
end

function env.warn(...)
    local str=env.format_error(env.callee(),...)   
    print(str)
end

function env.raise(...)
    local str=env.format_error(env.callee(),...)
    return error('000-00000:'..str)
end

function env.raise_error(...)
    local str=env.format_error(nil,...)
    return error('000-00000:'..str)
end

function env.checkerr(result,msg,...)
    if not result then
        local str=env.format_error(env.callee(),msg,...)
        return error('000-00000:'..str)
    end
end

local writer=writer
function env.exec_command(cmd,params)    
    local result
    local name=cmd:upper()
    cmd=_CMDS[cmd]   

    if not cmd then
        return print("No such comand["..name.." "..table.unpack(params).."]!")
    end

    if not cmd.FUNC then return end
    env.CURRENT_CMD=name
    local args= cmd.OBJ and {cmd.OBJ,table.unpack(params)} or {table.unpack(params)}
    local event=env.event and env.event.callback
    if event then event("BEFORE_COMMAND",name,params) end
    --env.trace.enable(true)
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
            local msg={}
            res[2]=tostring(res[2]):gsub('^.*java%..*Exception%:%s*',''):gsub("^.*000%-00000:","")
            for v in res[2]:gmatch("(%u%u%u+%-[^\n\r]*)") do
                table.insert(msg,v)
            end
            if #msg > 0 then
                print(env.ansi.mask("HIR",table.concat(msg,'\n')))
            elseif #res[2]>0 then
                print(env.ansi.mask("HIR",res[2].."\n"))
            end

            if coroutine.running() then pcall(coroutine.yield) end
        elseif not result then
            result=res       
        end
    end
    if result[1] and event and not env.IS_INTERNAL_EVAL then event("AFTER_COMMAND",name,params) end
        
    return table.unpack(result)
end

local is_in_multi_state=false
local curr_stmt=""
local multi_cmd

local cache_prompt,fix_prompt

function env.set_prompt(name,default,isdefault)
    default=default:upper()    
    if not name then
        cache_prompt=default
        if fix_prompt then default=fix_prompt end
    else
        if isdefault then
            fix_prompt,default=nil,cache_prompt
        else
            fix_prompt=default
        end
    end
    env.PRI_PROMPT,env.MTL_PROMPT=default.."> ",(" "):rep(#default+2)
    env.CURRENT_PROMPT=env.PRI_PROMPT
    return default
end

function env.pending_command()
    if curr_stmt and curr_stmt~="" then 
        return true
    end
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
end

function env.parse_args(cmd,rest)    
    --deal with the single-line commands
    local arg_count
    if type(cmd)=="number" then
        arg_count=cmd+1
    else
        if not cmd then 
            cmd,rest=rest:match('([^%s\n\r\t;]+)[%s\n\r\t]*(.*)') 
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
                elseif (rest:sub(i+1,i+1) or " "):match("^[%s\n\t\r]*$") then
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
                elseif not char:match("([%s\t\r\n])") then
                    piece = piece ..char
                elseif piece ~= '' then
                    args[#args+1],piece=piece,''
                end
            end
            if #args>=arg_count-2 then--the last parameter
                piece=rest:sub(i+1):gsub("^([%s\t\r\n]+)",""):gsub('^"(.*)"$','%1')                
                args[#args+1],piece=piece,''
                break
            end
        end
        --If the quote is not in couple, then treat it as a normal string
        if piece:sub(1,1)==quote then
            for s in piece:gmatch('([^%s]+)') do
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

function env.eval_line(line,exec)
    if type(line)~='string' or line:gsub('[%s\n\r\t]+','')=='' then return end
    local b=line:byte()    
    --remove bom header
    if not b or b>=128 then return end
    local done
    local function check_multi_cmd(lineval)
        curr_stmt = curr_stmt ..lineval
        done,curr_stmt=env.check_cmd_endless(multi_cmd,curr_stmt)
        if done then  
            if curr_stmt then
                local stmt={multi_cmd,env.parse_args(multi_cmd,curr_stmt)}                                
                multi_cmd,curr_stmt=nil,nil
                env.CURRENT_PROMPT=env.PRI_PROMPT
                if exec~=false then
                    env.exec_command(stmt[1],stmt[2])
                else
                    return stmt[1],stmt[2]
                end
            end
            multi_cmd,curr_stmt=nil,nil
            return
        end
        curr_stmt = curr_stmt .."\n"
        return multi_cmd
    end
    
    if multi_cmd then return check_multi_cmd(line) end
    
    local cmd,rest=line:match('^%s*([^%s\t]+)[%s\t]*(.*)')
    
    if not cmd or cmd=="" or cmd:sub(1,2)=="--" then return end
    cmd=cmd:gsub(';+$','')
    if cmd:sub(1,2)=="/*" then cmd=cmd:sub(1,2) end
    cmd=cmd:upper()
    if not (_CMDS[cmd]) then
        return print("No such command["..cmd.."], please type 'help' for more information.")        
    elseif _CMDS[cmd].MULTI then --deal with the commands that cross-lines
        multi_cmd=cmd
        env.CURRENT_PROMPT=env.MTL_PROMPT
        curr_stmt = ""
        return check_multi_cmd(rest)
    end
    
    --print('Command:',cmd,table.concat (args,','))
    rest=rest:gsub("[;%s]+$","")
    local args=env.parse_args(cmd,rest)
    if exec~=false then
        env.exec_command(cmd,args)        
    else
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
    cmd,args=env.eval_line(table.concat(args,' ')..';',false)
    if not cmd then return end
    print("Command    : "..cmd.."\nParameters : "..#args..' - '..(_CMDS[cmd].ARGS-1).."\n============================")
    for k,v in ipairs(args) do
        print(string.format("%-2s = %s",k,v))
    end
end

function safe_call(func,...)
    if not func then return end
    local res,rtn=pcall(func,...)
    if not res then
        return env.warn(tostring(rtn):gsub(env.WORK_DIR,""))
    end
    return rtn
end

function env.onload(...)
    env.__ARGS__={...} 
    env.init=require("init")     
    env.init.init_path()
    for k,v in ipairs({'jit','ffi','bit'}) do
        if not _G[v] then
            local m=package.loadlib("lua5.1."..(env.OS=="windows" and "dll" or "so"), "luaopen_"..v)()
            if not _G[v] then _G[v]=m end
            if v=="jit" then
                table.new=require("table.new")
                table.clear=require("table.clear")
                env.jit.profile=require("jit.profile")
                env.jit.util=require("jit.util")
            elseif v=='ffi' then
                env.ffi=require("ffi")
            end
        end 
    end
    
    os.setlocale('',"all")

    env.set_command(nil,"RELOAD","Reload environment, including variables, modules, etc",env.reload,false,1)
    env.set_command(nil,"LUAJIT","#Switch to luajit interpreter, press Ctrl+Z to exit.",function() os.execute(('"%sbin%sluajit"'):format(env.WORK_DIR,env.PATH_DEL)) end,false,1)
    env.set_command(nil,"-P","#Test parameters. Usage: -p <command> [<args>]",env.testcmd,false,99)
    
    env.init.onload()

    env.set_prompt(nil,"SQL")  
    env.safe_call(env.set and env.set.init,"Prompt","SQL",env.set_prompt,
                  "core","Define command's prompt, if value is 'timing' then will record the time cost(in second) for each execution.")
    env.safe_call(env.ansi and env.ansi.define_color,"Promptcolor","HIY","core","Define prompt's color")
    env.safe_call(env.ansi and env.ansi.define_color,"commandcolor","HIC","core","Define command line's color")
    env.safe_call(env.event and env.event.snoop,"ON_COMMAND_ABORT",env.clear_command)
    env.safe_call(env.event and env.event.callback,"ON_ENV_LOADED") 
    
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
                env.eval_line(v..';')
            end
        end
    end 
end

function env.unload()
    if env.event then env.event.callback("ON_ENV_UNLOADED") end
    env.init.unload(init.module_list,env)
    env.init=nil
    package.loaded['init']=nil
    _CMDS.___ABBR___={}
    if jit and jit.flush then pcall(jit.flush) end
end

function env.reload()
    print("Reloading environemnt ...")
    env.unload()
    java.loader.ReloadNextTime=true
    env.CURRENT_PROMPT="_____EXIT_____"
end

function env.load_data(file)
    file=env.WORK_DIR.."data"..env.PATH_DEL..file
    local f=io.open(file)
    if not f then
        return {}
    end
    local txt=f:read("*a")    
    f:close()
    if not txt or txt:gsub("[\n\t%s\r]+","")=="" then return {} end
    --env.MessagePack.set_array("always_as_map")
    return env.MessagePack.unpack(txt)
end

function env.save_data(file,txt)
    file=env.WORK_DIR.."data"..env.PATH_DEL..file
    local f=io.open(file,'w')
    if not f then
        env.raise("Unable to save "..file)
    end
    env.MessagePack.set_array("always_as_map")
    txt=env.MessagePack.pack(txt)
    f:write(txt)
    f:close()
end

function env.write_cache(file,txt)
    local dest=env.WORK_DIR.."cache"..env.PATH_DEL..file
    file=dest
    local f=io.open(file,'w')
    if not f then
        env.raise("Unable to save "..file)
    end   
    f:write(txt)
    f:close()
    return dest
end

local title_list,title_keys={},{}
function env.set_title(title)
    local callee=env.callee():gsub("#%d+$","")
    if not title_list[callee] then
        title_keys[#title_keys+1]=callee
    end
    title_list[callee]=title or ""
    title=""
    for _,k in ipairs(title_keys) do
        if (title_list[k] or "")~="" then
            if title~="" then title=title.."    " end
            title=title..title_list[k]
        end
    end
    os.execute("title "..title)
end

function env.reset_title()
    for k,v in pairs(title_list) do title_list[k]="" end
    os.execute("title dbcli")
end

return env