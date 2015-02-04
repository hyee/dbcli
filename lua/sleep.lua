local env,socket=env,env.socket
function sleep(second)
    second=tonumber(second)
    if not second then return print("Invalid input of sleep function, the value should be a number") end
    if second <= 0 then return end
    socket.sleep(second)
end

env.set_command(nil,"SLEEP","Usage: sleep <seconds>",sleep,false,2)
return sleep