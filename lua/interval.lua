local env,os=env,os
local exec,sleep=env.eval_line,env.sleep
local interval={}
function interval.itv(sec,count,target)
    env.checkerr(sec,'Invalid syntax! Usage: ITV <START [seconds]|END|OFF|seconds times command>')
    local cmd,sec,count=sec:upper(),tonumber(sec),tonumber(count)
    if cmd=="START" then
        if env.event then env.event.callback("ON_INTERVAL",'START') end
        interval.is_begin=true;
        interval.timer,interval.clock=count or 1,os.clock()
    elseif cmd=="END" then
        if not interval.is_begin then return end;
        if env.event then 
            if type(env.sleep)=="function" then 
                env.sleep(interval.timer)
            elseif type(env.sleep)=="table" then
                env.sleep.sleep(interval.timer)
            else
                env.raise("Cannot find function env.sleep!")
            end
            env.event.callback("ON_INTERVAL",'RESET') 
        end
    elseif cmd=="OFF" then
        interval.is_begin=false
        env.event.callback("ON_INTERVAL",'OFF') 
    else
        if not sec or not count or not target or sec<=0 or count<=0 then
            env.raise('Invalid syntax!')
        end
        for i=1,count do
            exec(target)
            if i<count then sleep(sec) end
        end
    end
end

function interval.tester()
    exec("itv 3 3 select dbms_random.value,systimestamp from dual;")
end

env.set_command(nil,{"INTERVAL","ITV"},[[
    Run a command with specific interval, type 'help itv' for detail. Usage: ITV <START [seconds]|END|OFF|seconds times command>
    Example:
        1) itv 5 5 ora actives
        2) ITV BEGIN/END/OFF can only be used in script, 'ora' scripts for example.
           itv begin 5                --start the loop for every 5 seconds, itv begin/end/off should be in a script
           var flag varchar2
           ...do something...
           begin
               ...
               if ... then
                   :flag := '' ;
               else
                   :flag := 'itv off'; --off means stop the loop, the loop will also stop if db error is detected
                end if;
           end;
           /  
           &flag
           itv end
    ]],interval.itv,'__SMART_PARSE__',4)

return interval