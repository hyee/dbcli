local env=env
local write
local system=env.class(env.scripter)

function system:ctor()
    self.process=nil
    self.proc=java.require("org.dbcli.SubSystem")
    self.prompt_pattern="^.+[>\\$#@:] *$"
    self.support_redirect=true
end

function system:kill_reader(cmds)
    if not self.reader then return end
    if cmds[1]:upper()==self.name:upper() then return end
    self.reader:kill()
    self.reader=nil
end

function system:get_last_line(cmd)
    if not self.process then return end
    --return self.process:getLastLine(cmd)
end

function system:run_command(cmd,is_print)
    if not self.process then return end
    self.prompt=self.process:execute(cmd,is_print and true or false,self.block_input or false)
    if not self.prompt then return self:terminate() end
    if self.enter_flag==true then env.set_subsystem(self.name,self.prompt) end
end

function system:terminate()
    if not self.process then return end
    self.process:close()
    self.process,self.enter_flag,self.startup_cmd=nil,nil,nil
    print("Sub-system '"..self.name.."' is terminated.")
    return env.set_subsystem(nil)
end

function system:set_work_dir(path,quiet)
    if path=="" then return print("Current working dir is "..self.work_dir) end
    path=path=="." and env._CACHE_PATH or path
    path=env.join_path(path,"")
    env.checkerr(os.exists(path)=='directory',"No such folder: %s!",path)
    self.work_dir=path
    if not quiet then
        print("Working dir changed to "..path)
    end
    if not self.process then return end
end

function system:list_work_dir(filter)
    os.execute((env.IS_WINDOWS and ('dir "'..self.work_dir..'" /B/S/A:-D ') or ('find "'..self.work_dir..'" -type f'))..(filter or ""))
end

function system:make_native_command(arg)
    local is_win=env.IS_WINDOWS
    local env,cmd={},{}
    local function enclose(s)
        return tostring(s):find("%s") and ('"'..s..'"') or s
    end
    for k,v in pairs(self.env) do
        env[#env+1]=is_win and ('(set '..enclose(k..'='..v)..' )') or ('export k="'..v..'"')
    end

    env[#env+1]=(is_win and 'cd /d ' or 'cd ')..enclose(self.work_dir)

    for i,v in ipairs(self.startup_cmd) do
        cmd[#cmd+1]=enclose(v)
    end

    for i,v in ipairs(arg) do
        cmd[#cmd+1]=enclose(v)
    end

    env[#env+1]=table.concat(cmd," ")
    cmd=table.concat(env,is_win and ' & ' or " ; ")
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
                self.work_dir=args[1]:sub(3):gsub('"','')
                table.remove(args,1)
            end
        end
        
        
        self.env={PATH=os.getenv("PATH")}
        if not self.work_dir then self.work_dir=self.extend_dirs or self.script_dir or env._CACHE_PATH end
        local do_redirect
        self.startup_cmd,do_redirect=self:get_startup_cmd(args,is_native)
        if not self.startup_cmd then return end
        table.insert(self.startup_cmd,1,self.boot_cmd or os.find_extension(self.executable or self.name))
        self:set_work_dir(self.work_dir,true)
        env.log_debug("subsystem","Command : " ..table.concat(self.startup_cmd," "))
        env.log_debug("subsystem","Work dir: "..self.work_dir)
        env.log_debug("subsystem","Environment: \n"..table.dump(self.env))

        if (do_redirect or not is_native) and self.support_redirect or (is_native and not self.support_redirect) then
            io.write("Connecting to "..self.name.."...")
            --print(table.concat(self.startup_cmd," "))
            self.process=self.proc:create(self.prompt_pattern,self.work_dir,self.startup_cmd,self.env)
            self.msg_stack={}
            self:run_command(nil,false)
            env.printer.write("$DELLINE$")
            if not self.process then return end
            if self.after_process_created then self:after_process_created() end
            if #args==0 then
                cmd=nil
            else
                cmd=table.concat(args," ")
            end
        else
            local line=self:make_native_command(args)
            terminal:lockReader(true)
            env.log_debug("subsystem","SQL: "..line)
            return os.execute(line)
        end
    end

    if not cmd then 
        env.set_subsystem(self.name,self.prompt)
        self.enter_flag=true
        local help=[[
            You are entering '%s' interactive mode, working dir is '%s'.
            To switch to the native CLI mode, execute '-n' or '.%s -n'.
            Type 'lls' to list the files in current working dir, to change the working dir, execute 'lcd <path>'.
            Type '.<cmd>' to run the root command, 'bye' to leave, or 'exit' to terminate.]]
        help=help:format(self.name,self.work_dir,self.name):gsub("%s%s%s+",'\n'):gsub("^%s+","")
        print(env.ansi.mask("PromptColor",help))
        env.set_subsystem(self.name,self.prompt)
        return
    end

    local command=cmd:upper():gsub("^%s+","")
    if command=='BYE' then
        self.enter_flag=false
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
    env.set_command{obj=self,cmd=self.name, 
                    help_func=self.description,call_func=self.call_process,
                    is_multiline=false,parameters=2,color="PROMPTSUBCOLOR",is_blocknewline=false}
    env.event.snoop("BEFORE_COMMAND",self.kill_reader,self,1)
end

function system:onunload()
    self:terminate()
end

return system