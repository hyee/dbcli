local env,loader,math=env,loader,math
function sleep(second)
    env.checkerr(tonumber(second),env.helper.helper,env.CURRENT_CMD)
    second=tonumber(second)
    if second <= 0 then return end
    loader:sleep(math.round(second*1000,0))
end

env.set_command(nil,"SLEEP","Usage: sleep <seconds>",sleep,false,2)
return sleep