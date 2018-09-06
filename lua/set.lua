local env=env
local cfg,grid={name='SET'},env.grid
local maxvalsize=20
local file='setting.dat'
local root_cmd
cfg._backup=nil
cfg._plugins={}


function cfg.show_cfg(name)
    local rows={{'Name','Value','Default','Class','Available Values','Description'}}
    print([[Usage: set      <name>                                  : Get specific parmeter value
       set -a                                           : Show abbrs and source.
       set      <name1> <value1> [<name2> <value2> ...] : Change settings in current window
       set -p   <name1> <value1> [<name2> <value2> ...] : Change settings permanently
       set [-p] <name1> default  [<name2> back     ...] : Change settings back to the default/previous values
    ]])
    if name and name~='-a' and name~='-A' then
        for k,v in pairs(cfg) do
            if type(v)=="table" and k==k:upper() and v.src and (k:find(name,1,true) or v.class and v.class:upper():find(name,1,true)) then
                table.insert(rows,{k,string.from(v.value),string.from(v.default),v.class,v.range or '*',v.desc})
            end
        end
    else
        if name then table.insert(rows[1],2,"Source") end
        for k,v in pairs(cfg) do
            if type(v)=="table" and k==k:upper() and v.src and (name or (v.desc and not v.desc:find('^#'))) then
                table.insert(rows,{
                    name and table.concat(v.abbr,', ') or k,
                    #tostring(v.value)<=30 and tostring(v.value) or tostring(v.value):sub(1,27)..'...',
                    #tostring(v.default)<=30 and tostring(v.default) or tostring(v.default):sub(1,27)..'...',
                    v.class,v.range or '*',
                    v.desc})
                if name then table.insert(rows[#rows],2,cfg[k].src) end
            end
        end
    end
    grid.sort(rows,"Class,Name",true)
    grid.print(rows)
end

cfg._commands={}
function cfg.exists(name)
    return name and cfg._commands[name:upper()]
end

function cfg.get(name)
    local option=cfg.exists(name)
    if not option then
        return env.warn("Setting ["..name.."] does not exist!")
    end
    return option.value
end

function cfg.change_default(name,value)
    local item=cfg.exists(name)
    env.checkerr(item,"No Such setting: %s",name)
    if cfg.get(name)==item.default then
        cfg.force_set(name,value)
    end
    item.default=value
end

function cfg.get_config(name,value)
    return env.load_data(file)[name:upper()]
end

function cfg.save_config(name,value)
    env.checkerr(name and not cfg.exists(name),"Cannot configure %s that already defined!",name)
    cfg._p=env.load_data(file)
    value=value and value:lower()~="default" and value or nil 
    cfg._p[name:upper()]=value
    env.save_data(file,cfg._p)
    return value
end

function cfg.init(name,defaultvalue,validate,class,desc,range,instance)
    local abbr={name}
    if type(name)=="table" then
        abbr=name
        name=abbr[1]
    end
    name=name:upper()
    if cfg.exists(name) then
        return env.warn("Environment parameter '%s' has been defined in %s!",name,cfg.exists(name).src)
    end
    if not cfg[name] then cfg[name]={} end
    cfg[name]={
        value=defaultvalue,
        abbr=abbr,
        default=defaultvalue,
        func=validate,
        class=class,
        desc=desc,
        range=range,
        org=defaultvalue,
        src=env.callee(),
        abbr=abbr,
        base_name=name,
        instance=(type(instance)=="table" or type(instance)=="userdata") and instance
    }
    for k,v in ipairs(abbr) do
        if type(v)=="string" and v~="" then
            abbr[k],cfg._commands[v:upper()]=v:upper(),cfg[name]
        end
    end

    if maxvalsize<tostring(defaultvalue):len() then
        maxvalsize=tostring(defaultvalue):len()
    end
    
    if not cfg_P then cfg._p=env.load_data(file) end
    if cfg._p[name] and cfg._p[name]~=defaultvalue then
        cfg.doset(name,cfg._p[name])
    end
end

function cfg.inject_cfg(name,callback,obj)
    cfg.init(name,"unknown",callback,env.callee(),"#hidden",'*',obj)
end

function cfg.remove(name)
    local option=cfg.exists(name)
    if not option then return end
    local src=env.callee()
    if src:gsub("#%d+","")~=option.src:gsub("#%d+","") then
        env.raise("Cannot remove setting '%s' from %s, it was defined in file %s!",name,src,_CMDS[cmd].FILE)
    end
    
    for k,v in ipairs(option.abbr) do
        cfg[v],cfg._commands[v]=nil,nil
    end
end


function cfg.temp(name,value,backup)
    name=name:upper()
    local item=cfg.exists(name)
    if not item then return end
    if (backup or item.prebackup) then
        item.org=item.value
    end
    item.prebackup=backup
    item.value=value
    env.log_debug("set",name,value)
    if env.event then
        env.event.callback("ON_SETTING_CHANGED",item.base_name,value,item.org)
    end
end

function cfg.set(name,value,backup,isdefault)
    --res,err=pcall(function()
    if not name then return cfg.show_cfg() end
    name=name:upper()
    if not value then return cfg.show_cfg(name) end
    local config=cfg.exists(name)
    if not config then return print("Cannot set ["..name.."], the parameter does not exist!") end
    if tostring(value):upper()=="DEFAULT" then
        return cfg.set(name,config.default,nil,true)
    elseif tostring(value):upper()=="BACK" then
        return cfg.restore(name)
    end

    local range= config.range
    if range and range ~='' then
        local lower,upper=range:match("([%-%+]?%d+)%s*%-%s*([%-%+]?%d+)")
        if lower then
            value,lower,upper=tonumber(value),tonumber(lower),tonumber(upper)
            if not value or not (value>=lower and value<=upper) then
                return print("Invalid value for '"..name.."', it should be "..range)
            end
        elseif range:find(",") then
            local match=0
            local v=value:lower()
            for k in range:gmatch('([^,%s]+)') do
                if v==k:lower() then
                    match,value=1,k
                end
            end
            if match==0 then
                return print("Invalid value '"..v.."' for '"..name.."', it should be one of the following values: "..range)
            end
        end
    end

    local default_type=type(config.default)
    if type(value)=="string" and default_type~="string" then
        if default_type=="number" and tonumber(value) then
            value=tonumber(value)
        elseif default_type=="boolean" and value:lower()=="true" then
            value=true
        elseif default_type=="boolean" and value:lower()=="false" then
            value=false
        end
    end
    
    local final=value
    if config.func then
        if config.instance then
            final=config.func(config.instance,config.base_name,value,isdefault)
        else
            final=config.func(config.base_name,value,isdefault)
        end
        if final==nil then return end
    end

    cfg.temp(name,final,backup)
    if maxvalsize<tostring(final):len() then
        maxvalsize=tostring(final):len()
    end
    return final
end

function cfg.doset(...)
    local args,idx={...},1
    if #args==0 or args[1]=='-a' or args[1]=='-A' then return cfg.show_cfg(args[1]) end
    if args[1]:lower()=="-p" then idx=2 end
    for i=idx,#args,2 do
        local config=cfg.exists(args[i])
        if config and config.desc and config.desc:find('^#') then
            local arg=table.concat(args,' ',i+1)
            cfg.set(args[i],arg,true)
            break;
        end;
        if i==1 and not config and env.event then
            local rtn={...}
            env.event.callback("ON_SET_NOTFOUND",rtn)
            if rtn[1]==true then break end
        end
        local value=cfg.set(args[i],args[i+1],true)
        if value and idx==2 then
            cfg._p=env.load_data(file)
            cfg._p[args[i]:upper()]=value
            if args[i+1] and args[i+1]:upper()=="DEFAULT" then
                cfg._p[args[i]:upper()]=nil
            end
            env.save_data(file,cfg._p)
        end
    end
end

function cfg.force_set(item,value)
    cfg.doset(item,value)
    if cfg._backup and cfg._backup[item:upper()] then cfg._backup[item:upper()]=cfg[item:upper()] end
end

function cfg.restore(name)
    if not name then
        return
    elseif type(name)=="table" then
        env.log_debug("set","Start restore")
        for k,v in pairs(name) do
            if v.value~=cfg.get(k) and k~="PROMPT" then
                cfg.doset(k,v.value)
                cfg[k]=v
            end
        end
        return
    end
    name=name:upper()
    env.log_debug("set","Restoring",name)
    if not cfg.exists(name) or cfg.exists(name).org==nil then return end
    cfg.set(name,cfg.exists(name).org)
end


function cfg.backup()
    local backup={}
    for k,v in pairs(cfg) do
        if k==k:upper() and type(v)=="table" and k~="PROMPT" then
            backup[k]={}
            for item,value in pairs(v) do
                backup[k][item]=value
            end
        end
    end
    env.log_debug("set","Start backup")
    return backup
end

function cfg.capture_before_cmd(command)
    if #env.RUNNING_THREADS>1 then return end
    local cmd=env._CMDS[command[1]]
    cfg._backup=cfg.backup()
    if command[1]~='SET' and cmd.ALIAS_TO~='SET' then
        env.log_debug("set","taking full backup",command[1])
        cfg._backup=cfg.backup()
    else
        cfg._backup=nil
    end
end

function cfg.capture_after_cmd(cmd,args)
    if #env.RUNNING_THREADS>1 then return end
    
    if cfg._backup then
        env.log_debug("set","taking full reset")
        cfg.restore(cfg._backup) 
    end
    cfg._backup=nil
end

function cfg.onload()
    env.event.snoop("BEFORE_COMMAND",cfg.capture_before_cmd)
    env.event.snoop("AFTER_COMMAND",cfg.capture_after_cmd)
    env.set_command{obj=nil,cmd=cfg.name, 
                    help_func="Set environment parameters. Usage: set [-a] | {[-p] <name1> [<value1|DEFAULT|BACK> [name2 ...]]}",
                    call_func=cfg.doset,
                    is_multiline=false,parameters=99,color="PROMPTCOLOR"}
end

return cfg