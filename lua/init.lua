local env=env
local dirs={"lib","cache","data"}
local init={
    module_list={
       --Libraries ->
        "lib/zlib",
        "lib/socket",
        "lib/lanes",
        "lib/MessagePack",
        "lib/ProFi",
        "lib/misc",
        "lib/class",
        "lua/packer",
        "lua/trace",
        "lua/printer",  
        "lua/ansi",    
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
        "lua/login",
        "lua/var",
        "lua/scripter",
        "lua/snapper",
        "lua/tester"}
}

init.databases={oracle="oracle/oracle",mssql="mssql/mssql"}
local default_database='oracle'

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
        local p1,p2=path.."?.lua",path..(java.system:getProperty('os.arch')=='x86' and 'x86' or "x64")..path_del.."?."..(env.OS=="windows" and "dll" or "so")
        package.path  = package.path .. (path_del=='/' and ':' or ';') ..p1
        package.cpath = package.cpath ..(path_del=='/' and ':' or ';') ..p2        
    end     
end

local function exec(func,...)
    if type(func)~='function' then return end
    local res,rtn=pcall(func,...)
    if not res then
        return print('Error on loading module: '..tostring(rtn):gsub(env.WORK_DIR,""))
    end
    return rtn
end

function init.db_list()
    local keys={}
    for k,_ in pairs(init.databases) do
        keys[#keys+1]=k
    end
    table.sort(keys)
    return keys
end

function init.set_database(_,db)
    if not db then return nil end
    db=db:lower()
    if db==env.CURRENT_DB then return db end
    env.checkerr(init.databases[db],'Invalid database type!')
    if env.CURRENT_DB then
        print("Switching database ...")
        env.CURRENT_DB=db
        env.unload()
        env.onload(table.unpack(env.__ARGS__))
    end
    env.CURRENT_DB=db
    return db 
end

function init.load_database()
    local res
    if not env.CURRENT_DB then
        if env.set and env.set._p then env.CURRENT_DB=env.set._p['database'] end
        env.CURRENT_DB=env.CURRENT_DB or default_database 
    end    
    local file=init.databases[env.CURRENT_DB]
    if not file then return end
    local name=file:match("([^\\/]+)$")
    env[name]=exec(dofile,env.WORK_DIR..file:gsub("[\\/]+",env.PATH_DEL)..'.lua')    
    exec(type(env[name])=="table" and env[name].onload,env[name],name)
    init.module_list[#init.module_list+1]=file
end

function init.load_modules(list,tab)
    local n
    local modules={}
    local root,del,dofile=env.WORK_DIR,env.PATH_DEL,dofile

    for _,v in ipairs(list) do
        n=v:match("([^\\/]+)$")
        tab[n]=exec(dofile,root..v:gsub("[\\/]+",del)..'.lua')
        modules[n]=tab[n]        
    end
    
    for k,v in pairs(modules) do
        exec(type(v)=="table" and v.onload,v,k)
    end    
end

function init.onload()
    init.load_modules(init.module_list,env)
    if env.set then
        init.load_database()
        env.safe_call(env.set.init,"database",env.CURRENT_DB,init.set_database,'core','Define current database type',table.concat(init.db_list(),','))        
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

return init
