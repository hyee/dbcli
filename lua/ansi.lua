local rawget,env=rawget,env
local ansi={}
local cfg
local reader,writer,str_completer,arg_completer,add=reader
local terminal=reader:getTerminal()
local isAnsiSupported=terminal:isAnsiSupported()
local enabled=isAnsiSupported

ansi.ansi_mode=os.getenv("ANSICON_CMD")
if not ansi.ansi_mode or ansi.ansi_mode:gsub("[ \t]","")=="" then 
    ansi.ansi_mode="jline"
else
    ansi.ansi_mode="ansicon"
end

local color=setmetatable({
    BLK = "\27[30m", -- Black 
    RED = "\27[31m", -- Red 
    GRN = "\27[32m", -- Green 
    YEL = "\27[33m", -- Yellow 
    BLU = "\27[34m", -- Blue
    MAG = "\27[35m", -- Magenta
    CYN = "\27[36m", -- Cyan 
    WHT = "\27[37m", -- White

    GRAY=  "\27[1;30;40m", --BG Light gray
    XXX=  "\27[48;5;15m", --BG Light gray
    DCY=  "\27[0;36m", --Dark Cyan

    HIR = "\27[31m", -- Light Red 
    HIG = "\27[1;32m", -- Light Green
    HIY = "\27[1;33m", -- Light Yellow 
    HIB = "\27[1;34m", -- Light Blue 
    HIM = "\27[1;35m", -- Light Magenta 
    HIC = "\27[1;36m", -- Light Cyan 
    HIW = "\27[1;37m", -- Light White
    DEF = "\27[39m", -- default FG color 

    --background color
    HBRED = "\27[41;1m", -- BG Light Red  
    HBGRN = "\27[42;1m", -- BG Light Green
    HBYEL = "\27[43;1m", -- BG Light Yellow 
    HBBLU = "\27[44;1m", -- BG Light Blue  
    HBMAG = "\27[45;1m", -- BG Light Magenta 
    HBCYN = "\27[46;1m", -- BG Light Cyan 
    HBWHT = "\27[47;1m", -- BG Light White
    HBBLK = "\27[40;1m", -- BG Light Black
    HBGRY=  "\27[0;37;47m", --BG Light gray

    BBLK = "\27[40m", -- BG Black
    BRED = "\27[41m", -- BG Red
    BGRN = "\27[42m", -- BG Green 
    BYEL = "\27[43m", -- BG Yellow
    BBLU = "\27[44m", -- BG Blue
    BMAG = "\27[45m", -- BG Magenta 
    BCYN = "\27[46m", -- BG Cyan 
    BDEF = "\27[49m", -- default BG color 

    NOR = "\27[0m", -- Reset 

    BOLD = "\27[1m", -- Bold
    ITL = "\27[3m", -- ITalics
    UDL = "\27[4m", -- Underline
    BLINK = "\27[5m", -- Blink 
    REV = "\27[7m", -- Reverse
    HIREV = "\27[1;7m", -- Revers and light color    
    HIDE = "\27[8m", -- Hidden
    

    CLR = "\27[2J", -- Clear Screen
    HOME = "\27[H", -- Send cursor back 
    REFCLR = "\27[2J;H", -- clean and reset cursor    
    SAVEC = "\27[s", -- Save cursor position 
    REST = "\27[u", -- Restore cursor to saved position 
    
    FRTOP = "\27[2;25r", -- Freeze first line
    FRBOT = "\27[1;24r", -- Freeze last line
    UNFR = "\27[r", -- Free 1st/last lines 
        
    },{
    __index=function(self,k)
        return rawget(self,k:upper())
    end
})



function ansi.cfg(name,value,module,description)
    if not cfg then cfg={} end
    if not name then return cfg end
    if not cfg[name] then cfg[name]={} end
    if not value then return cfg[name][1] end
    cfg[name][1]=value
    if description then
        cfg[name][2]=module
        cfg[name][3]=description
        cfg[name][4]=value
    end
end

function ansi.mask(codes,msg,continue)    
    if not enabled then return msg end    
    local str
    for v in codes:gmatch("([^;%s\t,]+)") do
        v=v:upper()
        if not color[v] then v=ansi.cfg(v) or "" end
        if color[v] then
            if not str then
                str=color[v] 
            else
                str=str:gsub("([%d;]+)","%1;"..color[v]:match("([%d;]+)"),1)
            end
        end
    end
    return str and (str..msg..(continue and "" or color.NOR)) or msg
end

function ansi.addCompleter(name,args)
--[[
    if not reader then return end
    if type(name)~='table' then
        name={tostring(name)}        
    end

    local c=str_completer:new(table.unpack(name))
    for i,k in ipairs(name) do name[i]=tostring(k):lower() end
    c=str_completer:new(table.unpack(name))
    reader:addCompleter(c)
    if type(args)=="table" then
        for i,k in ipairs(args) do args[i]=tostring(k):lower() end
        for i,k in ipairs(name) do
            c=arg_completer:new(str_completer:new(k,table.unpack(args)))
            reader:addCompleter(c)
        end
    end
--]]
end

function ansi.clear_sceen()
    os.execute(env.OS == "windows" and "cls" or "clear")
end

function ansi.define_color(name,value,module,description)
    if not value or not enabled then return end
    name,value=name:upper(),value:upper()    
    env.checkerr(not color[name],"Cannot define color ["..name.."] as a name!")
    if ansi.mask(value,"")=="" then
        env.raise("Undefined color code ["..value.."]!")
    end
    
    if description then
        ansi.cfg(name,ansi.cfg(name) or value,module,description)
        env.set.init(name,value,ansi.define_color,module,description)
        if value ~= ansi.cfg(name) then
            env.set.force_set(name,ansi.cfg(name))
        end        
    else        
        ansi.cfg(name,value)
        return value
    end
end

function ansi.get_color(name)
    --io.stdout:write(name,ansi.cfg(name),enabled and 1 or 0)
    if not name or not enabled then return "" end
    name=name:upper()    
    if color[name] then return color[name] end    
    return ansi.cfg(name) and ansi.mask(ansi.cfg(name),"",true) or ""    
end

function ansi.enable_color(name,value)
    if not isAnsiSupported then return 'off' end
    if value=="off" then
        if not enabled then return end
        --env.remove_command("clear")
        for k,v in pairs(ansi.cfg()) do
            env.set.remove(k)
        end
        enabled=false
    else
        if enabled then return end
        --env.set_command(nil,{"clear","cls"},"Clear screen ",ansi.clear_sceen,false,1)
        for k,v in pairs(ansi.map or {}) do
            env.set.init(k,v[4],ansi.define_color,v[2],v[3])
            if v[1] ~= v[4] then
                env.set.doset(k,v[1])
            end
        end
        enabled=true
    end
    return value
end

function ansi.onload()
    env.set_command(nil,{"clear","cls"},"Clear screen ",ansi.clear_sceen,false,1)
    writer=reader:getOutput()
    ansi.loaded=true
    str_completer=java.require("jline.console.completer.StringsCompleter",true)
    arg_completer=java.require("jline.console.completer.ArgumentCompleter",true)
    if not isAnsiSupported then
        for k,v in pairs(color) do color[k]='' end
    end
    env.set.init("ansicolor",isAnsiSupported and 'on' or 'off',ansi.enable_color,"core","Enable color masking inside the intepreter.",'on,off')
    ansi.color,ansi.map=color,cfg
end

function ansi.strip_ansi(str)
    if not enabled then return str end
    return str:gsub("\27%[[%d;]*[mK]","")
end

function ansi.strip_len(str)
    return #ansi.strip_ansi(str)
end


return ansi