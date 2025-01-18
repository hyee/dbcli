local rawget,env=rawget,env
local ansi={}
local cfg
local reader,writer,str_completer,arg_completer,add=reader
local terminal=reader:getTerminal()
local isAnsiSupported=true
local pcall,type,select,pairs,tonumber,table,tostring=pcall,type,select,pairs,tonumber,table,tostring

local enabled=isAnsiSupported
--[[https://stackoverflow.com/questions/4842424/list-of-ansi-color-escape-sequences
    http://ascii-table.com/ansi-escape-sequences-vt-100.php
    https://conemu.github.io/en/AnsiEscapeCodes.html
╔══════════╦════════════════════════════════╦═════════════════════════════════════════════════════════════════════════╗
║  Code    ║             Effect             ║                                   Note                                  ║
╠══════════╬════════════════════════════════╬═════════════════════════════════════════════════════════════════════════╣
║ 0        ║  Reset / Normal                ║  all attributes off                                                     ║
║ 1        ║  Bold or increased intensity   ║                                                                         ║
║ 2        ║  Faint (decreased intensity)   ║  Not widely supported.                                                  ║
║ 3        ║  Italic                        ║  Not widely supported. Sometimes treated as inverse.                    ║
║ 4        ║  Underline                     ║                                                                         ║
║ 5        ║  Slow Blink                    ║  less than 150 per minute                                               ║
║ 6        ║  Rapid Blink                   ║  MS-DOS ANSI.SYS; 150+ per minute; not widely supported                 ║
║ 7        ║  reverse video                 ║  swap foreground and background colors                                  ║
║ 8        ║  Conceal                       ║  Not widely supported.                                                  ║
║ 9        ║  Crossed-out                   ║  Characters legible, but marked for deletion.  Not widely supported.    ║
║ 10       ║  Primary(default) font         ║                                                                         ║
║ 11–19    ║  Alternate font                ║  Select alternate font `n-10`                                           ║
║ 20       ║  Fraktur                       ║  hardly ever supported                                                  ║
║ 21       ║  Bold off or Double Underline  ║  Bold off not widely supported; double underline hardly ever supported. ║
║ 22       ║  Normal color or intensity     ║  Neither bold nor faint                                                 ║
║ 23       ║  Not italic, not Fraktur       ║                                                                         ║
║ 24       ║  Underline off                 ║  Not singly or doubly underlined                                        ║
║ 25       ║  Blink off                     ║                                                                         ║
║ 27       ║  Inverse off                   ║                                                                         ║
║ 28       ║  Reveal                        ║  conceal off                                                            ║
║ 29       ║  Not crossed out               ║                                                                         ║
║ 30–37    ║  Set foreground color          ║  See color table below                                                  ║
║ 38       ║  Set foreground color          ║  Next arguments are `5;n` or `2;r;g;b`, see below                       ║
║ 39       ║  Default foreground color      ║  implementation defined (according to standard)                         ║
║ 40–47    ║  Set background color          ║  See color table below                                                  ║
║ 48       ║  Set background color          ║  Next arguments are `5;n` or `2;r;g;b`, see below                       ║
║ 49       ║  Default background color      ║  implementation defined (according to standard)                         ║
║ 51       ║  Framed                        ║                                                                         ║
║ 52       ║  Encircled                     ║                                                                         ║
║ 53       ║  Overlined                     ║                                                                         ║
║ 54       ║  Not framed or encircled       ║                                                                         ║
║ 55       ║  Not overlined                 ║                                                                         ║
║ 60       ║  ideogram underline            ║  hardly ever supported                                                  ║
║ 61       ║  ideogram double underline     ║  hardly ever supported                                                  ║
║ 62       ║  ideogram overline             ║  hardly ever supported                                                  ║
║ 63       ║  ideogram double overline      ║  hardly ever supported                                                  ║
║ 64       ║  ideogram stress marking       ║  hardly ever supported                                                  ║
║ 65       ║  ideogram attributes off       ║  reset the effects of all of 60-64                                      ║
║ 90–97    ║  Set bright foreground color   ║  aixterm (not in standard)                                              ║
║ 100–107  ║  Set bright background color   ║  aixterm (not in standard)                                              ║
╚══════════╩════════════════════════════════╩═════════════════════════════════════════════════════════════════════════╝
--]]--

--Color definitions from MUD, not all features are support in Ansicon/Jansi library
local base_color={
    --For the ansi controls that have parameter, used '$<code>[,parameters]$' format
    --For example: $SET,1,2$ 
    SET        =function(r,c) return "\27["..r..";"..c.."H" end, --'Set Cursor position, Usage: SET,<n rows>,<n cols>'
--  FRSCREEN   =function(a,b) return"\27["..a..";"..b.."r" end,
--  FR         =function(a) return "\27["..a.."r" end,
    DELLINE    ={"\27[1K\27[1G",'Erase the whole line',nil,1},
    DELAFT     ={"\27[0K",'Erase from cursor to the end of line',nil,1},


    --Foreground Colors
    BLK={"\27[0;30m","Foreground Color: Black",'color:black'},
    RED={"\27[0;31m","Foreground Color: Red",'color:FireBrick'},
    GRN={"\27[0;32m","Foreground Color: Green",'color:DarkGreen'},
    YEL={"\27[0;33m","Foreground Color: Yellow",'color:GoldenRod'},
    BLU={"\27[0;34m","Foreground Color: Blue",'color:DarkBlue'},
    MAG={"\27[0;35m","Foreground Color: Magenta",'color:DarkMagenta'},
    CYN={"\27[0;36m","Foreground Color: Cyan",'color:DarkCyan'},
    WHT={"\27[0;37m","Foreground Color: White",'color:GhostWhite'},
    GRY={"\27[90m","Foreground Color: Gray",'color:Gray'},
    --GRY={"\27[30;1;40m","Foreground Color: Gray"}, 

    --High Intensity Foreground Colors
   --BG Light gray
    HIR={"\27[91m","High Intensity Foreground Color: Red",'color:Red'},
    HIG={"\27[92m","High Intensity Foreground Color: Green",'color:Green'},
    HIY={"\27[93m","High Intensity Foreground Color: Yellow",'color:Yellow'},
    HIB={"\27[94m","High Intensity Foreground Color: Blue",'color:Blue'},
    HIM={"\27[95m","High Intensity Foreground Color: Magenta",'color:Magenta'},
    HIC={"\27[96m","High Intensity Foreground Color: Cyan",'color:LightCyan'},
    HIW={"\27[97m","High Intensity Foreground Color: White",'color:white'},

    --High Intensity Background Colors
    HBRED={"\27[101m","High Intensity Background Color: Red",'background:Red'},
    HBGRN={"\27[102m","High Intensity Background Color: Green",'background:Green'},
    HBYEL={"\27[103m","High Intensity Background Color: Yellow",'background:Yellow'},
    HBBLU={"\27[104m","High Intensity Background Color: Blue",'background:Blue'},
    HBMAG={"\27[105m","High Intensity Background Color: Magenta",'background:Magenta'},
    HBCYN={"\27[106m","High Intensity Background Color: Cyan",'background:Cyan'},
    HBWHT={"\27[107m","High Intensity Background Color: White",'background:White'},    

    --Background Colors
    BBLK={"\27[40m","Background Color: Black",'background:black'},
    BRED={"\27[41m","Background Color: Red",'background:FireBrick'},
    BGRN={"\27[42m","Background Color: Green",'background:DarkGreen'},
    BYEL={"\27[43m","Background Color: Yellow",'background:GoldenRod'},
    BBLU={"\27[44m","Background Color: Blue",'background:DarkBlue'},
    BMAG={"\27[45m","Background Color: Magenta",'background:DarkMagenta'},
    BCYN={"\27[46m","Background Color: Cyan",'background:DarkCyan'},
    BWHT={"\27[47m","Background Color: White",'background:GhostWhite'},
    BGRY={"\27[100m","Background Color: Gray",'background:gray'}, 
    NOR ={"\27[39;49;0m","Puts every color back to normal",'\0'},


    --Additional ansi Esc codes added to ansi.h by Gothic  april 23,1993
    --Note, these are Esc codes for VT100 terminals, and emmulators
    --and they may not all work within the mud
    RESET   ={"\27[0m","Reset",nil,0},
    BOLD    ={"\27[1m","Turn on  Bright Or Bold",nil,0}, 
    UBOLD   ={"\27[2m","Turn off Bright Or Bold",nil,0}, 
    ITA     ={"\27[3m","Turn on  Italic Or Inverse",nil,0}, 
    BKP     ={'\27[?2004h',"Turn on bracketed paste",nil,1},
    UBKP    ={'\27[?2004l',"Turn off bracketed paste",nil,1},
    CLR     ={"\27C\27[3J","Clear the screen",nil,1},
    HOME    ={"\27[H","Send cursor to home position",nil,1},
    REF     ={"\27[2J;H" , "Clear screen and home cursor",nil,1},
    KILLBL  ={"\27[0J","Clear from cursor to end of screen",nil,1},
    BIGTOP  ={"\27#3","Dbl height characters, top half",nil,1},
    BIGBOT  ={"\27#4","Dbl height characters, bottem half",nil,1},
    SAVEC   ={"\27[s","Save cursor position",nil,1},
    REST    ={"\27[u","Restore cursor to saved position",nil,1},
 -- REVINDEX={"\27M","Scroll screen in opposite direction",1},
 -- SINGW   ={"\27#5","Normal, single-width characters",1},
 -- DBL     ={"\27#6","Creates double-width characters",1},
 -- FRTOP   ={"\27[2;25r","Freeze top line",1},
 -- FRBOT   ={"\27[1;24r","Freeze bottom line",1},
 -- UNFR    ={"\27[r","Unfreeze top and bottom lines",1},
    BLINK   ={"\27[5m","Blink on",nil,0},
    BLINK2  ={"\27[6m","Blink on",nil,0},
    UBLNK   ={"\27[25m","Blink off",nil,0},
    UBLNK2  ={"\27[26m","Blink off",nil,0},
    UDL     ={"\27[4m","Underline on",nil,0},
    UUDL    ={"\27[24m","Underline off",nil,0},
    REV     ={"\27[7m","Reverse video mode on",nil,0},
    UREV    ={"\27[27m","Reverse video mode off",nil,0},
    CONC    ={"\27[8m","Concealed(foreground becomes background)",nil,0},
    UCONC   ={"\27[28m","Concealed off",nil,0},
    CROSS   ={"\27[9m","Crossline on",nil,0},
    UCROSS  ={"\27[29m","Crossline off",nil,0},
    HIREV   ={"\27[1,7m","High intensity reverse video",nil,0},
    WRAP    ={"\27[?7h","Wrap lines at screen edge",nil,1},
    UNWRAP  ={"\27[?7l","Don't wrap lines at screen edge",nil,1}

    --CLIP ={"\27]52;c;%s\7"}
}

local default_color={
    ['0']={'BBLK','BLK'},
    ['1']={'BBLU','BLU'},
    ['2']={'BGRN','GRN'},
    ['3']={'BCYN','CYN'},
    ['4']={'BRED','RED'},
    ['5']={'BMAG','MAG'},
    ['6']={'BYEL','YEL'},
    ['7']={'BWHT','WHT'},
    ['8']={'BGRY','GRY'},
    ['9']={'HBBLU','HIB'},
    ['A']={'HBGRN','HIG'},
    ['B']={'HBCYN','HIC'},
    ['C']={'HBRED','HIR'},
    ['D']={'HBMAG','HIM'},
    ['E']={'HBYEL','HIY'},
    ['F']={'HBWHT','HIW'},
}

local color_map={}

local var=os.getenv("ANSICOLOR")
if var and var:lower()=="off" then
    isAnsiSupported,enabled=false,false
else
    isAnsiSupported=true
end

ansi.ansi_mode=os.getenv("ANSICON_DEF") or "jline"
ansi.escape="%f[\\]\\[eE](%[[%d;]*[mMK])"
ansi.pattern="\27%[[%d;]*[mK]"

local console_color=os.getenv("CONSOLE_COLOR")
if isAnsiSupported and console_color and console_color~='NA' then
    ansi.ansi_default=console_color
    local fg,bg=default_color[console_color:sub(2)][2] or '',default_color[console_color:sub(1,1)][1] or ''
    --if bg and fg and env.IS_WINDOWS then
    --    base_color['NOR'][1]=base_color['NOR'][1]..base_color[fg][1]..base_color[bg][1]
    --end
end

local color=setmetatable({},{__index=function(self,k) return rawget(self,k:upper()) end})

function ansi.cfg(name,value,module,description)
    if not cfg then cfg={} end
    if not name then return cfg end
    name=name:upper()
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
    local c,count=code:gsub(ansi.escape,function(m) return '\27'..m:gsub('M','m') end)
    if count>0 then return c end
    c=color[code:upper()]
    if not c then return end
    if type(c)=="table" then return c[1] end
    local v1,v2=select(1,...) or '',select(2,...) or ''
    if type(c)=="function" then return c(v1~='' and v1 or 1,v2~='' and v2 or 1) end
    return c
end

function ansi.mask(codes,msg,continue,cfg_name)
    if codes==nil then return msg end
    local combines,str
    if color_map[codes] and not cfg_name then
        str=base_color[codes][1]
    else
        for v in codes:gmatch(codes:find('[\\]?[eE]%[') and ('[\\]?[eE][^eE\\]+') or "([^; \t,]+)") do
            local c=ansi.string_color(v:find('^[eE]%[') and '\\'..v or v)
            if not c then
                local v1=ansi.cfg(v)
                if v1 then return ansi.mask(v1,msg,continue,v) end
            else
                if not str then
                    str,combines=c,{color_map[c]}
                elseif c~="" then
                    combines[#combines+1]=color_map[c]
                    str=str:gsub("([%d;]+)","%1;"..c:match("([%d;]+)"),1)
                end
            end
        end

        if combines and #combines>1 then
            local desc,css={},{}
            for i,color in ipairs(combines) do
                desc[i],css[i]=color[2],color[3]
            end
            local color={str,table.concat(desc,';'),table.concat(css,';')}
            color[0]=cfg_name or codes
            color_map[color[0]],color_map[str]=color,color
        end
    end

    if str and not enabled then str="" end
    if not continue then
        continue=ansi.string_color('NOR')
    elseif type(continue)=='string' then
        continue=ansi.string_color(continue:match("([^; \t,]+)"))
    else
        continue=''
    end
    return str and (str..(msg or "")..continue) or msg
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

function ansi.clear_screen()
    os.execute(env.PLATFORM=='windows' and "cls" or "clear")
    reader:clearScreen();
end

function ansi.define_color(name,value,module,description)
    if not value or not enabled then
        if description then
            ansi.cfg(name,value,module,description)
        end
        return
    end
    name,value=name:upper(),value:upper()
    value=value:gsub("%$(%u+)%$",'%1'):gsub('[\\%$]E%[','E[')
    env.checkerr(not color[name],"Cannot define color ["..name.."] as a name!")
    if ansi.mask(value,"")=="" then
        env.raise("Undefined color code: "..value.."!")
    end

    if description then
        local v=os.getenv(name:upper()) 
        value = v and v:upper():gsub("%$(%u+)%$",'%1'):gsub('[\\%$]E%[','E[') or value
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
    local c=ansi.string_color(name,...)
    return c and c or ansi.cfg(name) and ansi.mask(ansi.cfg(name),"",true,name) or ""
end

function ansi.enable_color(name,value)
    if not isAnsiSupported then return 'off' end
    if value=="off" then
        if not enabled then return end
        --env.remove_command("clear")
        for k,v in pairs(ansi.cfg()) do env.set.remove(k) end
        for k,v in pairs(base_color) do color[k]="" end
        enabled=false
    else
        if enabled then return end
        for k,v in pairs(base_color) do color[k]=v end
        for k,v in pairs(ansi.cfg() or {}) do
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
    env.set_command(nil,{"clear","cls","cl"},"Clear screen ",ansi.clear_screen,false,1)
    writer=console:getOutput()
    ansi.loaded=true
    --str_completer=java.require("jline.console.completer.StringsCompleter",true)
    --arg_completer=java.require("jline.console.completer.ArgumentCompleter",true)
    for k,v in pairs(base_color) do 
        color[k]=isAnsiSupported and v or ''
        if type(v)=='table' and v[1] then
            v[0]=k
            color_map[v[1]]=v
        end
    end
    env.set.init("ansicolor",isAnsiSupported and 'on' or 'off',ansi.enable_color,"core","Enable color masking inside the intepreter.",'on,off')
    env.set_command(nil,'ansi',"Show and test ansi colors, run '@@NAME' for more details",ansi.test_text,false,2)
    ansi.color,ansi.map=color,cfg
end

local function _strip_repl(s)
    return (ansi.cfg(s) or color[s]) and '' or "$"..s.."$"
end

local function _strip_ansi(str,func)
    local func_=nil
    if type(func)=='function' then 
        func_=function(s) return func(s,color_map[s]) end
    end
    return str:gsub(ansi.escape,function(m) return '\27'..m:gsub('M','m') end)
              :gsub(ansi.pattern,func_ or '')
              :gsub("%$(%u+)%$",function(s)
                  local s1=ansi.cfg(s) or color[s]
                  if s1 then
                      return func_ and func_(s1) or ''
                  end
                  return "$"..s.."$"
               end)
end

local ulen=console.ulen
--returns byte length, char length, and final string after limiting the max length
function string.ulen(s,maxlen)
    if s=="" then return 0,0,s end
    if not s then return nil end
    if maxlen==0 then return 0,0,'' end
    local s1,len1,len2=tostring(s)
    len1=#s1
    local is_ansi,is_unicode=s1:find('\27[',1,true),s1:sub(1,1024):find('[\127-\255]')
    if (maxlen and maxlen>0 and len1>maxlen and is_ansi) or is_unicode then
        len1,len2,s1=ulen(console,s1,tonumber(maxlen) or 0):match("(%d+):(%d+):(.*)")
        len1,len2,s1=tonumber(len1) or 0,tonumber(len2) or 0,maxlen and s1 or s
        if is_unicode then
            len1=#(is_ansi and s1:strip_ansi() or s1)
        end
    else
        if (maxlen or 0)>0 and len1>maxlen then 
            s1=s1:sub(1,maxlen)
            len1=#s1
        end
        len2=is_ansi and #s1:strip_ansi() or len1
    end
    return len1,len2,s1
end

function ansi.strip_ansi(str,func)
    local e,s=pcall(_strip_ansi,str,func)
    return s
end

function string.strip_ansi(str)
    return ansi.strip_ansi(str)
end

function ansi.strip_len(str,siz)
    local len1,len2= ansi.strip_ansi(str):ulen(siz)
    return len2
end

function string.strip_len(str,siz)
    return ansi.strip_len(str,siz)
end

local function cv(all,code)
    return ansi.mask(code,nil,true) or all
end

function ansi.convert_ansi(str)
    return str and str:gsub("(%$(%u+)%$)",cv):gsub(ansi.escape,"\27%1")
end

function string.convert_ansi(str)
    return ansi.convert_ansi(str)
end

local grp1,grp2,grp3,grp3=table.new(10,0),table.new(10,0),table.new(10,0),table.new(10,0)
function string.from_ansi(str)
    if type(str)~='string' then return str,nil,nil,str end
    local str1=str:convert_ansi()
    if str1==str then return str end
    local len,first,ed,ec,grp,last,curr=#str1
    for plain,color,cnt,start,stop in str1:gsplit(ansi.pattern) do
        if not start then
            if not grp then return str,first,last,str1 end
            if type(grp)=='string' then 
                grp={grp,plain} 
            else
                grp[#grp+1]=plain
            end
            return table.concat(grp,''),first,last,str1
        end

        if plain~='' then
            if not grp then 
                grp=plain 
            elseif type(grp)=='string' then
                grp={grp,plain}
            else
                grp[#grp+1]=plain
            end
        end
        --print(j,len,color=='')
        if color~='' then
            if start==1 then
                first=color
                ed=stop
            elseif ed and ed+1==start then
                first=first..color
                ed=stop 
            elseif stop==len then
                if ec and ec+1==start then
                    last=curr..color
                else
                    last=color
                end
            else
                if ec and ec+1==start then
                    curr=curr..color
                else
                    curr=color
                end
                ec=stop
            end
        end
    end
end

function string.to_ansi(str,st,ed)
    if not st then return str end
    return st..str..(ed or '')
end

function ansi.test_text(str)
    if not isAnsiSupported then return print("Ansi color support is disabled!") end
    if not str or str=="" then
        local rows=env.grid.new()

        local rep=function(escapes) return 
            escapes:gsub("($E%[)(%d+)(.*)",function(e,bg,code)
                return string.format("%s%-12s%s","\\e["..bg..code,e..code:sub(2),ansi.get_color("NOR"))
            end) 
        end
        local backs={}
        for i=0,31 do
            local foreground,background,head={},{},{}
            for j=0,7 do
                local code=i*8+j
                head[j*2+1],head[j*2+2]="Color#"..(j+1)..' + B',"Color#"..(j+1)..' + W'
                foreground[j*2+1]=rep("$E[40;38;5;"..code..'m')
                foreground[j*2+2]=rep("$E[107;38;5;"..code..'m')
                background[j*2+1]=rep("$E[30;48;5;"..code..'m')
                background[j*2+2]=rep("$E[97;48;5;"..code..'m')
            end
            if i==0 then
                table.insert(head,1,"F/B Ground")
                rows:add(head)
            end
            table.insert(foreground,1,"Foreground")
            table.insert(background,1,"Background")
            rows:add(foreground)
            backs[#backs+1]=background
        end
        for k,v in ipairs(backs) do rows:add(v) end
        rawprint(env.space.."ANSI 256 colors, where '$E' means ascii code 27(a.k.a chr(27)): ")
        rawprint(env.space..string.rep("=",140))
        rows:print()
        rawprint("\n")
        
        rawprint(env.space.."ANSI SGR Codes, where '$E' means ascii code 27(a.k.a chr(27)): ")
        rawprint(env.space..string.rep("=",140))
        print(env.load_data(env.join_path(env.WORK_DIR,"lib","ANSI.txt"),false))
        rawprint(env.space..string.rep("=",140))
        
        local bf,wf,bb,wb=base_color['BLK'][1],base_color['HIW'][1],base_color['BBLK'][1],base_color['HBWHT'][1]
        if env.grid then
            local row=env.grid.new()
            local is_fg,max_len=nil,0
            row:add{"Ansi Code","Ansi Type","Description","Demo #1(White)","Demo #2(Black)"}
            for k,v in pairs(base_color) do if type(v)=="table" and v[2] and max_len<#v[2] then max_len=#v[2] end end
            local fmt="%s%s"..base_color['NOR'][1]
            for k,v in pairs(base_color) do
                if type(v)=="table" then
                    local text=string.format('%-'..max_len..'s',v[2])
                    is_fg=text:lower():match("foreground")
                    local ctl=v[4] or 0
                    row:add{k,
                        ctl>0 and " Control" or is_fg and 'FG color' or 'BG color',
                        text,
                        ctl>0 and "N/A" or fmt:format(is_fg and (v[1]..wb) or (wf..v[1]),text),
                        ctl>0 and "N/A" or fmt:format(is_fg and (v[1]..bb) or (bf..v[1]),text)}
                end
            end
            row:sort("-2,3,1",true)
            row:print()
        end
        rawprint(env.space..string.rep("=",140))
        rawprint(env.space.."Use `$<code>$<other text>` to mask color in all outputs, including query, echo, etc. Not all listed control codes are supported.")
        rawprint(env.space.."For the color settings defined in command 'set', use '<code1>[;<code2>[...]]' format")
        rawprint(env.space.."Run 'ansi <text>' to test the color, i.e.: ")
        rawprint(env.space.."    1). ansi $HIR$ Hello $HIC$$HBGRN$ ANSI!")
        rawprint(env.space.."    2). ansi \\e[4;91m Bold+Underline+Red \\e[0m")
        rawprint(env.space.."    3). select '$HIR$'||owner||'$HIB$.\\e[48;5;11m'||object_name obj,'$NOR$' x,a.* from all_objects a where rownum<10;")
        rawprint(env.space.."Use 'set color' to adjust the color preferences of the console.")
        return
    end
   
    return print("ANSI result: "..ansi.convert_ansi(str)..ansi.string_color('NOR'))
end


return ansi