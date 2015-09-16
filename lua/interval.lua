local env=env
local exec,sleep=env.eval_line,env.sleep
local interval={}
function interval.itv(sec,count,target)
    sec,count=tonumber(sec),tonumber(count)
    --print(sec,count,target)
    if not sec or not count or not target or sec<=0 or count<=0 then
        env.raise('Invalid syntax!')
    end
    for i=1,count do
        exec(target)
        if i<count then sleep(sec) end
    end
end

function interval.tester()
    exec("itv 3 3 select dbms_random.value,systimestamp from dual;")
end

env.set_command(nil,{"INTERVAL","ITV"},"Run a command with specific interval. Usage: ITV <seconds> <times> <command>",interval.itv,'__SMART_PARSE__',4)

return interval