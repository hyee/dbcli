local env=env
local event,hook,grid=env.event,env.ProFi,env.grid
local prof=jit and jit.profile
local tracer={status="off",profiler="off"}

tracer.prof_cache={}

function tracer.profile(thread, samples, vmstate)
    local func=prof.dumpstack(thread, 'pl\tF', 1)
    if func:find("input.lua",1,true) then return end
    local item=tracer.prof_cache[func] or {samples=0,N=0,I=0,C=0,G=0,J=0}
    item.samples,item[vmstate]=item.samples+samples,item[vmstate]+samples
    if not tracer.prof_cache[func] then tracer.prof_cache[func] = item end
end

function tracer.format_profile()
    local grid=env.grid
    local f=grid.new()
    local d=1e-3
    local sum={0,0,0,0,0,0}
    f:add{"File","Line","Function","Native","N-Natv","C_FUN","GC","JIT","Count","Code"}
    local files={}
    for k,v in pairs(tracer.prof_cache) do
        sum={sum[1]+v.N,sum[2]+v.I,sum[3]+v.C,sum[4]+v.G,sum[5]+v.J,sum[6]+v.samples}
        local file,line,func=k:match("^([^\t]-):?(%d*)\t.-([^:]*)$")
        --if not file then file,func=k:match("^([^\t]*)\t.-([^:]*)$") end
        local l,code=tonumber(line)," "
        if l and l>0 and not files[file] then
            files[file]={}
            local f=io.open(file)
            if f then
                for ln in f:lines() do
                    table.insert(files[file],ln)
                end
                f:close()
            end
        end
        if l and files[file] then
            code=(files[file][l] or " "):gsub("[ \t]+"," "):sub(1,60)
        end
        file=file:gsub(env.WORK_DIR,"")
        f:add{file,line or -1,func,v.N*d,v.I*d,v.C*d,v.G*d,v.J*d,v.samples*d,code}
    end
    files=nil
    f:add{"--Total--",0,"Total",sum[1]*d,sum[2]*d,sum[3]*d,sum[4]*d,sum[5]*d,sum[6]*d," "}
    f:add_calc_ratio("Count",2)
    f:sort(-9,true)
    f:print(nil,nil,nil,100)
end

function tracer.enable(name,flag)
    if name=="ENVTRACE" then
        if tracer.status~=flag then
            tracer.status=flag
            if flag=="on" then
                hook:reset()
                hook:start()
            else
                hook:stop()
                local loc=env._CACHE_PATH..'ProfilingReport.txt'
                hook:writeReport(loc)
                --print("Profiler file report written to "..loc)
            end
        end
        return flag
    end

    if not prof or tracer.profiler==flag then return flag end
    tracer.profiler=flag
    if flag=="on" then
        tracer.prof_cache={}
        prof.start("li0.1",tracer.profile)
    else
        prof.stop()
        tracer.format_profile()
    end
    return flag
end


function tracer.onload()
    local cfg=env.set
    cfg.init("envtrace",tracer.status,tracer.enable,"core","Enable trace to monitor the performance.",'on,off')
    if prof then
        cfg.init("envprofiler",tracer.profiler,tracer.enable,"core","Enable jit profiler to monitor the performance.",'on,off')
    end
end

return tracer