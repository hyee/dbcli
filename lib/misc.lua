local ffi = require("ffi")
local string,table,java=string,table,java

function string.initcap(v)
    return (' '..v):lower():gsub("([^%w])(%w)",function(a,b) return a..b:upper() end):sub(2)
end

local shell=ffi.load("shell32")
local kernel=ffi.load("kernel32")
ffi.cdef([[
typedef int           INT;
typedef unsigned long    DWORD;
typedef unsigned short   WORD;
typedef unsigned char    BYTE;
typedef char *        LPSTR;
typedef const char *    LPCSTR;
typedef const char *    PCSTR;
typedef LPCSTR          LPCTSTR;
typedef int           HWND;
typedef void *        HINSTANCE;
typedef void *        LPVOID;
typedef WORD *           LPWORD;
typedef int              BOOL;
typedef void *HANDLE;
typedef unsigned char  *   LPBYTE;

typedef struct _SECURITY_ATTRIBUTES {
    DWORD nLength;
    LPVOID lpSecurityDescriptor;
    BOOL bInheritHandle;
} SECURITY_ATTRIBUTES,  *PSECURITY_ATTRIBUTES,  *LPSECURITY_ATTRIBUTES;
typedef struct _STARTUPINFOA {
    DWORD   cb;
    LPSTR   lpReserved;
    LPSTR   lpDesktop;
    LPSTR   lpTitle;
    DWORD   dwX;
    DWORD   dwY;
    DWORD   dwXSize;
    DWORD   dwYSize;
    DWORD   dwXCountChars;
    DWORD   dwYCountChars;
    DWORD   dwFillAttribute;
    DWORD   dwFlags;
    WORD    wShowWindow;
    WORD    cbReserved2;
    LPBYTE  lpReserved2;
    HANDLE  hStdInput;
    HANDLE  hStdOutput;
    HANDLE  hStdError;
} STARTUPINFOA, *LPSTARTUPINFOA;

typedef struct _PROCESS_INFORMATION {
    HANDLE hProcess;
    HANDLE hThread;
    DWORD dwProcessId;
    DWORD dwThreadId;
} PROCESS_INFORMATION, *PPROCESS_INFORMATION, *LPPROCESS_INFORMATION;

void ShellExecuteA(HWND hwnd,LPCTSTR lpOperation,LPCTSTR lpFile,LPCTSTR lpParameters,LPCTSTR lpDirectory,INT nShowCmd);

BOOL CreateProcessA(
    LPCSTR lpApplicationName,
    LPCTSTR lpCommandLine,
    LPSECURITY_ATTRIBUTES lpProcessAttributes,
    LPSECURITY_ATTRIBUTES lpThreadAttributes,
    BOOL bInheritHandles,
    DWORD dwCreationFlags,
    LPVOID lpEnvironment,
    LPCSTR lpCurrentDirectory,
    LPSTARTUPINFOA lpStartupInfo,
    LPPROCESS_INFORMATION lpProcessInformation
    );
]])
function os.shell(cmd,args)
    shell.ShellExecuteA(0,nil,cmd,nil,nil,1)
end

local WCS_ctype = ffi.typeof('char[?]')
function os.CreateProcess(cmdline,  flags)
    kernel.CreateProcessA(cmdline,nil, nil, nil,false, 0, nil,nil,nil,nil)
end

function os.exists(file,ext)
    local f=io.open(file,'r')
    if not f and type(ext)=="string" then
        f=io.open(file..'.'..ext,'r')
        if f then file=file..'.'..ext end
    end
    if f then
        f:close()
        return 1,file
    end

    local r=os.execute('cd "'..file..'" 2>nul 1>nul')
    return r and 2 or nil,file
end

function os.find_extension(exe)
    local cmd=(env.OS=="windows" and "where " or "which ")..exe.." >"..(env.OS=="windows" and "nul 2>nul" or "/dev/null")
    env.checkerr((os.execute(cmd)),"Cannot find "..exe.." in the default path, please add it into EXT_PATH of file data/init.cfg")
    cmd=(env.OS=="windows" and "where " or "which ")..exe
    local f=io.popen(cmd)
    local path
    for n in f:lines() do 
        path=n
        break
    end
    f:close()
    return path
end

--Continus sep would return empty element
function string.split (s, sep, plain,occurrence)
    local r={}
    for v in s:gsplit(sep,plain,occurrence) do
        r[#r+1]=v
    end
    return r
end

function string.replace(s,sep,txt,plain,occurrence)
    local r=s:split(sep,plain,occurrence)
    return table.concat(r,txt),#r-1
end

function string.escape(s, mode)
    s = s:gsub('%%','%%%%'):gsub('%z','%%z'):gsub('([%^%$%(%)%.%[%]%*%+%-%?])', '%%%1')
    if mode == '*i' then s = s:gsub('[%a]', function(s) return s:lower():format('[%s%s]',s:upper()) end) end
    return s
end

function string.gsplit(s, sep, plain,occurrence)
    local start = 1
    local counter=0
    local done = false
    local function pass(i, j)
        if i and (not occurrence or counter<occurrence) then
            local seg = i>1 and s:sub(start, i - 1) or ""
            start = j + 1
            counter=counter+1
            return seg, s:sub(i,j)
        else
            done = true
            return s:sub(start),""
        end
    end
    return function()
        if done then return end
        if sep == '' then done = true return s end
        return pass(s:find(sep, start, plain))
    end
end

function string.case_insensitive_pattern(pattern)
    -- find an optional '%' (group 1) followed by any character (group 2)
    local p = pattern:gsub("(%%?)(.)",
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

function string.trim(s,sep)
    return s:match('^%s*(.-)%s*$')
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
    return String:format(base,java.cast(tonumber(s),cast or 'double'))
end

function string.lpad(str, len, char)
    str=tostring(str) or str
    return (str and (str..(char or ' '):rep(len - #str)):sub(1,len)) or str
end

function string.rpad(str, len, char)
    str=tostring(str) or str
    return (str and ((char or ' '):rep(len - #str)..str):sub(-len)) or str
end

function string.cpad(str, len, char)
    str,char=tostring(str) or str,char or ' '
    if not str then return str end
    char=char:rep(math.floor((len-#str)/2))
    return string.format("%s%s%s",char,str,char):sub(1,len)
end


if not table.unpack then table.unpack=function(tab) return unpack(tab) end end

function string.from(v)
    local path=_G.WORK_DIR
    path=path and #path or 0
    if type(v) == "function" then
        local d=debug.getinfo(v)
        local src=d.short_src:split(path,true)
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

local function compare(a,b)
    local t1,t2=type(a[1]),type(b[1])
    if t1==t2 and t1~='table' and t1~='function' and t1~='userdata' and t1~='thread'  then return a[1]<b[1] end
    if t1=="number" then return true end
    if t2=="number" then return false end
    return tostring(a[1])<tostring(b[1])
end

function math.round(num,digits)
    digits=digits or 0
    return math.floor(10^digits*num+0.5)/(10^digits)
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
        if type(v) == "table" then
            if tabs then
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

-- byte  1          2           3          4
--------------------------------------------
-- 00 - 7F
-- C2 - DF    80 - BF
-- E0         A0 - BF     80 - BF
-- E1 - EC    80 - BF     80 - BF
-- ED         80 - 9F     80 - BF
-- EE - EF    80 - BF     80 - BF
-- F0         90 - BF     80 - BF    80 - BF
-- F1 - F3    80 - BF     80 - BF    80 - BF
-- F4         80 - 8F     80 - BF    80 - BF
function string.chars(s,start)
    local i = start or 1
    if not s or i>#s then return nil end
    local function next()
        local c,i1,p,is_multi = s:byte(i),i
        if not c then return end
        if c >= 0xC2 and c <= 0xDF then
            local c2 = s:byte(i + 1)
            if c2 and c2 >= 0x80 and c2 <= 0xBF then i=i+1 end
        elseif c >= 0xE0 and c <= 0xEF then
            local c2 = s:byte(i + 1)
            local c3 = s:byte(i + 2)
            local flag = c2 and c3 and true or false
            if c == 0xE0 then
                if flag and c2 >= 0xA0 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then i1=i+2 end
            elseif c >= 0xE1 and c <= 0xEC then
                if flag and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then i1=i+2 end
            elseif c == 0xED then
                if flag and c2 >= 0x80 and c2 <= 0x9F and c3 >= 0x80 and c3 <= 0xBF then i1=i+2 end
            elseif c >= 0xEE and c <= 0xEF then
                if flag and 
                    not (c == 0xEF and c2 == 0xBF and (c3 == 0xBE or c3 == 0xBF)) and 
                    c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF 
                then i1=i+2 end
            end
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2 = s:byte(i + 1)
            local c3 = s:byte(i + 2)
            local c4 = s:byte(i + 3)
            local flag = c2 and c3 and c4 and true or false
            if c == 0xF0 then
                if flag and
                    c2 >= 0x90 and c2 <= 0xBF and
                    c3 >= 0x80 and c3 <= 0xBF and
                    c4 >= 0x80 and c4 <= 0xBF
                then i1=i+3 end
            elseif c >= 0xF1 and c <= 0xF3 then
                if flag and
                    c2 >= 0x80 and c2 <= 0xBF and
                    c3 >= 0x80 and c3 <= 0xBF and
                    c4 >= 0x80 and c4 <= 0xBF
                then i1=i+3 end
            elseif c == 0xF4 then
                if flag and
                    c2 >= 0x80 and c2 <= 0x8F and
                    c3 >= 0x80 and c3 <= 0xBF and
                    c4 >= 0x80 and c4 <= 0xBF
                then i1=i+3 end
            end
        end
        p,i,is_multi=s:sub(i,i1),i1+1,i1>i
        return p,is_multi,i
    end
    return next
end

function string.ulen(s)
    if s=="" then return 0,0 end
    if not s then return nil end 
    local len1,len2=0,0
    for c,is_multi in s:chars() do
        len1,len2=len1+1,len2+(is_multi and 2 or 1)
    end
    return len1,len2
end