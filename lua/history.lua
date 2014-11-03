local env,os=env,os
local event,cfg,grid=env.event,env.set,env.grid
local history={}
local keys={}
local lastcommand

function history:show(index)	
	index=tonumber(index)	
	if not index then
		local hdl,counter=grid.new(),0
		grid.add(hdl,{"#","Command"})
		for i=#self,1,-1 do
			counter=counter+1
			grid.add(hdl,{counter,self[i].desc})
		end
		grid.print(hdl)
	else
		local cmd=self[#self-index+1]
		if cmd then
			env.exec_command(cmd.cmd,cmd.args)
		end
	end
end

function history:capture(cmd,args) 
	if (cmd=="HIS" or cmd=="/" or cmd=="R" or cmd=="HISTORY") then return end
	local maxsiz=cfg.get("HISSIZE")	
	local key=table.concat(args," "):gsub("[%s\t\n\r]+"," "):sub(1,300)
	if key:upper():find(cmd.." ")~=1 then
		key=cmd.." "..key
	end
	if keys[key] then
		table.remove(self,keys[key])
	end
	lastcommand={cmd=cmd,desc=key,args=args,tim=os.clock()}
	if maxsiz < 1 then return end
	table.insert(self,lastcommand)
	while #self>maxsiz do
		local k=self[1].desc
		table.remove(self,1)
		keys[k]=nil
	end
	keys[key]=#self
end


function history.rerun()
	if lastcommand then
		env.exec_command(lastcommand.cmd,lastcommand.args)
	end
end

cfg.init("HISSIZE",50,nil,"core","Max size of historical commands",'0 - 999')

event.snoop("AFTER_COMMAND",history.capture,history)

env.set_command(history,{'history','his'},"Show/run historical commands. Usage: his [index]",history.show,false,2)
env.set_command(history,{'r','/'},"Rerun the previous command.",history.rerun,false,2)

return history
