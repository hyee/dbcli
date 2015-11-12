local env,pcall=env,pcall
local event={}

function event.callback(name,...)
    local args,callee_idx={...},3
    if type(name)=="number" then
        callee_idx,name=name,args[1]
        table.remove(args,1)
    end

    name=name:upper()
    if not event[name] then event[name]={} end
    event[name].src=env.callee(callee_idx)
    local v=event[name]
    local flag,result
    for k,v in ipairs(v) do
        env.log_debug("Event",name,'-->',v.src)
        if v.obj then
            flag,result=pcall(v.func,v.obj,...)
        else
            flag,result=pcall(v.func,...)
        end
        if not flag then
            env.warn(result)
        end
    end
    return ...,result
end

function event.snoop(callee_idx,name,func,obj,priority)
    if type(callee_idx)~="number" then
        callee_idx,name,func,obj,priority=3,callee_idx,name,func,obj
    end
    name=name:upper()
    if not event[name] then event[name]={} end
    local e=event[name]
    for k,v in ipairs(e) do
        if v.func==func then return end
    end
    local src=env.callee(callee_idx)
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