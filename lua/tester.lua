local env=env
local tester={}
function tester.do_test(target)
	if target=="" then target=nil end
	if not target or taget=="ALL" then
		local list,keys={},{}
		for k,v in pairs(env) do
			if type(v)=="table" then
				if type(v.tester)=="function" then
					list[k]=v.tester
					table.insert(keys,k)
				end
			  --if type(v.C)=="table" then end
			end
		end
		table.sort(keys)
		if #keys==0 then return print("No available modules.") end
		if not target then print("Available modules:") end
		for i,k in ipairs(keys) do
			if not target then 
				print(string.format("%3s %s",i,k))
			else
				print("Start running unit test on '"..k.."'' module...")
				pcall(list[k],env[k])
			end
		end
	else
		assert(type(env[target])=="table","CLI-00001: No such module["..target.."]!")
		assert(type(env[target].tester)=="function","CLI-00002: Module['..target..'] does not have the tester function!")
		print("Start running unit test on '"..target.." module ...")
		pcall(env[target].tester,env[target])
	end
end

env.set_command(nil,"tester","#Invoke unit test on existing modules",tester.do_test,false,2)
return tester