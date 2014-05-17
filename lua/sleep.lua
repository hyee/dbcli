local env,java=env,env.java
local thread=java.require("java.lang.Thread",true)
function sleep(second)
	second=tonumber(second)
	if not second then return print("Invalid input of sleep function, the value should be a number") end
	if second <= 0 then return end
	thread:sleep(second*1000)
end

env.set_command(nil,"SLEEP","Usage: sleep <seconds>",sleep,false,2)
return sleep