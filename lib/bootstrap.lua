local _G=_ENV or _G
local jit=_G.jit
local _os=jit.os:lower()
local ver=os.getenv("OSVERSION")
local clock=os.clock()
if ver then
    ver=ver:match('%d+%.%d+')
    if ver then
        ver=ver+0
        if ver<6 then luv=package.loadlib("luv_winxp.dll","luaopen_luv")() end
    end
end
if not luv then luv=require("luv") end
_os=_os=='osx' and (jit.arch:lower()=='arm64' and 'mac-arm' or 'mac') or _os
_os=_os=='linux' and (jit.arch:lower()=='arm64' and 'linux-arm' or 'linux') or _os
local psep,fsep,dll,which,dlldir
if _os=="windows" then
    psep,fsep,dll,which,dlldir=';','\\','.dll','where java 2>nul',jit.arch
else
    psep,fsep,dll,which,dlldir=':','/',".so",'which java 2>/dev/null',_os
end

-- A UNC name starts with two separators. Collapsing them turns '\\server\share\x' into
-- '\server\share\x', which exists nowhere, and fs_stat then denies a java.exe that is there.
local function resolve(path)
    local lead=_os=='windows' and path:sub(1,2):match('^[%\\/][%\\/]') and fsep..fsep or ''
    if lead=='' then return (path:gsub('[\\/]+',fsep)) end
    return lead..(path:sub(3):gsub('[\\/]+',fsep))
end
local java_bin,java_ver,java_home=arg[1],tonumber(arg[2]) or 52,nil

luv.set_process_title("DBCli - Initializing")
local files={}
local function scan(dir,ext)
    local req = luv.fs_scandir(dir)
    local pattern='%.'..ext..'$'
    local function iter()
        return luv.fs_scandir_next(req)
    end
    local subdirs={}
    for name, ftype in iter do
        name=resolve(dir..fsep..name)
        if ftype==nil then
            local attr=luv.fs_stat(name)
            ftype=attr and attr.type or "file"
        end
        -- Windows file systems ignore case, so 'Foo.JAR' is an ordinary jar -- and this branch
        -- skipped it, silently leaving that jar off the classpath.
        local lname=name:lower()
        if ftype=="directory" then
            subdirs[#subdirs+1]=name
        elseif lname:find(pattern) and (java_ver>=53 or not lname:find('jaxb',1,true)) then
            local prefix,version=lname:match('[/\\]([^%/\\]-)%-?([%-0-9.]*)%.jar$')
            version=version:gsub('%d+',function(d) return string.rep('0',4-#d)..d end)
            local p='.'..fsep..name
            local idx=files[prefix]
            if idx then
                if version>idx[2] then
                    idx[2],files[idx[1]]=version,p
                end
            else
                idx=#files+1
                files[prefix],files[idx]={idx,version},p
            end
        end
    end
    for _,sub in ipairs(subdirs) do scan(sub,ext) end
end


scan("lib","jar")
local other_lib=os.getenv("OTHER_LIB")
local other_options={}
if other_lib then
    -- Format: [<extra classpath jars>];<JVM options>, the ';' separator is optional
    local cp, args = other_lib:match('^(.-);(.*)$')
    if not args then cp, args = '', other_lib end
    for param in cp:gmatch('%S+') do
        files[#files+1]=param
    end
    for param in args:gmatch('%S+') do
        other_options[#other_options+1]=param
    end
end
local jars=table.concat(files,psep)

if not java_bin or not luv.fs_stat(resolve(java_bin)) then
    print("Cannot find java executable, exit.")
    os.exit(1)
end

java_bin=java_bin:gsub("[\\/][^\\/]+$","")
java_home=java_bin:gsub("[\\/][^\\/]+$","")
if luv.fs_stat(resolve(java_home..'/jre')) then
    java_bin=resolve(java_home..'/jre/bin')
    java_home=java_bin:gsub("[\\/][^\\/]+$","")
end

local path={java_bin}
local jvmpath=luv.fs_stat(resolve(java_bin..'/server')) and resolve(java_bin..'/server')
if not jvmpath then jvmpath=luv.fs_stat(resolve(java_bin..'/client')) and resolve(java_bin..'/client') end
if not jvmpath then jvmpath=resolve(java_home..'/lib/amd64/server') end

path[#path+1]=jvmpath
path[#path+1]=resolve(java_home..'/lib')

local libpath=os.getenv("LD_LIBRARY_PATH")
if libpath then path[#path+1]=libpath end
--luv.os_setenv("LD_LIBRARY_PATH",table.concat(path,psep))

local is_win=jit.os=='Windows'
path[#path+1]=os.getenv("PATH")
luv.os_setenv("PATH",table.concat(path,psep))
local freem=luv.get_free_memory()
--An empty DBCLI_ENCODING is not "the empty charset": a profile that exports it with no value means
--"no preference", so it is read the same way as unset (cmd's 'SET X=' unsets, POSIX's does not).
local function env_or(name,fallback)
    local v=os.getenv(name)
    return v and v~='' and v or fallback
end
local function says_utf8(loc)
    return loc:lower():find('utf%-?8')~=nil
end
local charset=env_or("DBCLI_ENCODING","UTF-8")
--file.encoding is not merely a default here: Console.java pins the terminal codec with
--Charset.forName(System.getProperty("file.encoding")) and hands that Charset to both
--WinSysTerminal.createTerminal and TerminalBuilder.encoding, so this value is what decodes the keys
--typed and encodes the screen. From 18 the JVM documents only UTF-8 and COMPAT as command-line
--values -- anything else is "unspecified behaviour" -- and COMPAT means the host encoding, which is
--what a site writing DBCLI_ENCODING=GBK has always meant. Below 18 COMPAT is not a charset at all
--(measured: it resolves to UTF-8), and there the equivalent of "host encoding" is to leave the
--property unset, which is what the JVM would have done anyway.
if java_ver>=62 then
    if not says_utf8(charset) and charset~='COMPAT' then charset='COMPAT' end
elseif charset:lower()=='compat' then
    charset=nil
end
--Windows paints in wide characters, so forcing UTF-8 onto its streams cannot disagree with the
--terminal. POSIX has no such buffer: the JVM takes a stream encoding from the locale, and a locale
--that does not say UTF-8 (unset, C, POSIX) resolves to 7-bit ASCII -- every non-ASCII byte a session
--prints then becomes '?'. So POSIX is forced only for those locales; a real UTF-8 locale and a legacy
--8-bit one both keep deciding for themselves. (A declared-but-not-generated locale fools this test:
--it reads as UTF-8 while the JVM still answers ANSI_X3.4-1968. That is fixed by locale-gen.)
--A declared non-UTF-8 DBCLI_ENCODING says "this terminal speaks my code page", so POSIX leaves the
--streams alone then too -- forcing UTF-8 beside a legacy terminal codec is how one screen ends up
--showing two encodings at once. Windows keeps forcing, as it always has.
local legacy_asked=charset==nil or not says_utf8(charset)
local force_streams=is_win or (not legacy_asked and not says_utf8(env_or("LC_ALL",env_or("LC_CTYPE",os.getenv("LANG") or ''))))
local options ={'-server',
                --'-noverify' lived here for years and never did anything: it is a launcher word,
                --not a VM option, and JNI_CreateJavaVM is handed it as one -- with javavm.c setting
                --ignoreUnrecognized=JNI_TRUE it is discarded without a word. The VM's own echo of
                --its accepted flags is identical with and without it ('-Xverify:none', which the VM
                --does parse, is visibly not). Bytecode verification has therefore always been on.
                '-Xms64m',
                '-Xmx'..math.max(128,math.min(math.floor((dlldir=='x86' and freem or luv.get_total_memory())/1024/1024*0.75),dlldir=='x86' and 512 or 2048))..'m',
                '-XX:+UseStringDeduplication',
                --Compressed oops is a 64-bit flag; a 32-bit JVM has never heard of it, so on the
                --bundled x86 runtime this asked for nothing.
                dlldir~='x86' and '-XX:+UseCompressedOops' or nil,
                --java_ver>64 and '-XX:+UseZGC' or '-XX:+UseG1GC',
                '-XX:+UseG1GC','-XX:MaxGCPauseMillis=200','-XX:G1ReservePercent=10',
                '-XX:MaxJNILocalCapacity=65536',
                --'-Xcheck:jni','-verbose:jni',
                charset and '-Dfile.encoding='..charset or nil,
                '-Duser.language=en','-Duser.region=US','-Duser.country=US',
                '-Djava.security.egd=file:/dev/./urandom',
                '-Dsecurerandom.source=file:/dev/./urandom',
                --JLine writes ESC[9999E at startup whenever the terminal type is windows-conemu, as
                --ConEmu's "activate extended fonts" signal. That type is what a plain console without VTP
                --gets -- a conhost that cannot parse the escapes itself takes the native renderer, and the
                --renderer reads this sequence as the CNL it looks like, so nothing here has to know about
                --ConEmuHk's parser. The point is the same either way: on a console that is not really
                --ConEmu the cursor lands on the last line and the banner prints at the bottom with an
                --empty screen above it. Only inside a real ConEmu window (ConEmuPID is set there) does
                --that signal mean anything.
                not os.getenv("ConEmuPID") and '-Dorg.jline.terminal.conemu.disable-activate=true' or nil,
                --'-Djava.awt.headless=true',
                force_streams and (java_ver<62 and '-Dsun.stderr.encoding=UTF-8' or '-Dstderr.encoding=UTF-8') or nil,
                force_streams and (java_ver<62 and '-Dsun.stdout.encoding=UTF-8' or '-Dstdout.encoding=UTF-8') or nil,
                --The two names on this line are the ones the VM works out for itself: measured with
                --'-XshowSettings:properties' over JDK 8..26, sun.jnu.encoding takes effect on 8 only
                --and is refused from 11 up, and native.encoding keeps reporting the OS code page.
                is_win and (java_ver<62 and '-Dsun.jnu.encoding=UTF-8'    or '-Dnative.encoding=UTF-8') or nil,
                --stdin joins at 69 rather than with its siblings at 62 because that is where the VM
                --begins defining the property itself: absent through 67, 'ms936' at 70 on this ladder.
                is_win and (java_ver>=69 and '-Dstdin.encoding=UTF-8') or nil,
                java_ver>=53 and '--add-opens=java.base/java.util=ALL-UNNAMED' or nil,
                java_ver>=53 and java_ver<61 and '--illegal-access=permit' or nil,
                java_ver>=53 and '--add-opens=java.sql/java.sql=ALL-UNNAMED' or nil ,
                java_ver>=53 and '--add-opens=java.base/jdk.internal.loader=ALL-UNNAMED' or nil ,
                java_ver>=53 and '--add-opens=jdk.zipfs/jdk.nio.zipfs=ALL-UNNAMED' or nil ,
                java_ver>=53 and '--add-opens=java.base/java.lang=ALL-UNNAMED' or nil,
                java_ver>=53 and '--add-opens=java.base/java.net=ALL-UNNAMED' or nil,
                java_ver>=53 and '--add-opens=java.base/java.io=ALL-UNNAMED' or nil,
                java_ver>=53 and '--add-opens=java.base/jdk.internal=ALL-UNNAMED' or nil,
                java_ver>=53 and '--add-exports=java.base/jdk.internal.reflect=ALL-UNNAMED' or nil,
                java_ver>=53 and '--add-exports=jdk.unsupported/sun.misc=ALL-UNNAMED' or nil,
                java_ver>=53 and '--add-modules=jdk.unsupported' or nil,
                java_ver>=60 and '--enable-native-access=ALL-UNNAMED' or nil,
                java_ver>=68 and '--illegal-native-access=allow' or nil,
                java_ver>=70 and '--enable-final-field-mutation=ALL-UNNAMED' or nil,
                --UseSVE is an aarch64 flag; on x64 the VM does not know the name, and here an
                --unknown name is dropped in silence rather than refused.
                jit.arch=='arm64' and java_ver>=65 and '-XX:UseSVE=0' or nil,
                '-Djava.library.path='..resolve(luv.cwd().."/lib/"..dlldir),
                '-Djava.class.path='..jars,
                }
local siz=select('#',table.unpack(options))
local params={}
for i=1,siz do
    local param = options[i]
    if param then
        params[#params+1]=param
    end
end
for i=1,#other_options do
    params[#params+1]=other_options[i]
end

javavm = require("javavm",true)
--javavm.trace(2)
javavm.create(table.unpack(params))

_G.__jvmclock=os.clock()-clock
clock=os.clock()
local destroy=javavm.destroy
loader = java.require("org.dbcli.Loader",true).get()
console=loader.console
terminal,reader,writer=console.terminal,console.reader,console.writer
local m,_env,_loaded=_ENV or _G,{},{}
for k,v in pairs(m) do _env[k]=v end
if m.loaded then for k,v in pairs(m.loaded) do _loaded[k]=v end end

local input=loader:getInputPath()
--Any byte from 0x80 up means the path is not plain ASCII. 0x7F is DEL, a legal ASCII character;
--and the range stopped at 0xFE, so a path ending in a 0xFF byte got through.
if input:find('[\128-\255]') then
    print('DBCLI cannot be launched from a Unicode path!')
    os.exit(1)
end

_G.__loadclock=os.clock()-clock
clock=os.clock()

while true do
    _G.__startclock=os.clock()
    local input,err=loadfile(resolve(input),'bt',_env)
    if not input then error(err) end
    loader:resetLua()
    input(arg)
    rawset(_env,'CURRENT_DB',rawget(_G,'CURRENT_DB'))
    if not rawget(_G,'REOAD_SIGNAL') then break end
    m.loaded=_loaded
end

destroy()
