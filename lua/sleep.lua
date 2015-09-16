local env,loader,math=env,loader,math
function sleep(second)
    second=tonumber(second)
    if not second then return print("Invalid input of sleep function, the value should be a number") end
    if second <= 0 then return end
    loader:sleep(math.round(second*1000,0))
end

env.set_command(nil,"SLEEP","Usage: sleep <seconds>",sleep,false,2)
return sleep