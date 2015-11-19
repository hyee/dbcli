local env=env
local cfg,grid={name='SET'},env.grid
local maxvalsize=20
local file='setting.dat'
local root_cmd
cfg._backup=nil


function cfg.show_cfg(name)
    local rows={{'Name','Value','Default','Class','Available Values','Description'}}
    print([[Usage: set      <name>                                  : Get specific parmeter value
       set -a                                           : Show abbrs and source.
       set      <name1> <value1> [<name2> <value2> ...] : Change settings in current window
       set -p   <name1> <value1> [<name2> <value2> ...] : Change settings permanently
       set [-p] <name1> default  [<name2> back     ...] : Change settings back to the default/previous values
    ]])
    if name and name~='-a' and name~='-A' then
        local v=cfg.exists(name)
        table.insert(rows,{name,string.from(v.value),string.from(v.default),v.class,v.range or '*',v.desc})
    else
        if name then table.insert(rows[1],2,"Source") end
        for k,v in pairs(cfg) do
            if type(v)=="table" and k==k:upper() and v.src then
                table.insert(rows,{
                    name and table.concat(cfg[k].abbr,', ') or k,
                    string.from(cfg[k].value),
                    string.from(cfg[k].default),
                    cfg[k].class,cfg[k].range or '*',
                    cfg[k].desc})
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

function cfg.init(name,defaultvalue,validate,class,desc,range)
    cfg._p=env.load_data(file)
    local abbr={name}
    if type(name)=="table" then
        abbr=name
        name=abbr[1]
    end
    name=name:upper()
    if cfg.exists(name) then
        env.raise("Environment parameter '%s' has been defined in %s!",name,cfg.exists(name).src)
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
        abbr=abbr
    }
    for k,v in ipairs(abbr) do
        if type(v)=="string" and v~="" then
            abbr[k],cfg._commands[v:upper()]=v:upper(),cfg[name]
        end
    end
    if maxvalsize<tostring(defaultvalue):len() then
        maxvalsize=tostring(defaultvalue):len()
    end
    if cfg._p[name] and cfg._p[name]~=defaultvalue then
        cfg.doset(name,cfg._p[name])
    end
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
    if not cfg.exists(name) then return end
    if backup or cfg.exists(name).prebackup then
        cfg.exists(name).org=cfg.exists(name).value
    end
    cfg.exists(name).prebackup=backup
    cfg.exists(name).value=value
    env.log_debug("set",name,value)
    if env.event then
        env.event.callback("ON_SETTING_CHANGED",name,value,cfg.exists(name).org)
    end
end

function cfg.set(name,value,backup,isdefault)
    --res,err=pcall(function()
    if not name then return cfg.show_cfg() end
    name=name:upper()
    if not cfg.exists(name) then return print("Cannot set ["..name.."], the parameter does not exist!") end
    if not value then return cfg.show_cfg(name) end

    if tostring(value):upper()=="DEFAULT" then
        return cfg.set(name,cfg.exists(name).default,nil,true)
    elseif tostring(value):upper()=="BACK" then
        return cfg.restore(name)
    end

    local range= cfg.exists(name).range
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
                    match=1
                end
            end
            if match==0 then
                return print("Invalid value '"..v.."' for '"..name.."', it should be one of the following values: "..range)
            end
        end
    end

    local final=value

    if cfg.exists(name).func then
        final=cfg.exists(name).func(name,value,isdefault)
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
    env.log_debug("set","taking full backup",command[1])
    if command[1]~=cfg.name then
        cfg._backup=cfg.backup()
    else
        cfg._backup=nil
    end
end

function cfg.capture_after_cmd(cmd,args)
    if #env.RUNNING_THREADS>1 then return end
    env.log_debug("set","taking full reset")
    if cfg._backup then cfg.restore(cfg._backup) end
    cfg._backup=nil
end

function cfg.onload()
    event.snoop("BEFORE_COMMAND",cfg.capture_before_cmd)
    event.snoop("AFTER_COMMAND",cfg.capture_after_cmd)
    env.set_command(nil,cfg.name,"Set environment parameters. Usage: set [-a] | {[-p] <name1> [<value1|DEFAULT|BACK> [name2 ...]]}",cfg.doset,false,99)
end

return cfg