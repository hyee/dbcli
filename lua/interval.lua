local exec,sleep=env.eval_line,env.sleep
local interval={}
function interval.interval(cmd)
	local sec,count,target=cmd:gsub("^[\n\r\t%s]+",""):match("^(%d+)%s+(%d)%s+(.+)$")
	sec,count=tonumber(sec),tonumber(count)
	--print(sec,count,target)
	if not sec or not count or not target or sec<=0 or count<=0 then
		return print('Invalid syntax!')
	end
	for i=1,count do
		exec(target..';')
		if i<count then sleep(sec) end
	end
end

function interval.tester()
	exec("itv 3 3 select dbms_random.value,systimestamp from dual;")
end

env.set_command(nil,{"INTERVAL","ITV"},"Run a command with specific interval. Usage: ITV <seconds> <times> <command>;",interval.interval,true,2)

return interval