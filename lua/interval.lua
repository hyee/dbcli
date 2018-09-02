local env,os=env,os
local exec,sleep=env.eval_line,env.sleep
local interval,stack={},{}
local threads=env.RUNNING_THREADS
interval.cmd='ITV'

function interval.itv(sec,count,target)
    env.checkhelp(sec)
    local cmd,org_count,sec,count=sec:upper(),count,tonumber(sec),tonumber(count)
    local thread,cmds=threads[#threads-1],stack[threads[#threads-1]]
    if cmd=="START" then
        target=target and target:gsub("[ \t]+$","")
        stack[thread]={timer=count or 1,clock=os.timer(),msg=target,{interval.cmd ,{cmd,org_count,target}}}
        if target then print(target) end
    elseif cmd=="END" then
        if not cmds then return end;
        local sleep
        if type(env.sleep)=="function" then 
            sleep=env.sleep
        elseif type(env.sleep)=="table" then
            sleep=env.sleep.sleep
        else
            env.raise("Cannot find function env.sleep!")
        end
        stack[thread].replay=true
    elseif cmd=="OFF" then
        stack[thread]=nil
    else
        if not sec or not count or not target or sec<=0 or count<=0 then
            env.raise('Invalid syntax!')
        end
        for i=1,count do
            exec(target,true,true)
            if i<count then sleep(sec) end
        end
    end
end

function interval.replay()
    local cmds=stack[threads[#threads]]
    if not cmds or not cmds.replay then return end
    stack[threads[#threads]]=nil
    if(cmds.msg) then print("") end
    sleep(cmds.timer)
    
    for idx,cmd in ipairs(cmds) do
        env.exec_command(cmd[1],cmd[2])
    end
end

function interval.capture(command)
    local cmds=stack[threads[#threads]]
    if not cmds then return end
    local cmd,args=table.unpack(command)
    cmds[#cmds+1]={cmd,{table.unpack(args)}}
end


function interval.onload()
    env.set_command(nil,{"REPEAT",interval.cmd},[[
        Run a command with specific interval, type 'help @@NAME' for detail. Usage: @@NAME <START [seconds] [remark]>|END|<seconds> times command>
        Example:
            1)  @@NAME 5 5 ora actives
            2)  refer to 'show itvtest
            3)  @@NAME 1 2 <<!
                   show lockobj
                   ora actives
                !

      ]],interval.itv,'__SMART_PARSE__',4)
    if env.event then 
        env.event.snoop('BEFORE_COMMAND',interval.capture,nil,99) 
        env.event.snoop('AFTER_COMMAND',interval.replay,nil,1) 
    end
end

return interval