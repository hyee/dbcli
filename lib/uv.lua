local u=require "luv"
luv=u
local table,math,type,tonumber,os,pcall=table,math,type,tonumber,os,pcall
local uv,env={},env
local index,pos,found
local modules={timer=1,prepare=1,check=1,idle=1,async=1,tcp=1,pipe=1,tty=1,udp=1,fs_event=1,fs_poll=1,fs=1,thread=1,os=1,signal=1}
local sep=jit.os=='windows' and '\\' or '/'
for k,v in pairs(modules) do uv[k]={} end
for name,method in pairs(u) do
    if name:find('setup') then print(name) end
    found=false
    for k,v in pairs(modules) do
        index,pos=name:find(k,1,true)
        if index==1 and name:sub(pos+1,pos+1)=='_' then 
            uv[k][name:sub(pos+2)]=method
            found=true
        elseif name=='new_'..k then
            uv[k].new=method
            found=true
        end
    end
    if not found then uv[name]=method end
end

uv.event,uv.fs_event=uv.fs_event,nil

function os.exists(file,ext)
    file=env.resolve_file(file)
    local attr=uv.fs.stat(file)
    if not attr and type(ext)=="string" then
        file=file..'.'..ext
        attr=uv.fs.stat(file)
    end
    return attr and attr.type,attr and file
end

function os.read(file,size)
    local fd = uv.fs.open(file, 'r', tonumber('644', 8))
    env.checkerr(fd,'file "%s" doese not exist!',file)
    if not size then
        local stat = assert(uv.fs.fstat(fd))
        size=stat.size
    end
    local chunk = assert(uv.fs.read(fd, size, 0))
    uv.fs.close(fd)
    return chunk
end

local function noop() end
function uv.async_read(path, maxsize, callback,...)
    local fd, onStat, onRead, onChunk, pos, chunks
    local args={...}
    local len=#args
    local function res(err,text)
        if fd then u.fs_close(fd, noop) end
        args[len+1],args[len+2]=err or false,text
        return callback(table.unpack(args))
    end

    if (maxsize or 0)<=0 then
        maxsize=1024*1024*1024
    end
    u.fs_open(path, "r", 438 --[[ 0666 ]], function (err, result)
        if err then return res(err) end
        fd = result
        u.fs_fstat(fd, onStat)
    end)
    function onStat(err, stat)
        if err then return onRead(err) end
        if stat.size > 0 then
            u.fs_read(fd, math.min(maxsize,stat.size), 0, onRead)
        else
          -- the kernel lies about many files.
          -- Go ahead and try to read some bytes.
            pos = 0
            chunks = {}
            u.fs_read(fd, math.min(maxsize,8192), 0, onChunk)
        end
    end
    function onRead(err, chunk)
        return res(err, chunk)
    end
    function onChunk(err, chunk)
        if err then
            
            return res(err)
        end
        if chunk and #chunk > 0 then
            chunks[#chunks + 1] = chunk
            pos = pos + #chunk
            if pos<maxsize then
                return u.fs_read(fd, math.min(maxsize-pos,8192), pos, onChunk)
            end
        end
        return res(nil, table.concat(chunks))
    end
end

local binaries={class=1,jar=1,exe=1,dll=1,so=1,gif=1,html=1,zip=1,['7z']=1,chm=1,mnk=1}

local function comp(a,b)
    if a.depth~=b.depth then return a.depth<b.depth end
    return a.fullname:lower()<b.fullname:lower()
end

function os.list_dir(path,ext,depth,read_func,filter,is_skip_binary)
    local filenames=table.new(1024,0)
    local dirs={}
    local fullname,name
    if ext=='' then ext=nil end
    if ext and ext~='*' and ext:sub(1,1)~='.' then ext='.'..ext:lower() end
    depth=tonumber(depth) or 99

    if type(path)=="table" then
        local paths={}
        for index,subdir in ipairs(path) do
            if type(subdir)=='table' then
                for k,v in pairs(subdir) do
                    if not paths[subdir] then
                        paths[subdir],dirs[#dirs+1]=1,{v,10000*index+1}
                    end
                end
            else
                if not paths[subdir] then
                    paths[subdir],dirs[#dirs+1]=1,{subdir,10000*index+1}
                end
            end
        end
    else
        dirs[1]={path,1}
    end
    local function set_text(index,status,text)
        if status then
            io.write('Error on reading '..filenames[index].fullname..': '..status..'\n')
            return
        end
        local err
        filenames[index].data=text
        if type(read_func)=='function' then 
            err,filenames[index].data=pcall(read_func,'ON_READY',filenames[index])
            if not err then 
                print(filenames[index].data) 
                error()
            end 
        end
    end

    local function push_file(fullname,name,typ,depth)
        if is_skip_binary then
            local n=name:lower():match('([^%.//\\]+)$')
            if binaries[n] then return end
        end
        local file={fullname=env.join_path(fullname),name=name,type=typ,depth=depth%10000,shortname=name:gsub('(%.[^%.\\/]*)$','')}
        local is_allow,err
        if type(read_func)=="function" then 
            err,is_allow=pcall(read_func,'ON_SCAN',file)
            if not err then print(is_allow);error() end 
            if not is_allow then return end
        end
        filenames[#filenames+1]=file
        if read_func and typ=='file' then
            uv.async_read(file.fullname,tonumber(read_func) or tonumber(is_allow) or 4*1024*1024,set_text,#filenames)
        end
    end

    local function scan(p,d)
        local req = uv.fs.scandir(p)
        while true do
            local ent,typ
            typ,ent=os.exists(p,ext and ext:sub(2))
            if not typ then break end
            if typ~='directory' then
                push_file(ent,ent:match('[^\\/]+$'),typ,d)
                break
            end
            ent, typ = uv.fs.scandir_next(req)
            if not ent then break end
            if type(ent) == "table" then
                fullname,name,typ=p .. '/' .. ent.name,ent.name, ent.type
            else
                fullname,name=p .. '/' .. ent,ent
            end

            fullname=fullname:gsub("([\\/]+)",env.PATH_DEL)
            if (typ or "") == "" then typ=os.exists(fullname) end
            if typ=='directory' then
                dirs[#dirs+1]={fullname,d+1}
            elseif (not ext) or ext=='*' or name:sub(-#ext):lower()==ext then
                if not filter or name:find(filter) then
                    push_file(fullname,name,typ,d)
                end
            end
        end
    end

    while true do
        local p=table.remove(dirs,1)
        if not p or p[2]%10000>depth then break end
        scan(p[1],p[2])
    end
    uv.run()
    table.sort(filenames,comp)
    return filenames
end


return uv