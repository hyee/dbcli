local env,loader,math,sleep_=env,loader,math,uv.sleep
function sleep(second)
    second=tonumber(second)
    env.checkhelp(second)
    if second <= 0 then return end
    sleep_(math.round(second*1000,0))
end

env.set_command(nil,"SLEEP","Usage: sleep <seconds>",sleep,false,2)
return sleep