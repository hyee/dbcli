--init a global function to store CLI variables
local _G = _ENV or _G
local reader=reader

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
    __index=function(self,key) return self.___ABBR___[key] and self[self.___ABBR___[key]]  or nil end
})

--
env.space="    "
local _CMDS=env._CMDS
function env.list_dir(file_dir,file_ext,text_macher)
    local dir
    local keylist={}

    local filter=file_ext and "*."..file_ext or "*"
    file_dir=(file_dir..env.PATH_DEL):gsub("[\\/]+",env.PATH_DEL)
    if env.OS=="windows" then
        dir=io.popen('dir "'..file_dir..'\\'..filter..'" /b /s')
    else
        dir=io.popen('find "'..file_dir..'" -iname '..filter..' -print')
    end

    for n in dir:lines() do 
        local name=n:match("([^\\/]+)$")
        if file_ext then
            name=name:match("(.+)%.%w+$")
        end 
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
    return keylist
end

local cmd_keys={}

function env.check_cmd_endless(cmd,other_parts)
    
    if not _CMDS[cmd] then
        return true,other_parts
    end
    local p1=';+[%s\t\n]*$'

    if not _CMDS[cmd].MULTI then        
        return true,other_parts and other_parts:gsub(p1,"")
    elseif type(_CMDS[cmd].MULTI)=="function" then
        return _CMDS[cmd].MULTI(cmd,other_parts)
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

function env.set_command(obj,cmd,help_func,call_func,is_multiline,paramCount,dbcmd)
    local abbr={}
    if not paramCount then
        env.raise("Incompleted command["..cmd.."], number of parameters is not defined!")
    end

    if type(cmd)=="table" then
        local tmp=cmd[1]:upper()
        for i=2,#cmd,1 do 
            if _CMDS[tmp] then break end
            cmd[i]=cmd[i]:upper()

            if _CMDS.___ABBR___[cmd[i]] then
                env.raise("Command '"..cmd[i].."' is already defined in ".._CMDS[_CMDS.___ABBR___[cmd[i]]]["FILE"])
            end
            cmd_keys[#cmd_keys+1]=cmd[i]
            table.insert(abbr,cmd[i])
            _CMDS.___ABBR___[cmd[i]]=tmp          
        end
        cmd=tmp
    else
        cmd=cmd:upper()
    end
    
    if _CMDS[cmd] then
        env.raise("Command '"..cmd.."' is already defined in ".._CMDS[cmd]["FILE"])
    end

    cmd_keys[#cmd_keys+1]=cmd

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
        OBJ    = obj,          --object, if the connected function is not a static function, then this field is used.
        FILE   = src,          --the file name that defines & executes the command
        DESC   = desc,         --command short help without \n
        HELPER = help_func,    --command detail help, it is a function
        FUNC   = call_func,    --command function        
        MULTI  = is_multiline,
        ABBR   = table.concat(abbr,','),
        ARGS   = paramCount,
        DBCMD  = dbcmd
    }
end

function env.remove_command(cmd)
    cmd=cmd:upper()
    if not _CMDS[cmd] then return end
    local src=env.callee()
    if src:gsub("#%d+","")~=_CMDS[cmd].FILE:gsub("#%d+","") then
        env.raise("Cannot remove command '%s' from %s, it was defined in file %s!",cmd,src,_CMDS[cmd].FILE)
    end
    for k,v in pairs(_CMDS.___ABBR___) do
        if v==cmd then
            _CMDS.___ABBR___[k]=nil
        end
    end
    _CMDS[cmd]=nil
end    

function env.callee(idx)
    if type(idx)~="number" then idx=3 end
    local info=getinfo(idx)    
    return info.short_src:gsub(env.WORK_DIR,"",1):gsub("%.%w+$","#"..info.currentline)
end

function env.format_error(src,errmsg,...)  
    errmsg=errmsg or ""  
    local name,line=src:match("([^\\/]+)%#(%d+)$")
    if name then
        name=name:upper():gsub("_",""):sub(1,3)
        errmsg=name.."-"..string.format("%05i",tonumber(line))..": "..errmsg
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
    print(str)
    return error('000-00000:')
end

function env.checkerr(result,msg,...)
    if not result then
        local str=env.format_error(env.callee(),msg,...)
        print(str)
        return error('000-00000:')
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
        local res = {pcall(func,table.unpack(args))}
        if not res[1] then
            result=res
            local msg={} 
            if not tostring(res[2]):find('000-00000:',1,true) then
                for v in tostring(res[2]):gmatch("(%u%u%u+%-[^\n\r]*)") do
                    table.insert(msg,v)
                end
                if #msg > 0 then
                    print(env.ansi.mask("HIR",table.concat(msg,'\n')))
                else
                    local trace=tostring(res[2]) --..'\n'..env.trace.enable(false)
                    print(env.ansi.mask("HIR",trace.."\n"))
                end
            end
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

function env.parse_args(cmd,rest)    
    --deal with the single-line commands
    local args_count
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
    
    local args ,args1={}    
    if arg_count == 1 then
        args[#args+1]=cmd.." "..rest
    elseif arg_count == 2 then
        args[#args+1]=rest
    elseif rest then 
        local piece=""
        local quote='"'
        local is_quote_string = false
        for i=1,#rest,1 do
            local char=rest:sub(i,i)
            if is_quote_string then                
                if char ~= quote then
                    piece = piece .. char
                elseif (rest:sub(i+1,i+1) or " "):match("^%s*$") then
                    --end of a quote string if next char is a space
                    args[#args+1]=piece:sub(2)
                    piece=''
                    is_quote_string=false
                else
                    piece=piece..char
                end
            else
                if char==quote and piece == '' then
                    --begin a quote string, if its previous char is not a space, then bypass
                    is_quote_string = true
                    piece=quote                   
                elseif not char:match("[%s\t\r\n]") then
                    piece = piece ..char
                elseif piece ~= '' then
                    args[#args+1]=piece
                    piece=''
                end
            end
            if #args>=arg_count-2 then
                piece=rest:sub(i+1)
                if piece:sub(1,1)==quote and piece:sub(-1)==quote then
                    piece=piece:sub(2,-2)
                end
                args[#args+1]=piece
                piece=""
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
    return args,cmd
end

function env.eval_line(line,exec)
    if not line then return end
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
    
    local cmd,rest=env.parse_args(2,line)
    cmd,rest=cmd[1],cmd[2] or ""
    cmd=cmd:gsub(';+$','')
    if not cmd or cmd=="" or cmd:sub(1,2)=="--" then return end
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

function env.set_title(title)
    os.execute("title "..title)
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
    env.args={...} 
    env.init=require("init")     
    env.init.init_path()
    for k,v in ipairs({'jit','ffi','bit'}) do
        if not _G[v] then
            local m=package.loadlib("lua5.1."..(env.OS=="windows" and "dll" or "so"), "luaopen_"..v)()
            if not _G[v] then _G[v]=m end
            if v=="jit" then
                table.new=require("table.new")
                table.clear=require("table.clear")
                jit.profile=require("jit.profile")
            end
        end 
    end
    
    os.setlocale('',"all")

    env.set_command(nil,"RELOAD","Reload environment, including variables, modules, etc",env.reload,false,1)
    env.set_command(nil,"LUAJIT","#Switch to luajit interpreter, press Ctrl+Z to exit.",function() os.execute(('"%sbin%sluajit"'):format(env.WORK_DIR,env.PATH_DEL)) end,false,1)
    env.set_command(nil,"-P","#Test parameters. Usage: -p <command> [<args>]",env.testcmd,false,99)
    
    env.init.load(init.module_list,env)

    env.set_prompt(nil,"SQL")  
    env.safe_call(env.set and env.set.init,"Prompt","SQL",env.set_prompt,
                  "core","Define command's prompt, if value is 'timing' then will record the time cost(in second) for each execution.")
    env.safe_call(env.ansi and env.ansi.define_color,"Promptcolor","HIY","core","Define prompt's color")
    env.safe_call(env.ansi and env.ansi.define_color,"commandcolor","HIC","core","Define command line's color")
    env.safe_call(env.event and env.event.callback,"ON_ENV_LOADED") 
    
    --load initial settings
    for _,v in ipairs(env.args) do
        if v:sub(1,2) == "-D" then
            local key=v:sub(3):match("^([^=]+)")
            local value=v:sub(4+#key)
            java.system:setProperty(key,value)
        else
            env.eval_line(v:gsub("="," ",1)..';')
        end
    end 
end

function env.unload()
    if env.event then env.event.callback("ON_ENV_UNLOADED") end

    env.init.unload(init.module_list,env)
    env.init=nil
    package.loaded['init']=nil
    for k,v in pairs(_CMDS) do
        _CMDS[k]=nil
    end
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
    env.MessagePack.set_array("always_as_map")
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

return env