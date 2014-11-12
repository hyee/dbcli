local env=env
local event={}

function event.callback(name,...)
    name=name:upper()
    if not event[name] then event[name]={} end
    event[name].src=env.callee()

    local v=event[name]

    for k,v in ipairs(v) do
        local result,err
        if v.obj then
            result,err=pcall(v.func,v.obj,...)    
        else
            result,err=pcall(v.func,...)
        end
        if not result then print(err) end
    end
end

function event.snoop(name,func,obj,priority)
    name=name:upper()
    if not event[name] then
        event[name]={}
    end
    local e=event[name]
    for k,v in ipairs(e) do
        if v.func==func then return end
    end
    local src=env.callee()
    if not func then
        return print("Event function not defined in "..src)
    end
    table.insert(e,{src=src,func=func,obj=obj,prior=tonumber(priority) or 50})    
    --Higher priority would be triggered 1st
    table.sort(e,function(a,b) return a.prior>b.prior end)
end

function event.show()
    local grid=env.grid
    local rows={{"Name","Definer","Listener","Priority"}}
    for k,v in pairs(event) do
        if type(v)=="table" and k==k:upper() then
            if #v==0 then
                table.insert(rows,{k,v.src,v.src_line,"","",""})
            else
                for i,j in ipairs(v) do
                    table.insert(rows,{k,v.src,j.src,i..'('..j.prior..')'})
                end
            end
        end
    end
    grid.sort(rows,1,true)
    grid.print(rows)
end

env.set_command(nil,"EVENT",nil,event.show,false,1)
return event