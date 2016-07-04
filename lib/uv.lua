local u=require"luv"
local uv={}
local index,pos,found
local modules={timer=1,prepare=1,check=1,idle=1,async=1,tcp=1,pipe=1,tty=1,udp=1,fs_event=1,fs_poll=1,fs=1,thread=1,os=1,signal=1}

for k,v in pairs(modules) do uv[k]={} end
for name,method in pairs(u) do
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

function uv.os.exists(file,ext)
    local attr=uv.fs.stat(file)
    if not attr and type(ext)=="string" then
        file=file..'.'..ext
        attr=uv.fs.stat(file)
    end
    return attr and attr.type,file
end

return uv