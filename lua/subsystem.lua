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
    self.process,self.handle,self.startup_cmd=nil,nil,nil
    print("Sub-system '"..self.name.."' is terminated.")
    return env.set_subsystem(nil)
end

function system:set_work_dir(path,quiet)
    if path=="" then return print("Current working dir is: "..self.work_dir) end
    path=path=="." and env._CACHE_PATH or path
    env.checkerr(os.exists(path)==2,"No such folder: %s!",path)
    self.work_dir=path
    if not quiet then
        print("Working dir changed to "..path)
    end
end

function system:list_work_dir(filter)
    os.execute('dir "'..self.work_dir..'" /B/S/A:-D '..(filter or ""))
end

function system:call_process(cmd)
    if not self.handle then
        local is_native
        local args=env.parse_args(99,cmd or "") or {}
        for i,k in ipairs(args) do
            if k:upper()=="-F" then 
                is_native=true 
                table.remove(args,i)
            elseif k:upper():find("^%-D") then
                self.work_dir=k:sub(3):gsub('"','')
                table.remove(args,i)
            end
        end
        env.find_extension(self.name)

        self.startup_cmd=self:get_startup_cmd(args)
        if not self.work_dir then self.work_dir=env._CACHE_PATH end
        self:set_work_dir(self.work_dir,true)

        self.process,self.handle=winapi.spawn_process(self.startup_cmd,self.work_dir)
        env.checkerr(self.process,self.handle)
        --self.process:wait_async(function(...) print(...);print("Sub-system is terminated") end)
        if not is_native then
            self:run_command(nil,false)
            if #args==0 then 
                cmd=nil
            else
                cmd=table.concat(args," ")
            end
        else
            return os.execute(self.exec_cmd)
        end
    end

    if not cmd then 
        env.set_subsystem(self.name,self.prompt)
        self.enter_flag=true
        local help=[[
            You are entering '%s' interactive mode, work dir is '%s'.
            To switch to the native CLI mode, execute '-f' or '.%s -f'.
            Type 'lls' to list the files in current work dir, to change the work dir, execute 'llcd <path>'.
            Type '.<cmd>' to run the root command, 'bye' to leave, or 'exit' to terminate."]]
        help=help:format(self.name,self.work_dir,self.name):gsub("%s%s%s+",'\n')
        print(env.ansi.mask("PromptColor",help))
        return
    end

    local command=cmd:upper()
    if command=='BYE' then
        return env.set_subsystem(nil)
    elseif command=="-F" then
        return os.execute(self.startup_cmd)
    elseif command:find("^LLS ") or command=="LLS" then
        return self:list_work_dir(cmd:sub(5))
    elseif command:find("^LCD ") or command=="LCD"  then
        return self:set_work_dir(cmd:sub(5))
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