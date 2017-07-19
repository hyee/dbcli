--export LUA_BIN=/media/sf_D_DRIVE/dbcli/lib/linux
-- export LD_LIBRARY_PATH=/media/sf_D_DRIVE/jdk_linux/jre/bin:/media/sf_D_DRIVE/jdk_linux/jre/lib/amd64/server:./lib/linux
--local java_bin="/media/sf_D_DRIVE/jdk_linux/jre/bin"
local java_bin="d:/program files/java/jre/bin"
local _os=jit.os:lower()
local psep,fsep=_os=="windows" and ';' or ':',_os=="windows" and '\\' or '/'
local dll=_os=="windows" and ".dll" or _os=="linux" and ".so" or ".dylib"
local function resolve(path) return (path:gsub("[\\/]+",fsep)) end
local lua_path=os.getenv("LUA_BIN")
if lua_path then package.cpath=resolve(lua_path..'/?'..dll) end


local uv=require("luv")

uv.set_process_title("DBCli - Initializing")
local files={}
local function scan(dir,ext)
	local req = uv.fs_scandir(dir)
	local pattern='%.'..ext..'$'
	local function iter()
		return uv.fs_scandir_next(req)
	end
	for name, ftype in iter do
		name=resolve(dir..'/'..name)
		if ftype==nil then
			local attr=uv.fs_stat(name)
			ftype=attr and attr.type or "file"
		end
		if ftype=="directory" then
			scan(name,ext)
		elseif name:find(pattern) then
			files[#files+1]=name
		end
	end
end
scan("lib","jar")
local jars=table.concat(files,psep)

local path={java_bin}
local jvmpath=uv.fs_stat(resolve(java_bin..'/server')) and resolve(java_bin..'/server')
if not jvmpath then jvmpath=uv.fs_stat(resolve(java_bin..'/client')) and resolve(java_bin..'/client') end
if not jvmpath then jvmpath=resolve(java_bin:gsub("/bin/?$",'/lib/amd64/server')) end
path[#path+1]=jvmpath
local libpath=os.getenv("LD_LIBRARY_PATH")
if libpath then
	path[#path+1]=libpath
	uv.os_setenv("LD_LIBRARY_PATH",table.concat(path,psep))
end

path[#path+1]=os.getenv("PATH")
uv.os_setenv("PATH",table.concat(path,psep))
--uv.os_setenv("JAVA_HOME","D:\\Program Files\\Java\\jre")

local charset=os.getenv("DBCLI_ENCODING") or "UTF-8"
local options ={'-noverify' ,
			    '-Xmx384M',
			    '-XX:+UseStringDeduplication',
			    '-Dfile.encoding='..charset,
			    '-Duser.language=en','-Duser.region=US','-Duser.country=US',
			    '-Djava.awt.headless=true',
			    '-Djava.class.path='..jars}
javavm = require("javavm")
javavm.create(table.unpack(options))
local destroy=javavm.destroy
loader = java.require("org.dbcli.Loader").get()
console=loader.console
terminal,reader,writer=console.terminal,console.reader,console.writer
while true do
	local input=loadfile(resolve(loader.root.."/lua/input.lua"))
	input(table.unpack(arg))
	if not _G['REOAD_SIGNAL'] then break end
end
destroy()
