local env=env
local write
local system=env.class(env.scripter)

function system:ctor()
    self.process=nil
    self.proc=java.require("org.dbcli.SubSystem")
    self.idle_pattern="^(.*?)([^\n\r]+[>\\$#] )$"
end

function system:kill_reader(cmds)
    if not self.reader then return end
    if cmds[1]:upper()==self.name:upper() then return end
    self.reader:kill()
    self.reader=nil
end

function system:run_command(cmd,is_print)
    self.prompt=self.process:write(cmd and cmd.."\n" or nil,is_print and true or false)
    if not self.prompt then return self:terminate() end
end

function system:terminate()
    if not self.process then return end
    self.process:close()
    self.process,self.enter_flag,self.startup_cmd=nil,nil,nil
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

function system:make_native_command(arg)
    local env,cmd={},{}
    for k,v in pairs(self.env) do
        env[#env+1]='(set '..k..'='..v.." )"
    end
    env[#env+1]='cd /d "'..self.work_dir..'"'

    for i,v in ipairs(self.startup_cmd) do
        cmd[#cmd+1]='"'..v..'"'
    end

    for i,v in ipairs(arg) do
        cmd[#cmd+1]='"'..v..'"'
    end

    env[#env+1]=table.concat(cmd," ")
    cmd=table.concat(env,' & ')
    return cmd
end

function system:call_process(cmd,is_native)
    if not self.process or is_native==true then
        local args=env.parse_args(99,cmd or "") or {}
        for i=1,#args do
            local k=args[1]:upper()
            if k:sub(1,1)~='-' then break end
            if k=="-N" then 
                is_native=true 
                table.remove(args,1)
            elseif k:find("^%-D") then
                self.work_dir=k:sub(3):gsub('"','')
                table.remove(args,1)
            end
        end
        
        self.env={}

        self.startup_cmd=self:get_startup_cmd(args,is_native)
        table.insert(self.startup_cmd,1,os.find_extension(self.name))
        if not self.work_dir then self.work_dir=env._CACHE_PATH end
        self:set_work_dir(self.work_dir,true)
        
        --self.process:wait_async(function(...) print(...);print("Sub-system is terminated") end)
        if not is_native then
            self.process=self.proc:create(self.idle_pattern,self.work_dir,self.startup_cmd,self.env)
            self.msg_stack={}
            self:run_command(nil,false)
            if #args==0 then 
                cmd=nil
            else
                cmd=table.concat(args," ")
            end
        else
            return os.execute(self:make_native_command(args))
        end
    end

    if not cmd then 
        env.set_subsystem(self.name,self.prompt)
        self.enter_flag=true
        local help=[[
            You are entering '%s' interactive mode, work dir is '%s'.
            To switch to the native CLI mode, execute '-n' or '.%s -n'.
            Type 'lls' to list the files in current work dir, to change the work dir, execute 'llcd <path>'.
            Type '.<cmd>' to run the root command, 'bye' to leave, or 'exit' to terminate."]]
        help=help:format(self.name,self.work_dir,self.name):gsub("%s%s%s+",'\n')
        print(env.ansi.mask("PromptColor",help))
        env.set_subsystem(self.name,self.prompt)
        return
    end

    local command=cmd:upper()
    if command=='BYE' then
        return env.set_subsystem(nil)
    elseif command:find("^%-N") then
        return self:call_process(cmd,true)
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
    env.event.snoop("BEFORE_COMMAND",self.kill_reader,self,1)
end

function system:onunload()
    self:terminate()
end

return system