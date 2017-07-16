local env=env
local write=env.printer.write
local uv = require('uv')

local handle, pid

local function onexit(code, signal)
    rint('exit',code,signal)
end

local process=env.class(env.scripter)
function process:ctor()
    self.process=nil
    self.proc=java.require("org.dbcli.SubSystem")
    self.prompt_pattern="^.+[>$#@] *$"
    self.support_redirect=true
    
end

function process:on_read(err,chunk)
    write('1')
    env.checkerr(not err,err)
    if chunk then
        write(chunk)
    else
        write('1')
    end
end

function process:kill_reader(cmds)
    if not self.reader then return end
    if cmds[1]:upper()==self.name:upper() then return end
    self.reader:kill()
    self.reader=nil
end

function process:get_last_line(cmd)
    if not self.process then return end
    --return self.process:getLastLine(cmd)
end

function process:run_command(cmd,is_print)
    if not self.process then return end
    if cmd then
        self.stdin.write(cmd..'\n')
    end
    self.prompt='SQL> '
   
    if not self.prompt then return self:terminate() end
    if self.enter_flag==true then env.set_subsystem(self.name,self.prompt) end
end

function process:terminate()
    if not self.process then return end
    uv.shutdown(self.stdin)
    uv.walk(uv.close)
    self.process,self.enter_flag,self.startup_cmd=nil,nil,nil
    print("Sub-system '"..self.name.."' is terminated.")
    return env.set_subsystem(nil)
end

function process:set_work_dir(path,quiet)
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

function process:list_work_dir(filter)

    os.execute('dir "'..self.work_dir..'" /B/S/A:-D '..(filter or ""))
end

function process:make_native_command(arg)
    local env,cmd={},{}
    local function enclose(s)
        return tostring(s):find("%s") and ('"'..s..'"') or s
    end
    for k,v in pairs(self.env) do
        env[#env+1]='(set '..enclose(k..'='..v)..' )'
    end

    env[#env+1]='cd /d '..enclose(self.work_dir)

    for i,v in ipairs(self.startup_cmd) do
        cmd[#cmd+1]=enclose(v)
    end

    for i,v in ipairs(arg) do
        cmd[#cmd+1]=enclose(v)
    end

    env[#env+1]=table.concat(cmd," ")
    cmd=table.concat(env,' & ')
    return cmd
end

function process:call_process(cmd,is_native)
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
        self.startup_cmd=self:get_startup_cmd(args,is_native)
        table.insert(self.startup_cmd,1,os.find_extension(self.executable or self.name))
        
        self:set_work_dir(self.work_dir,true)
        env.log_debug("subsystem","Command : " ..table.concat(self.startup_cmd," "))
        env.log_debug("subsystem","Work dir: "..self.work_dir)
        env.log_debug("subsystem","Environment: \n"..table.dump(self.env))
        if not is_native and self.support_redirect then
            io.write("Connecting to "..self.name.."...")
            --print(table.concat(self.startup_cmd," "))
            local cmd=self.startup_cmd[1]
            table.remove(self.startup_cmd,1)
            self.stdout,self.stderr,self.stdin = uv.pipe.new(false),uv.pipe.new(false),uv.pipe.new(false)
            local options={stdio={self.stdin,self.stdout,self.stderr},verbatim=true,args=self.startup_cmd}
            options.env={}
            for k,v in pairs(self.env) do options.env[#options.env+1]=k..'='..v end
            options.cwd=self.work_dir
            self.process = uv.spawn(cmd,options, onexit)
            local reader=function(...) self:on_read(...) end
            uv.read_start(self.stdout, reader)
            uv.read_start(self.stderr, reader)
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

function process:__onload()
    self.sleep=env.sleep
    write=env.printer.write
    env.set_command{obj=self,cmd=self.name, 
                    help_func=self.description,call_func=self.call_process,
                    is_multiline=false,parameters=2,color="PROMPTSUBCOLOR"}
    env.event.snoop("BEFORE_COMMAND",self.kill_reader,self,1)
end

function process:onunload()
    self:terminate()
end

return process