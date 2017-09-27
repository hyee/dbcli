local env,os=env,os
local event,cfg,grid=env.event,env.set,env.grid
local history={}
local keys={}
history.keys=keys
local lastcommand

function history:show(key)
    local index=tonumber(key)
    if not index then
        if key and key:lower()=="last" then
            print(lastcommand.text)
            return
        end
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
    if #env.RUNNING_THREADS>1 or not args then return end
    --if(cmd==nil) then print(debug.traceback()) end
    cmd=cmd:upper()
    if (cmd=="HIS" or cmd=="/" or cmd=="R" or cmd=="HISTORY" or cmd=='ED' or cmd=='EDIT') then return end
    local maxsiz=cfg.get("HISSIZE")
    local text=table.concat(args," ")
    if text:find(cmd,1,true)~=1 then text=cmd..' '..text end
    local key=text:gsub("[%s%z\128\192]+"," "):sub(1,300)
    local k1=key:upper()
    if keys[k1] then
        table.remove(self,keys[k1])
        for k,v in pairs(keys) do if v>keys[k1] then keys[k]=v-1 end end
    end
    lastcommand={cmd=cmd,desc=key,args=args,tim=os.timer(),clock=clock,key=k1,text=text}
    if maxsiz < 1 then return end
    table.insert(self,lastcommand)
    while #self>maxsiz do
        local k=self[1].key
        table.remove(self,1)
        for o,v in pairs(keys) do if v>1 then keys[o]=v-1 end end
        keys[k]=nil
    end
    keys[k1]=#self
    local file=env.join_path(env._CACHE_PATH,'afiedt.buf')
    local f,err=io.open(file,'w')
    env.checkerr(f,err)
    f:write(lastcommand.text)
    f:close()
end


function history.rerun()
    if lastcommand then
        local file=env.join_path(env._CACHE_PATH,'afiedt.buf')
        local f,err=io.open(file,'r')
        env.checkerr(f,err)
        local text=f:read('*a')
        f:close()
        env.eval_line(text,true,true)
    end
end

function history.edit_buffer()
    if not lastcommand then return end
    local editor=cfg.get("editor")
    local file=env.join_path(env._CACHE_PATH,'afiedt.buf')
    env.checkerr(os.exists(editor),'Cannot find "'..editor..'" in current search path.')
    os.shell(editor,file)
end

function history.set_editor(name,editor)
    editor=os.find_extension(editor)
    return editor
end

function history.onload()
    cfg.init("HISSIZE",50,history.set_editor,"core","Max size of historical commands",'0 - 999')
    cfg.init({"EDITOR",'_EDITOR'},env.PLATFORM=='windows' and 'notepad' or 'vi',history.set_editor,"core","The editor to edit the buffer")
    event.snoop("AFTER_SUCCESS_COMMAND",history.capture,history)
    env.set_command(history,{'history','his'},"Show/run historical commands. Usage: @@NAME [index|last]",history.show,false,2)
    env.set_command(history,{'r','/'},"Rerun the previous command.",history.rerun,false,2)
    env.set_command(history,{'EDIT','ED'},"Use the program that defined in 'set editor' to edit the buffer in order to run with '/'.",history.edit_buffer,false,2)
end

return history
