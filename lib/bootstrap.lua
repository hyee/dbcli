local _G=_ENV or _G
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
local psep,fsep,dll,which,dlldir
if _os=="windows" then 
    psep,fsep,dll,which,dlldir=';','\\','.dll','where java 2>nul',jit.arch
else
    psep,fsep,dll,which,dlldir=':','/',".so",'which java 2>/dev/null',_os
end

local function resolve(path) return (path:gsub("[\\/]+",fsep)) end
local java_bin,java_ver,java_home=arg[1],tonumber(arg[2]) or 52

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
        if ftype=="directory" then
            subdirs[#subdirs+1]=name
        elseif name:find(pattern) and (java_ver>52 or not name:find('jaxb',1,true)) then
            local prefix,version=name:lower():match('[\\/]([^\\/]-)%-?([%-0-9.]*)%.jar$')
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
    for param in other_lib:gmatch("%S*") do
        other_options[#other_options+1]=param
    end
    files[#files+1]=table.remove(other_options,1)
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


path[#path+1]=os.getenv("PATH")
luv.os_setenv("PATH",table.concat(path,psep))
local freem=luv.get_free_memory()
local charset=os.getenv("DBCLI_ENCODING") or "UTF-8"
local options ={'-server',
                '-noverify',
                '-Xms64m',
                '-Xmx'..math.max(128,math.min(math.floor((dlldir=='x86' and luv.get_free_memory() or luv.get_total_memory())/1024/1024*0.75),dlldir=='x86' and 512 or 2048))..'m',
                --'-XX:+UseStringDeduplication','-XX:+UseCompressedOops',
                java_ver>64 and '-XX:+UseZGC' or '-XX:+UseG1GC',
                --'-XX:+UseG1GC','-XX:G1PeriodicGCInterval=3000','-XX:+G1PeriodicGCInvokesConcurrent','-XX:G1PeriodicGCSystemLoadThreshold=0.3',
                --'-XX:-BackgroundCompilation',
                --'-Xcheck:jni','-verbose:jni',
                '-XX:MaxJNILocalCapacity=1048576',
                '-Dfile.encoding='..charset,
                '-Duser.language=en','-Duser.region=US','-Duser.country=US',
                '-Djava.library.path='..resolve(luv.cwd().."/lib/"..dlldir),
                '-Djava.security.egd=file:/dev/./urandom',
                '-Dsecurerandom.source=file:/dev/./urandom',
                '-Djava.class.path='..jars,
                java_ver>52 and '--release=8' or nil,
                java_ver>52 and '-Djdk.module.illegalAccess=deny' or nil,
                --java_ver>52 and '--add-modules=java.xml.bind' or nil,
                java_ver>52 and '--add-opens=java.sql/java.sql=ALL-UNNAMED' or nil ,
                java_ver>52 and '--add-opens=java.base/jdk.internal.loader=ALL-UNNAMED' or nil ,
                java_ver>52 and '--add-opens=jdk.zipfs/jdk.nio.zipfs=ALL-UNNAMED' or nil ,
                java_ver>52 and '--add-opens=java.base/java.lang=ALL-UNNAMED' or nil,
                java_ver>52 and '--add-opens=java.base/java.net=ALL-UNNAMED' or nil,
                java_ver>52 and '--add-opens=java.base/java.io=ALL-UNNAMED' or nil,
                java_ver>52 and '--add-opens=java.base/jdk.internal=ALL-UNNAMED' or nil,
                java_ver>52 and '--add-exports=java.base/jdk.internal.reflect=ALL-UNNAMED' or nil,
                java_ver>52 and '--add-exports=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED' or nil,
                java_ver>52 and '--add-exports=java.base/jdk.internal.org.objectweb.asm.util=ALL-UNNAMED' or nil,
                java_ver>52 and '--add-exports=jdk.unsupported/sun.misc=ALL-UNNAMED' or nil,
                java_ver>52 and '--enable-native-access=ALL-UNNAMED' or nil,
                java_ver>64 and '--illegal-native-access=allow' or nil,
                java_ver>64 and '-XX:UseSVE=0' or nil,
                java_ver>52 and '--add-modules=jdk.unsupported' or nil}

for _,param in ipairs(other_options) do options[#options+1]=param end
options={table.unpack(options)}

javavm = require("javavm",true)
javavm.create(table.unpack(options))

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
if input:find('[\127-\254]') then
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
