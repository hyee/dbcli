local ffi = require("ffi")
local string,table,math,java,loadstring,tostring,tonumber=string,table,math,java,loadstring,tostring,tonumber
local ipairs,pairs,type=ipairs,pairs,type
local byte,sub,gsub,find=string.byte,string.sub,string.gsub,string.find

function string.initcap(v)
    return (' '..v):lower():gsub("([^%w])(%w)",function(a,b) return a..b:upper() end):sub(2)
end

function os.shell(cmd,args)
    io.popen('"'..cmd..(args and (" "..args) or "")..'"')
end

function os.find_extension(exe,ignore_errors)
    local exes=type(exe)=='string' and {exe} or exe
    local err='Cannot find executable "'..exes[1]..'" in the default path, please add it into EXT_PATH of file data'..env.PATH_DEL..(env.IS_WINDOWS and 'init.cfg' or 'init.conf')
    for _,exe in ipairs(exes) do 
        if exe:find('[\\/]') then
            local type,file=os.exists(exe)
            if not ignore_errors then env.checkerr(type,err) end
            return file
        end
        exe='"'..env.join_path(exe):trim('"')..'"'
        local nul=env.IS_WINDOWS and "NUL" or "/dev/null"
        local cmd=string.format("%s %s 2>%s", env.IS_WINDOWS and "where " or "which ",exe,nul)
        local f=io.popen(cmd)
        if f then
            local path
            for file in f:lines() do
                path=file
                break
            end
            f:close()
            if path then return path end
        end
    end
    env.checkerr(ignore_errors,err)
end

--Continus sep would return empty element
function string.split (s, sep, plain,occurrence,case_insensitive)
    local r={}
    for v in s:gsplit(sep,plain,occurrence,case_insensitive) do
        r[#r+1]=v
    end
    return r
end

local table_concat=table.concat
function string.replace(s,sep,txt,plain,occurrence,case_insensitive)
    if not sep or s=='' then return s end
    local r=s:split(sep,plain,occurrence,case_insensitive)
    return table_concat(r,txt),#r-1
end

function string.escape(s, mode)
    s = gsub(s,'([%^%$%(%)%.%[%]%*%+%-%?%%])', '%%%1')
    if mode == '*i' then s = s:case_insensitive_pattern() end
    return s
end

function string.gsplit(s, sep, plain,occurrence,case_insensitive)
    local start = 1
    local counter=0
    local done = false
    local s1=case_insensitive==true and s:lower() or s
    local sep1=case_insensitive==true and sep:lower() or sep
    local function pass(i, j)
        if i and ((not occurrence) or counter<occurrence) then
            local seg = i>1 and sub(s,start, i - 1) or ""
            start = j + 1
            counter=counter+1
            return seg, sub(s,i,j),counter,i,j
        else
            done = true
            return sub(s,start),"",counter+1
        end
    end
    return function()
        if done then return end
        if sep1 == '' then done = true;return s end
        return pass(find(s1,sep1, start, plain))
    end
end

function string.case_insensitive_pattern(pattern)
    -- find an optional '%' (group 1) followed by any character (group 2)
    local p = gsub(pattern,"(%%?)(.)",
        function(percent, letter)
            if percent ~= "" or not letter:match("%a") then
                -- if the '%' matched, or `letter` is not a letter, return "as is"
                return percent .. letter
            else
                -- else, return a case-insensitive character class of the matched letter
                return string.format("[%s%s]", letter:lower(), letter:upper())
            end
        end)
    return p
end

local other_spaces={
    '\xa3\xa0',--
    '\xc2\x85',   --0x85
    '\xc2\xa0',   --0xa0
    '\xe1\x9a\x80',   --0x1680
    '\xe1\xa0\x8e',   --0x180e
    '\xe2\x80\x80',   --0x2000
    '\xe2\x80\x81',   --0x2001
    '\xe2\x80\x82',   --0x2002
    '\xe2\x80\x83',   --0x2003
    '\xe2\x80\x84',   --0x2004
    '\xe2\x80\x85',   --0x2005
    '\xe2\x80\x86',   --0x2006
    '\xe2\x80\x87',   --0x2007
    '\xe2\x80\x88',   --0x2008
    '\xe2\x80\x89',   --0x2009
    '\xe2\x80\x8a',   --0x200a
    '\xe2\x80\x8b',   --0x200b
    '\xe2\x80\x8c',   --0x200c
    '\xe2\x80\x8d',   --0x200d
    '\xe2\x80\xa8',   --0x2028
    '\xe2\x80\xa9',   --0x2029
    '\xe2\x80\xaf',   --0x202f
    '\xe2\x81\x9f',   --0x205f
    '\xe2\x81\xa0',   --0x2060
    '\xe3\x80\x80',   --0x3000
    '\xef\xbb\xbf',   --0xfeff
}
local ext_spaces={}
local function exp_pattern(sep)
    local ary
    if sep then
        if not ext_spaces[sep] then
            ext_spaces[sep]={}
            for i=1,#sep do ext_spaces[sep][byte(sep,i)]=true end
        end
        ary=ext_spaces[sep]
    end
    return ary
end

local function rtrim(s,sep)
    local ary,f=exp_pattern(sep)
    if type(s)=='string' then
        local len=#s
        for i=len,1,-1 do
            local p=byte(s,i)
            if f then
                f=nil
            elseif p==160 and (byte(s,i-1)==194 or byte(s,i-1)==163) then
                f=true
            elseif p>32 and not (ary and ary[p]) then
                return i==len and s or sub(s,1,i)
            elseif i==1 then
                return ''
            end
        end
    end
    return s
end

local function ltrim(s,sep)
    local ary,f=exp_pattern(sep)
    if type(s)=='string' then
        local len=#s
        for i=1,len do
            local p=s:byte(i)
            if f then
                f=nil
            elseif (p==194 or p==163) and byte(s,i+1)==160 then
                f=true
            elseif p>32 and not (ary and ary[p]) then
                return i==1 and s or sub(s,i)
            elseif i==len then
                return ''
            end
        end
    end
    return s
end

string.ltrim,string.rtrim=ltrim,rtrim
function string.trim(s,sep)
    return rtrim(ltrim(s,sep),sep)
end


String=java.require("java.lang.String")
local String=String
--this function only support %s
function string.fmt(base,...)
    local args = {...}
    for k,v in ipairs(args) do
        if type(v)~="string" then
            args[k]=tostring(v)
        end
    end
    return String:format(base,table.unpack(args))
end

function string.format_number(base,s,cast)
    if not tonumber(s) then return s end
    return String:format(base,java.cast(s,cast or 'double'))
end

function string.lpad(str, len, char)
    str=tostring(str) or str
    return (str and ((char or ' '):rep(len - #str)..str):sub(-len)) or str
end

function string.rpad(str, len, char)
    str=tostring(str) or str
    return (str and (str..(char or ' '):rep(len - #str)):sub(1,len)) or str
end

function string.cpad(str, len, char,func)
    if not str then return str end
    str,char=tostring(str) or str,char or ' '
    --len counts display columns, so sub(1,len) would cut a multi-byte char in half and
    --#str would count escape sequences and continuation bytes instead of columns
    local _,width
    _,width,str=str:ulen(len)
    local rest=len-width
    local left=char:rep(math.floor(rest/2))
    local right=char:rep(rest-math.floor(rest/2))
    return type(func)~="function" and ("%s%s%s"):format(left,str,right) or func(left,str,right)
end


if not table.unpack then table.unpack=function(tab) return unpack(tab) end end

local system=java.system
local clocker=system.currentTimeMillis
function os.timer()
    return clocker()/1000
end

function string.from(v)
    local path=_G.WORK_DIR
    path=path and #path or 0
    if type(v) == "function" then
        local d=debug.getinfo(v)
        local src=d.source:gsub("^@+","",1):split(path,true)
        if src and src~='' then
            return 'function('..src[#src]:gsub('%.lua$','#'..d.linedefined)..')'
        end
    elseif type(v) == "string" then
        return ("%q"):format(v:gsub("\t","    "))
    end
    return tostring(v)
end

local weekmeta={__mode='k'}
local globalweek=setmetatable({},weekmeta)
function table.weak(reuse)
    return reuse and globalweek or setmetatable({},weekmeta)
end

function table.append(tab,...)
    for i=1,select('#',...) do
        tab[#tab+1]=select(i,...)
    end
end

local json=json
if json.use_lpeg then json.use_lpeg () end
function table.totable(str)
    local txt,err,done=loadstring('return '..str)
    if not txt then 
        done,txt=pcall(json.decode,str) 
    else
        done,txt=pcall(txt)
    end
    if not done then
        local idx=0
        str=('\n'..str):gsub('\n',function(s) idx=idx+1;return string.format('\n%4d',idx) end)
        env.raise('Error while parsing text into Lua table:' ..(err or tostring(txt) or '')..str)
    end
    return txt
end

local function compare(a,b)
    local t1,t2=type(a[1]),type(b[1])
    if t1==t2 and t1~='table' and t1~='function' and t1~='userdata' and t1~='thread'  then return a[1]<b[1] end
    if t1=="number" then return true end
    if t2=="number" then return false end
    return tostring(a[1])<tostring(b[1])
end

function math.round(exact, quantum)
    if type(exact)~='number' then return exact end
    quantum = quantum and 10^quantum or 1
    local quant,frac = math.modf(exact*quantum)
    local sgn=exact<0 and -1 or 1
    return sgn*(math.floor(math.abs(exact)*quantum+0.5))/quantum
end

if not table.clone then
    table.clone=function(t,depth) -- deep-copy a table
        if type(t) ~= "table" or (depth or 1)<=0 then return t end
        local meta = getmetatable(t)
        local target = {}
        for k, v in pairs(t) do
            if type(v) == "table" then
                target[k] = table.clone(v,(tonumber(depth) or 99)-1)
            else
                target[k] = v
            end
        end
        setmetatable(target, meta)
        return target
    end
end

function table.week(typ,gc)
    return setmetatable({},{__mode=typ or 'k'})
end

function table.strong(tab)
    return setmetatable(tab or {},{__gc=function(self) print('table is gc.') end})
end

function table.avgsum(t)
  local sum = 0
  local count= 0

  for k,v in pairs(t) do
    if type(v) == 'number' then
      sum = sum + v
      count = count + 1
    end
  end

  return (sum / count),sum,count
end

-- Get the mode of a table.  Returns a table of values.
-- Works on anything (not just numbers).
function table.mode( t )
  local counts={}

  for k, v in pairs( t ) do
    if counts[v] == nil then
      counts[v] = 1
    else
      counts[v] = counts[v] + 1
    end
  end

  local biggestCount = 0

  for k, v  in pairs( counts ) do
    if v > biggestCount then
      biggestCount = v
    end
  end

  local temp={}

  for k,v in pairs( counts ) do
    if v == biggestCount then
      table.insert( temp, k )
    end
  end

  return temp
end

-- Get the median of a table.
function table.median( t )
  local temp={}

  -- deep copy table so that when we sort it, the original is unchanged
  -- also weed out any non numbers
  for k,v in pairs(t) do
    if type(v) == 'number' then
      table.insert( temp, v )
    end
  end

  table.sort( temp )

  -- If we have an even number of table elements or odd.
  if math.fmod(#temp,2) == 0 then
    -- return mean value of middle two elements
    return ( temp[#temp/2] + temp[(#temp/2)+1] ) / 2
  else
    -- return middle element
    return temp[math.ceil(#temp/2)]
  end
end
    

-- Get the standard deviation of a table
function table.stddev( t )
  local m
  local vm
  local sum = 0
  local count = 0
  local result

  m = table.avgsum( t )

  for k,v in pairs(t) do
    if type(v) == 'number' then
      vm = v - m
      sum = sum + (vm * vm)
      count = count + 1
    end
  end

  result = math.sqrt(sum / (count-1))

  return result
end

-- Get the max and min for a table
function table.maxmin( t )
  local max = -math.huge
  local min = math.huge

  for k,v in pairs( t ) do
    if type(v) == 'number' then
      max = math.max( max, v )
      min = math.min( min, v )
    end
  end

  return max, min
end

function table.dump(tbl,indent,maxdep,tabs)
    maxdep=tonumber(maxdep) or 9
    if maxdep<=1 then
        return tostring(tbl)
    end

    if tabs==nil then
        tabs={}
    end

    if not indent then indent = '' end

    indent=string.rep(' ',type(indent)=="number" and indent or #indent)

    local ind = 0
    local pad=indent..'  '
    local maxlen=0
    local keys={}

    local fmtfun=string.format
    if type(tbl)=='userdata' then
        local t=debug.getmetatable(tbl)
        if type(t)~='table' or not t.__pairs then
            return indent..tostring(tbl)
        end
    elseif type(tbl)~='table' then
        return
    end
    for k,_ in pairs(tbl) do
        local k1=k
        if type(k)=="string" and not k:match("^[%w_]+$") then k1=string.format("[%q]",k) end
            keys[#keys+1]={k,k1}
            if maxlen<#tostring(k1) then maxlen=#tostring(k1) end
            if maxlen>99 then
                fmtfun=string.fmt
            end
        end

        table.sort(keys,compare)
        local rs=""
        for v, k in ipairs(keys) do
            v,k=tbl[k[1]],k[2]
        local fmt =(ind==0 and "{ " or pad)  .. fmtfun('%-'..maxlen..'s%s' ,tostring(k),'= ')
        local margin=(ind==0 and indent or '')..fmt
        rs=rs..fmt
        local is_javaobj=false
        if type(v) =='userdata' then
            local t=debug.getmetatable(v)
            if type(t)=='table' and t.__pairs then
                is_javaobj=true
            end
        end
        if type(v) == "table" or is_javaobj then
            if k=='root' then
                rs=rs..'<<Bypass root>>'
            elseif tabs then
                if not tabs[v] then
                    local c=tabs.__current_key or ''
                    local c1=c..(c=='' and '' or '.')..tostring(k)
                    tabs[v],tabs.__current_key=c1,c1
                    rs=rs..table.dump(v,margin,maxdep-1,tabs)
                    tabs.__current_key=c
                else
                    rs=rs..'<<Refer to '..tabs[v]..'>>'
                end
            else
                rs=rs..table.dump(v,margin,maxdep-1,tabs)
            end
        elseif type(v) == "function" then
            rs=rs..'<'..string.from(v)..'>'
        elseif type(v) == "userdata" then
            rs=rs..'<userdata('..tostring(v)..')>'
        elseif type(v) == "string" then
            rs=rs..string.format("%q",v:gsub("\n","\n"..string.rep(" ",#margin)))
        else
            rs=rs..tostring(v)
        end
        rs=rs..',\n'
        ind=ind+1
    end
    if ind==0 then return  '{}' end
    rs=rs:sub(1,-3)..'\n'
    if ind<2 then return rs:sub(1,-2)..' }' end
    return rs..indent..'}'
end


function try(args)
    local succ,res,err,final=pcall(args[1])
    local catch=args.catch or args[2]
    local finally=args.finally or args[3]
    final,err=true,not succ
    if err and catch then
        if(type(res)=="string" and env.ansi) then 
            res=res:match(env.ansi.pattern.."(.-)"..env.ansi.pattern)
        end
        succ,res=pcall(catch,res)
    end

    if finally then
        final,err=pcall(finally,err)
        if not catch or not final then succ,res=final,err or res end
    end

    if not succ then env.raise_error(res) end
    return res
end

function string.fromhex(str)
    return (str:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

--Serving pre-interned single bytes skips a string.sub plus a string-table probe
--per ASCII char, which dominates what this iterator costs.
local char1={}
for c=0,0xFF do char1[c+1]=string.char(c) end
--[[UTF-8 codepoint:
     byte  1        2           3          4
    --------------------------------------------
     00 - 7F
     C2 - DF      80 - BF
     E0           A0 - BF     80 - BF
     E1 - EC      80 - BF     80 - BF
     ED           80 - 9F     80 - BF
     EE - EF      80 - BF     80 - BF
     F0           90 - BF     80 - BF    80 - BF
     F1 - F3      80 - BF     80 - BF    80 - BF
     F4           80 - 8F     80 - BF    80 - BF

    The first hex character present the bytes of the char:
    0-7: 1 byte, e.g.:  57
    C-D: 2 bytes,e.g.:  ce 9a
    E:   3 bytes,e.g.:  e6 ad a1
    F:   4 bytes 
--]]--
--Iterates the UTF-8 chars of s from byte offset start, yielding char,is_multi,next_pos.
--is_multi means the char spans more than one byte. Malformed input is lenient: the
--offending lead byte is yielded on its own and scanning resumes right after it.
function string.chars(s,start)
    local i,n=start or 1,#s
    if i<1 then i=1 end
    local function iter()
        if i>n then return end
        local i0,c=i,byte(s,i)
        if c<0x80 then
            i=i0+1
            return char1[c+1],false,i
        end
        local i1=i0
        if c>=0xC2 and c<=0xDF then
            local c2=byte(s,i0+1)
            if c2 and c2>=0x80 and c2<=0xBF then i1=i0+1 end
        elseif c>=0xE0 and c<=0xEF then
            local c2,c3=byte(s,i0+1),byte(s,i0+2)
            if c3 then
                local lo,hi=0x80,0xBF
                if c==0xE0 then lo=0xA0 elseif c==0xED then hi=0x9F end
                if c2>=lo and c2<=hi and c3>=0x80 and c3<=0xBF then i1=i0+2 end
            end
        elseif c>=0xF0 and c<=0xF4 then
            local c2,c3,c4=byte(s,i0+1),byte(s,i0+2),byte(s,i0+3)
            if c4 then
                local lo,hi=0x80,0xBF
                if c==0xF0 then lo=0x90 elseif c==0xF4 then hi=0x8F end
                if c2>=lo and c2<=hi and c3>=0x80 and c3<=0xBF and c4>=0x80 and c4<=0xBF then i1=i0+3 end
            end
        end
        i=i1+1
        if i1==i0 then return char1[c+1],false,i end
        return sub(s,i0,i1),true,i
    end
    return iter
end

---------------------------------------------------------------- display width
--Port of jline 3.29 org.jline.utils.WCWidth, which is what Console.ulen reaches
--over JNI through AttributedString.columnLength(). Verified against jline's own
--output for all 1,112,064 codepoints; it agrees everywhere except these fixes:
--
--  1. C0/C1 controls and DEL. jline returns -1 and columnLength() sums it, so
--     "a\tb" measures 1 column, ESC TAB measures -2, and appending a character
--     can shrink a string. columnSubSequence inherits this and can walk past its
--     stop column. Here they count 0, which keeps 0 <= width <= #s -- the
--     invariant grid.fmt and cpad pad against and grid.lua:397 subtracts.
--     TAB is the single exception, at 1 column: it is the only C0 character that
--     advances the cursor, so 0 under-reports a string that visibly moves. It is
--     not 4, even though grid.lua's printables table renders a tab as four
--     spaces, because a tab is one byte and 4 would invert that invariant. The
--     grid does not depend on this value either way: printables substitutes the
--     spaces before the cell is ever measured.
--  2. Control sequences jline only half-parses. It strips CSI ..m but drops the
--     terminator of any other CSI, so ESC[?25l leaks "25l" as 3 columns and
--     ESC]0;title BEL leaks 6. Whole CSI/OSC/DCS/SOS/PM/APC/nF sequences count 0.
--     Two-byte Fe and private forms (ESC M, ESC D, ESC c, ESC 7, ESC Z) count 0
--     as well. jline reaches 0 on those only by accident -- its -1 for ESC
--     cancels the following byte's +1 -- so once controls are fixed the second
--     byte has to be consumed explicitly, or "ESC hello" measures 5 not 4.
--  3. Tables frozen around Unicode 5.0. Whole Mn blocks jline predates are now
--     zero-width (1AB0-1AFF, 1DCB-1DFD, FE24-FE2F) and these East Asian Wide
--     ranges are now double (16FE0-16FE4, 17000-18D08, 1B000-1B2FF).
--
--Nothing here allocates: unlike string.chars, measuring a cell must not intern a
--substring per character.

-- Sorted disjoint codepoint intervals whose width is not 1, flattened to
-- {first,last,width,...}. Searched only for the blocks listed in WMIX.
local WIV={
  0x80,0x9F,0,0x300,0x36F,0,0x483,0x486,0,0x488,0x489,0,0x591,0x5BD,0,0x5BF,0x5BF,0,0x5C1,0x5C2,0,
  0x5C4,0x5C5,0,0x5C7,0x5C7,0,0x600,0x603,0,0x610,0x615,0,0x64B,0x65E,0,0x670,0x670,0,0x6D6,0x6E4,0,
  0x6E7,0x6E8,0,0x6EA,0x6ED,0,0x70F,0x70F,0,0x711,0x711,0,0x730,0x74A,0,0x7A6,0x7B0,0,0x7EB,0x7F3,0,
  0x901,0x902,0,0x93C,0x93C,0,0x941,0x948,0,0x94D,0x94D,0,0x951,0x954,0,0x962,0x963,0,0x981,0x981,0,
  0x9BC,0x9BC,0,0x9C1,0x9C4,0,0x9CD,0x9CD,0,0x9E2,0x9E3,0,0xA01,0xA02,0,0xA3C,0xA3C,0,0xA41,0xA42,0,
  0xA47,0xA48,0,0xA4B,0xA4D,0,0xA70,0xA71,0,0xA81,0xA82,0,0xABC,0xABC,0,0xAC1,0xAC5,0,0xAC7,0xAC8,0,
  0xACD,0xACD,0,0xAE2,0xAE3,0,0xB01,0xB01,0,0xB3C,0xB3C,0,0xB3F,0xB3F,0,0xB41,0xB43,0,0xB4D,0xB4D,0,
  0xB56,0xB56,0,0xB82,0xB82,0,0xBC0,0xBC0,0,0xBCD,0xBCD,0,0xC3E,0xC40,0,0xC46,0xC48,0,0xC4A,0xC4D,0,
  0xC55,0xC56,0,0xCBC,0xCBC,0,0xCBF,0xCBF,0,0xCC6,0xCC6,0,0xCCC,0xCCD,0,0xCE2,0xCE3,0,0xD41,0xD43,0,
  0xD4D,0xD4D,0,0xDCA,0xDCA,0,0xDD2,0xDD4,0,0xDD6,0xDD6,0,0xE31,0xE31,0,0xE34,0xE3A,0,0xE47,0xE4E,0,
  0xEB1,0xEB1,0,0xEB4,0xEB9,0,0xEBB,0xEBC,0,0xEC8,0xECD,0,0xF18,0xF19,0,0xF35,0xF35,0,0xF37,0xF37,0,
  0xF39,0xF39,0,0xF71,0xF7E,0,0xF80,0xF84,0,0xF86,0xF87,0,0xF90,0xF97,0,0xF99,0xFBC,0,0xFC6,0xFC6,0,
  0x102D,0x1030,0,0x1032,0x1032,0,0x1036,0x1037,0,0x1039,0x1039,0,0x1058,0x1059,0,0x1100,0x115F,2,
  0x1160,0x11FF,0,0x135F,0x135F,0,0x1712,0x1714,0,0x1732,0x1734,0,0x1752,0x1753,0,0x1772,0x1773,0,
  0x17B4,0x17B5,0,0x17B7,0x17BD,0,0x17C6,0x17C6,0,0x17C9,0x17D3,0,0x17DD,0x17DD,0,0x180B,0x180D,0,
  0x18A9,0x18A9,0,0x1920,0x1922,0,0x1927,0x1928,0,0x1932,0x1932,0,0x1939,0x193B,0,0x1A17,0x1A18,0,
  0x1AB0,0x1B03,0,0x1B34,0x1B34,0,0x1B36,0x1B3A,0,0x1B3C,0x1B3C,0,0x1B42,0x1B42,0,0x1B6B,0x1B73,0,
  0x1DC0,0x1DFF,0,0x200B,0x200F,0,0x202A,0x202E,0,0x2060,0x2063,0,0x206A,0x206F,0,0x20D0,0x20EF,0,
  0x2329,0x232A,2,0x2E80,0x3029,2,0x302A,0x302F,0,0x3030,0x303E,2,0x3040,0x3098,2,0x3099,0x309A,0,
  0x309B,0xA4CF,2,0xA806,0xA806,0,0xA80B,0xA80B,0,0xA825,0xA826,0,0xAC00,0xD7A3,2,0xF900,0xFAFF,2,
  0xFB1E,0xFB1E,0,0xFE00,0xFE0F,0,0xFE10,0xFE19,2,0xFE20,0xFE2F,0,0xFE30,0xFE6F,2,0xFEFF,0xFEFF,0,
  0xFF00,0xFF60,2,0xFFE0,0xFFE6,2,0xFFF9,0xFFFB,0,0x10A01,0x10A03,0,0x10A05,0x10A06,0,0x10A0C,0x10A0F,0,
  0x10A38,0x10A3A,0,0x10A3F,0x10A3F,0,0x16FE0,0x16FE4,2,0x17000,0x18D08,2,0x1B000,0x1B2FF,2,
  0x1D167,0x1D169,0,0x1D173,0x1D182,0,0x1D185,0x1D18B,0,0x1D1AA,0x1D1AD,0,0x1D242,0x1D244,0,
  0x1F000,0x1F3FA,2,0x1F3FB,0x1F3FF,0,0x1F400,0x1FEEE,2,0x20000,0x2FFFD,2,0x30000,0x3FFFD,2,
  0xE0001,0xE0001,0,0xE0020,0xE007F,0,0xE0100,0xE01EF,0,0x110000,0x110000,1,
}

-- [block] = index into WIV of the first interval that can overlap it.
local WMIX={
  [0]=1,[3]=4,[4]=7,[5]=13,[6]=28,[7]=49,[9]=64,[10]=97,[11]=133,[12]=160,[13]=187,[14]=202,[15]=223,
  [16]=253,[17]=268,[19]=274,[23]=277,[24]=304,[25]=310,[26]=322,[27]=325,[29]=343,[32]=346,[35]=361,
  [46]=364,[48]=364,[164]=379,[168]=382,[215]=391,[251]=397,[254]=400,[255]=415,[266]=424,[367]=439,
  [397]=442,[465]=448,[466]=460,[499]=463,[510]=469,[767]=472,[1023]=475,[3584]=478,[3585]=484,
}

-- Uniform width of every other 256-codepoint block, run-length encoded as
-- {first_block,last_block,width,...} and expanded once at load time.
local WRLE={
  1,2,1,8,8,1,18,18,1,20,22,1,28,28,1,30,31,1,33,34,1,36,45,1,47,47,2,49,163,2,165,167,1,169,171,1,
  172,214,2,216,248,1,249,250,2,252,253,1,256,265,1,267,366,1,368,396,2,398,431,1,432,434,2,435,464,1,
  467,495,1,496,498,2,500,509,2,511,511,1,512,766,2,768,1022,2,1024,3583,1,3586,4351,1,
}

local HUGE,floor=math.huge,math.floor

--Uniform width of every block of 256 codepoints not named in WMIX, expanded
--once at load time.
local WBLK={}
for i=1,#WRLE,3 do
    local wd=WRLE[i+2]
    for b=WRLE[i],WRLE[i+1] do WBLK[b]=wd end
end

--UTF-8 lead byte to the high byte of its codepoints, and continuation byte to
--the two shares of that high byte. floor(cp/256) is then three table reads and
--two adds, so there is no division in the loop.
local LD,Q,Q16={},{},{}
for c=0xC2,0xDF do LD[c]=floor((c-0xC0)/4) end
for c=0xE0,0xEF do LD[c]=(c-0xE0)*16 end
for c=0xF0,0xF4 do LD[c]=(c-0xF0)*1024 end
for c=0x80,0xBF do Q[c]=floor((c-0x80)/4) Q16[c]=(c-0x80)*16 end

--Byte index just past the control sequence whose ESC is at index i.
local function esc_end(s,i)
    local c=byte(s,i+1)
    if not c then return i+1 end
    if c==0x5B then                                     --CSI
        i=i+2
        local b=byte(s,i)
        while b and b>=0x30 and b<=0x3F do i,b=i+1,byte(s,i+1) end
        while b and b>=0x20 and b<=0x2F do i,b=i+1,byte(s,i+1) end
        if b and b>=0x40 and b<=0x7E then i=i+1 end
        return i
    end
    if c==0x5D or c==0x50 or c==0x58 or c==0x5E or c==0x5F then   --OSC DCS SOS PM APC
        i=i+2
        local b=byte(s,i)
        while b do
            if b==0x07 then return i+1 end
            if b==0x1B and byte(s,i+1)==0x5C then return i+2 end
            i,b=i+1,byte(s,i+1)
        end
        return i
    end
    if c>=0x20 and c<=0x2F then                         --nF: intermediates then a final byte
        i=i+2
        local b=byte(s,i)
        while b and b>=0x20 and b<=0x2F do i,b=i+1,byte(s,i+1) end
        if b and b>=0x30 and b<=0x7E then i=i+1 end
        return i
    end
    --Fe and private two-byte forms: ESC M, ESC D, ESC E, ESC c, ESC 7, ESC Z,
    --ESC \ ... jline also measures these 0, but only by accident -- its -1 for
    --ESC cancels the following byte's +1. With controls fixed to 0 that
    --cancellation is gone, so the second byte has to be consumed explicitly.
    if c>=0x30 and c<=0x7E then return i+2 end
    return i+1
end

--Returns the width and the byte index it stopped at. lim is a column budget and
--trunc says to stop at a newline, which is what jline's columnSubSequence does;
--measuring without a budget passes HUGE and false, because columnLength() does
--not stop at one.
local function walk(s,lim,trunc)
    local w,i,n=0,1,#s
    while i<=n do
        local c=byte(s,i)
        local cw,ni
        if c<0x80 then
            if c>=0x20 and c~=0x7F then cw,ni=1,i+1
            elseif c==0x1B then cw,ni=0,esc_end(s,i)
            elseif c==0x09 then cw,ni=1,i+1     --TAB: the only C0 that advances the cursor
            elseif c==0x0A and trunc then break
            else cw,ni=0,i+1 end
        else
            local hi,cp
            if c>=0xC2 and c<=0xDF then
                local c2=byte(s,i+1)
                if c2 and c2>=0x80 and c2<=0xBF then
                    cp,hi,ni=(c-0xC0)*64+c2-0x80,LD[c],i+2
                end
            elseif c>=0xE0 and c<=0xEF then
                local c2=byte(s,i+1)
                local c3=c2 and byte(s,i+2)
                if c3 and c2>=0x80 and c2<=0xBF and c3>=0x80 and c3<=0xBF then
                    cp,hi,ni=(c-0xE0)*4096+(c2-0x80)*64+c3-0x80,LD[c]+Q[c2],i+3
                end
            elseif c>=0xF0 and c<=0xF4 then
                local c2=byte(s,i+1)
                local c3=c2 and byte(s,i+2)
                local c4=c3 and byte(s,i+3)
                if c4 and c2>=0x80 and c2<=0xBF and c3>=0x80 and c3<=0xBF and c4>=0x80 and c4<=0xBF then
                    cp,hi,ni=(c-0xF0)*262144+(c2-0x80)*4096+(c3-0x80)*64+c4-0x80,LD[c]+Q16[c2]+Q[c3],i+4
                end
            end
            if not ni then cw,ni=1,i+1                  --malformed byte: one replacement column
            else
                local bw=WBLK[hi]
                if bw~=nil then cw=bw
                else
                    cw=1
                    local k=WMIX[hi]
                    while k do
                        local f=WIV[k]
                        if f>cp then break end
                        if cp<=WIV[k+1] then cw=WIV[k+2] break end
                        k=k+3
                    end
                end
            end
        end
        if w+cw>lim then break end
        w,i=w+cw,ni
    end
    return w,i
end

--Display columns s occupies. Control sequences, combining marks and control
--characters count 0; East Asian wide and fullwidth count 2.
--Returns one value, unlike the char-count/width pair this replaces.
function string.wcwidth(s)
    if type(s)~='string' then
        if s==nil then return 0 end
        s=tostring(s)
    end
    return (walk(s,HUGE,false))
end

--Cuts s to at most maxlen display columns and returns byte_len, print_len, cut.
--print_len is the width cut actually has. Console.ulen reports maxlen here
--instead, so a wide character straddling the boundary makes it over-report by
--one and callers pad to a column the text never reaches.
function string.ulen(s,maxlen)
    if s=="" then return 0,0,s end
    if s==nil then return nil end
    if maxlen==0 then return 0,0,'' end
    if type(s)~='string' then s=tostring(s) end
    --width <= #s always, so a budget of at least #s provably cannot truncate and
    --the cut path below is dead. Skipping it anyway measured SLOWER (maxlen=12:
    --182 -> 118 MB/s): it splits walk into two call sites passing different
    --trunc/lim, and LuaJIT then cannot fold either to a constant. Keep one site.
    local trunc=maxlen and maxlen>0
    local w,i=walk(s,trunc and maxlen or HUGE,trunc)
    if i>#s then return #s,w,s end
    if byte(s,i)==0x0A then
        --Console.ulen only truncates when maxLength < columnLength(), so a
        --newline stop with room to spare must return the string whole.
        local full=(walk(s,HUGE,false))
        if maxlen>=full then return #s,full,s end
    end
    local cut=i>1 and sub(s,1,i-1) or ''
    --jline re-serialises through toAnsi(), which re-emits a trailing reset;
    --cutting the original bytes keeps the input colours but can drop that reset.
    if find(cut,'\27',1,true) then cut=cut..'\27[0m' end
    return #cut,w,cut
end
