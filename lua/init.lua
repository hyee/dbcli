local env=env
local dirs={"lib","cache","data"}
local init={
	module_list={
	   --Libraries ->
	    "lib/MessagePack",
	    "lib/ProFi",
	    "lib/misc",
		"lib/class",
	   	"lua/enc",
	    "lua/trace",
	    "lua/printer",  
	    "lua/jline",	
		"lua/event",
		"lua/grid",	
		"lua/helper",
		--"locale",
		--CLI commands ->	
		"lua/sleep",
		"lua/set",
		"lua/host",
		"lua/history",
		"lua/alias",
		"lua/interval",
		"lua/db_core",
		"lua/password",
		"lua/tester",
		--Externals ->
		"oracle/oracle",}
}

function init.init_path()
	local java=java
	java.system=java.require("java.lang.System")
	java.loader=loader
	env('java',java)
	local path=debug.getinfo(1).short_src	
	local path_del
	if path:sub(1,1)=="." then
		path_del=src:match("([^.])")
		env("WORK_DIR",'..'..path_del)
	else
		env("WORK_DIR",path:gsub('%w+[\\/]%w+.lua$',""))
		path_del=env.WORK_DIR:sub(-1)
	end
	env("PATH_DEL",path_del)
	env("OS",path_del=='/' and 'linux' or 'windows')
	local package=package
	package.cpath=""
	package.path=""

	for _,v in ipairs(dirs) do		
		
		os.execute('mkdir "'..env.WORK_DIR..v..'" 2> '..(env.OS=="windows" and 'NUL' or "/dev/null"))
	end

	for _,v in ipairs({"lua","lib","oracle","bin"}) do
		local path=string.format("%s%s%s",env.WORK_DIR,v,path_del)
		local p1,p2=path.."?.lua",path.."?."..(env.OS=="windows" and "dll" or "so")
		package.path  = package.path .. ';' ..p1
		package.cpath = package.cpath .. ';' ..p2		
	end	 
end

function init.load(list,tab)
	local n
	local modules={}
	local root,del,dofile=env.WORK_DIR,env.PATH_DEL,dofile
	local function exec(func,...)
		if not func then return end
		local res,rtn=pcall(func,...)
		if not res then
		 	return print('Error on loading module['..n..']: '..tostring(rtn):gsub(env.WORK_DIR,""))
		end
		return rtn
	end

	for _,v in ipairs(list) do
		n=v:match("([^\\/]+)$")
		tab[n]=exec(dofile,root..v:gsub("[\\/]+",del)..'.lua')
		modules[n]=tab[n]		
	end
	
	for k,v in pairs(modules) do
		if type(v)=="table" and type(v.onload)=="function" then			
			exec(v.onload,v,k)
		end
	end
end

function init.unload(list,tab)
	for i=#list,1,-1 do
		local m=list[i]:match("([^\\/]+)$")	
		if type(tab[m])=="table" and type(tab[m].onunload)=="function" then
			tab[m].onunload(tab[m])
		end
		tab[m]=nil		
	end
end

--[[local jvm = require("javavm")
jvm.create("-Djava.class.path="..CLIB.."jnlua-0.9.6.jar",
	      -- "-Dfile.encoding=UTF-8",
		   "-Djava.library.path="..CLIB,
	       "-Xmx32M")
local loader=java.require("loader")]]--


return init
