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

--Color definitions from MUD, not all features are support
local color=setmetatable({
        
        SET        =function(r,c) return "\27["..r..";"..c.."H" end,--set cursor position
        FRSCREEN   =function(a,b) return"\27["..a..";"..b.."r" end,
        FR         =function(a) return "\27["..a.."r" end,
        DELLINE    ="\27[K",                                        --erase the line where cursor is

        --Foreground Colors
        BLK={"\27[0;30m","Foreground Color: Black"},
        RED={"\27[0;31m","Foreground Color: Red"},
        GRN={"\27[0;32m","Foreground Color: Green"},
        YEL={"\27[0;33m","Foreground Color: Yellow"},
        BLU={"\27[0;34m","Foreground Color: Blue"},
        MAG={"\27[0;35m","Foreground Color: Magenta"},
        CYN={"\27[0;36m","Foreground Color: Cyan"},
        WHT={"\27[0;37m","Foreground Color: White"},

        --High Intensity Foreground Colors
        HIR={"\27[1;31m","High Intensity Foreground Color: Red"},
        HIG={"\27[1;32m","High Intensity Foreground Color: Green"},
        HIY={"\27[1;33m","High Intensity Foreground Color: Yellow"},
        HIB={"\27[1;34m","High Intensity Foreground Color: Blue"},
        HIM={"\27[1;35m","High Intensity Foreground Color: Magenta"},
        HIC={"\27[1;36m","High Intensity Foreground Color: Cyan"},
        HIW={"\27[1;37m","High Intensity Foreground Color: White"},

        --High Intensity Background Colors
        HBRED={"\27[41;1m","High Intensity Background Color: Red"},
        HBGRN={"\27[42;1m","High Intensity Background Color: Green"},
        HBYEL={"\27[43;1m","High Intensity Background Color: Yellow"},
        HBBLU={"\27[44;1m","High Intensity Background Color: Blue"},
        HBMAG={"\27[45;1m","High Intensity Background Color: Magenta"},
        HBCYN={"\27[46;1m","High Intensity Background Color: Cyan"},
        HBWHT={"\27[47;1m","High Intensity Background Color: White"},

        --Background Colors
        BBLK={"\27[40m","Background Color: Black"},
        BRED={"\27[41m","Background Color: Red"},
        BGRN={"\27[42m","Background Color: Green"},
        BYEL={"\27[43m","Background Color: Yellow"},
        BBLU={"\27[44m","Background Color: Blue"},
        BMAG={"\27[45m","Background Color: Magenta"},
        BCYN={"\27[46m","Background Color: Cyan"},
        BWHT={"\27[47m","Background Color: White"},
        NOR ={"\27[0;0m","Puts every color back to normal"},

        --Additional ansi Esc codes added to ansi.h by Gothic  april 23,1993
        --Note, these are Esc codes for VT100 terminals, and emmulators
        --and they may not all work within the mud
        BOLD    ="\27[1m",     --Turn on bold mode
        CLR     ="\27[2J",     --Clear the screen
        HOME    ="\27[H",      --Send cursor to home position
        REF     ="\27[2J;H" ,  --Clear screen and home cursor
        BIGTOP  ="\27#3",      --Dbl height characters, top half
        BIGBOT  ="\27#4",      --Dbl height characters, bottem half
        SAVEC   ="\27[s",      --Save cursor position
        REST    ="\27[u",      --Restore cursor to saved position
        REVINDEX="\27M",       --Scroll screen in opposite direction
        SINGW   ="\27#5",      --Normal, single-width characters
        DBL     ="\27#6",      --Creates double-width characters
        FRTOP   ="\27[2;25r",  --Freeze top line
        FRBOT   ="\27[1;24r",  --Freeze bottom line
        UNFR    ="\27[r",      --Unfreeze top and bottom lines
        BLINK   ="\27[5m",     --Initialize blink mode
        U       ="\27[4m",     --Initialize underscore mode
        REV     ="\27[7m",     --Turns reverse video mode on
        HIREV   ="\27[1,7m",   --Hi intensity reverse video  

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

function ansi.string_color(code,...)
    if not code then return end
    local c=color[code:upper()]
    if not c then return end
    if type(c)=="table" then return c[1] end
    if type(c)=="function" then return c(select(1,...) or 1,select(2,...) or 1) end
    return c
end

local nor=ansi.string_color('NOR')
function ansi.mask(codes,msg,continue)
    if not enabled then return msg end
    local str
    for v in codes:gmatch("([^; \t,]+)") do
        v=v:upper()
        local c=ansi.string_color(v)
        if not c then 
            v=ansi.cfg(v) or "" 
        else
            if not str then
                str=c
            else
                str=str:gsub("([%d;]+)","%1;"..c:match("([%d;]+)"),1)
            end
        end
    end
    return str and (str..msg..(continue and "" or nor)) or msg
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
    value=value:gsub("%$(%u+)%$",'%1')
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

function ansi.get_color(name,...)
    --io.stdout:write(name,ansi.cfg(name),enabled and 1 or 0)
    if not name or not enabled then return "" end
    name=name:upper()
    if color[name] then return ansi.string_color(name,...) or "" end
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
    env.set_command(nil,'ansi',"Show and test ansi colors, run 'ansi' for more details",ansi.test_text,false,2)
    ansi.color,ansi.map=color,cfg
end

function ansi.strip_ansi(str)
    if not enabled then return str end
    return str:gsub("\27%[[%d;]*[mK]","")
end

function ansi.strip_len(str)
    return #ansi.strip_ansi(str)
end

function ansi.convert_ansi(str)
    return str and str:gsub("%$((%u+)([, ]?)(%d*)([, ]?)(%d*))%$",
        function(all,code,x,pos1,x,pos2) 
            return ansi.string_color(code,pos1,pos2) or '$'..all..'$' 
        end)
end

function ansi.test_text(str)
    if not str or str=="" then
        local bf,wf,bb,wb=ansi.string_color('BLK'),ansi.string_color('WHT'),ansi.string_color('BBLK'),ansi.string_color('BWHT')
        if env.grid then
            local row=env.grid.new()
            local is_bg
            local fmt="%s%s"..nor
            row:add{"Color Code","B or F Ground","Description#1","Description#2"}
            for k,v in pairs(color) do
                if type(v)=="table" then
                    is_bg=k:match("^HB") or k:match("^B") and not k~='BLK'
                    row:add{k,is_bg and 'Background' or 'Foreground',fmt:format(is_bg and wf..v[1] or v[1]..wb,v[2]),fmt:format(is_bg and bf..v[1] or v[1]..bb,v[2])}
                end
            end
            row:sort("2,1",true)
            row:print()
        end
        rawprint(env.space..string.rep("=",100))
        rawprint(env.space.."Use '$<code>$<other text' to mask color in all outputs, including query, echo, etc.")
        rawprint(env.space.."For more ansi code, refer to the 'color' block in file 'lua/ansi.lua'.")
        rawprint(env.space.."Run 'ansi <text> to test color, i.e.: ansi $HIR$ Hello $GRN$$BWHT$ ANSI!")
        rawprint(env.space.."Or:  select '$HIR$'||owner||'$NOR$.'||object_name obj from all_objects where rownum<10;")
        return
    end
   
    return rawprint(env.space.."ANSI result: "..ansi.convert_ansi(str)..nor)
end


return ansi