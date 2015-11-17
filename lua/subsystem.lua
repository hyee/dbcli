local env=env
local write
local system=env.class(env.scripter)
local winapi=require("winapi")


function system:ctor()
    self.winapi=winapi
    self.handle=nil
    self.process=nil
    self.idle_pattern="^(.-)([^\n\r]+[>$#] )$"
end

function system:run_command(cmd,is_print)
    if cmd then self.handle:write(cmd.."\n") end
    local txt,prompt,msg
    while true do
        txt=self.handle:read()
        if not txt then break end
        msg,prompt=txt:match(self.idle_pattern)
        if is_print then write(msg or txt) end
        if prompt then break end
        self.sleep(0.2)
    end

    if not prompt then
        return self:terminate()
    else
        self.prompt=prompt
        if self.enter_flag then
            env.set_subsystem(self.name,prompt)
        end
    end
end

function system:terminate()
    if not self.process then return end
    pcall(self.process.kill,self.process)
    self.process:close()
    self.process,self.handle=nil,nil
    print("Sub-system '"..self.name.."' is terminated.")
    return env.set_subsystem(nil)
end

function system:call_process(cmd)
    if not self.handle then
        env.find_extension(self.name)
        local cmd=self:get_start_cmd(self.name,self.work_dir)
        self.process,self.handle=winapi.spawn_process(cmd)
        env.checkerr(self.process,self.handle)
        --self.process:wait_async(function(...) print(...);print("Sub-system is terminated") end)
        self:run_command(nil,false)
    end

    if not cmd then 
        env.set_subsystem(self.name,self.prompt)
        self.enter_flag=true
        print(env.ansi.mask("PROMPTCOLOR","You are entering "..self.name.." interactive mode, type '.<cmd>' to run the root command, 'bye' to leave, or 'exit' to terminate."))
        return
    end

    local command=cmd:upper()
    if command=='BYE' then
        return env.set_subsystem(nil)
    elseif command=='EXIT' then
        return self:terminate()
    end
    self:run_command(cmd,true)
end

function system:__onload()
    self.sleep=env.sleep
    write=env.printer.write
    set_command(self,self.name,self.description,self.call_process,false,2)
end

function system:onunload()
    self:terminate()
end

return system