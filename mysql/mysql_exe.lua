
local env,db,os,java=env,env.getdb(),os,java
local ora=db.C.ora
local mysql_exe=env.class(env.subsystem)

function mysql_exe:ctor()
    self.db=env.getdb()
    self.command={"source",'\\.',"ms"}
    self.support_redirect=false
    self.name="mysql"
    self.executable="mysql"
    self.description="Switch to mysql.exe with same login, the default working folder is 'mysql/mysql'. Usage: @@NAME [-n|-d<work_path>] [other args]"
    self.help_title='Run mysql script under the "mysql" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."mysql",nil
    self.prompt_pattern="^(.+[>\\$#@] *| *\\d+ +)$"
end

function mysql_exe:after_process_created()
    if self.work_dir==env._CACHE_PATH and self.work_path then
        self.work_dir,self.work_path=self.work_path,nil
    end
end

function mysql_exe:rebuild_commands(work_dir)
    self.cmdlist=self.super.rehash(self,self.script_dir,self.ext_name,self.extend_dirs)
    if work_dir and work_dir~=self.script_dir and work_dir~=self.extend_dirs then
        local cmds=self.super.rehash(self,work_dir,self.ext_name)
        for k,v in pairs(cmds) do
            self.cmdlist[k]=v
        end
    end
end

function mysql_exe:run_command(cmd,is_print)
    if not self.enter_flag and cmd then
        cmd=cmd..'\0'
    end
    return self.super.run_command(self,cmd,is_print)
end

function mysql_exe:set_work_dir(path,quiet)
    self.super.set_work_dir(self,path,quiet)
    if not quiet and path and path~="" then
        self:rebuild_commands(self.work_dir)
    end
end

function mysql_exe:get_startup_cmd(args,is_native)
    db:assert_connect()
    local conn=db.connection_info
    local props={"--default-character-set=utf8",'-n','-u',conn.user,'-P',conn.port,'-h',conn.hostname}
    if db.props.database~="" then
        props[#props+1]="--database="..db.props.database
    end
    local pwd=packer.unpack_str(conn.password)
    if (pwd or "")~="" then
        props[#props+1]="--password="..pwd
    end
    if self.work_dir==self.script_dir or self.work_dir==self.extend_dirs then
        self.work_path,self.work_dir=self.work_dir,env._CACHE_PATH
    end
    self:rebuild_commands(self.env['SQLPATH'])
    while #args>0 do
        local arg=args[1]:lower()
        env.checkerr(not (args[1]:find("^-[upPD]$") or 
                          arg:find("^--user") or 
                          arg:find("^--port") or 
                          arg:find("^--password") or
                          arg:find("^--database")), "You should not specify user/password/port/database here, those information should be automatically provided.")
        
        if arg:lower()~='-n' and arg~="--unbuffered" then 
            props[#props+1]=arg
        end
        table.remove(args,1)
    end
    return props
end

function mysql_exe:run_sql(g_sql,g_args,g_cmd,g_file)
    db:assert_connect()
    local context={}
    for k,v in pairs(g_args[1]) do
        context[#context+1]='SET @'..k.."='"..v.."'\\g"
    end
    for i=1,#g_sql do
        context[#context+1]="source "..g_file[i]:gsub("[\\/]+","/")
    end
    local tmpfile=env.write_cache("mysql.temp",table.concat(context,"\n"))
    self:call_process('-t < "'..tmpfile:gsub("[\\/]+","/")..'"')
end

function mysql_exe:after_script()
    self.work_path=nil
end

function mysql_exe:onload()
    env.event.snoop("AFTER_MYSQL_CONNECT",self.terminate,self)
    env.event.snoop("ON_DB_DISCONNECTED",self.terminate,self)
end

return mysql_exe.new()