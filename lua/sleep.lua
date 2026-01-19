local env,loader,math,sleep_=env,loader,math,uv.sleep
local sleep=function(second,is_not_breakable)
    second=tonumber(second)
    env.checkhelp(second)
    if second <= 0 then return end
    if is_not_breakable then
        sleep_(math.round(second*1000,0))
    else
        loader:sleep(math.round(second*1000,0))
    end
end

env.set_command(nil,"SLEEP","Usage: sleep <seconds>",sleep,false,2)
return sleep