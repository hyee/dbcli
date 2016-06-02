local env,os=env,os
local event,cfg,grid=env.event,env.set,env.grid
local history={}
local keys={}
history.keys=keys
local lastcommand

function history:show(index)
    index=tonumber(index)
    if not index then
        local hdl,counter=grid.new(),0
        grid.add(hdl,{"#","Secs","Command"})
        for i=#self,1,-1 do
            counter=counter+1
            grid.add(hdl,{counter,self[i].clock,self[i].desc})
        end
        grid.print(hdl)
    else
        local cmd=self[#self-index+1]
        if cmd then
            env.exec_command(cmd.cmd,cmd.args)
        end
    end
end

function history:capture(cmd,args,res,is_internal,command_text,clock)
    if #env.RUNNING_THREADS>1 then return end
    --if(cmd==nil) then print(debug.traceback()) end
    cmd=cmd:upper()
    if (cmd=="HIS" or cmd=="/" or cmd=="R" or cmd=="HISTORY") then return end
    local maxsiz=cfg.get("HISSIZE")
    local key=command_text:gsub("[%s%z\128\192]+"," "):sub(1,300)
    local k1=key:upper()
    if keys[k1] then
        table.remove(self,keys[k1])
        for k,v in pairs(keys) do if v>keys[k1] then keys[k]=v-1 end end
    end
    lastcommand={cmd=cmd,desc=key,args=args,tim=os.clock(),clock=clock,key=k1}
    if maxsiz < 1 then return end
    table.insert(self,lastcommand)
    while #self>maxsiz do
        local k=self[1].key
        table.remove(self,1)
        for o,v in pairs(keys) do if v>1 then keys[o]=v-1 end end
        keys[k]=nil
    end
    keys[k1]=#self
end


function history.rerun()
    if lastcommand then
        env.exec_command(lastcommand.cmd,lastcommand.args)
    end
end

function history.onload()
    cfg.init("HISSIZE",50,nil,"core","Max size of historical commands",'0 - 999')
    event.snoop("AFTER_SUCCESS_COMMAND",history.capture,history)
    env.set_command(history,{'history','his'},"Show/run historical commands. Usage: @@NAME [index]",history.show,false,2)
    env.set_command(history,{'r','/'},"Rerun the previous command.",history.rerun,false,2)
end

return history
