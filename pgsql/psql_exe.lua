
local env,db,os,java=env,env.getdb(),os,java
local ora=db.C.ora
local psql_exe=env.class(env.subsystem)

function psql_exe:ctor()
    self.db=env.getdb()
    self.command={'file','-f'}
    self.support_redirect=false
    self.name="psql"
    self.executable="psql"
    self.description="Switch to psql.exe with same login, the default working folder is 'psql/psql'. Usage: @@NAME [-n|-d<work_path>] [other args]"
    self.help_title='Run psql script under the "psql" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."psql",nil
    self.prompt_pattern="^(.+[>\\$#@] *| *\\d+ +)$"
end

function psql_exe:after_process_created()
    if self.work_dir==env._CACHE_PATH and self.work_path then
        self.work_dir,self.work_path=self.work_path,nil
    end
end

function psql_exe:rebuild_commands(work_dir)
    self.cmdlist=self.super.rehash(self,self.script_dir,self.ext_name,self.extend_dirs)
    if work_dir and work_dir~=self.script_dir and work_dir~=self.extend_dirs then
        local cmds=self.super.rehash(self,work_dir,self.ext_name)
        for k,v in pairs(cmds) do
            self.cmdlist[k]=v
        end
    end
end

function psql_exe:run_command(cmd,is_print)
    if not self.enter_flag and cmd then
        cmd=cmd..'\0'
    end
    return self.super.run_command(self,cmd,is_print)
end

function psql_exe:set_work_dir(path,quiet)
    self.super.set_work_dir(self,path,quiet)
    if not quiet and path and path~="" then
        self:rebuild_commands(self.work_dir)
    end
end

function psql_exe:get_startup_cmd(args,is_native)
    db:assert_connect()
    local conn=db.connection_info
    local props={'-w','-U',db.props.db_user,'-p',db.props.port,'-h',db.props.server,'-d',db.props.database}
    self.env['PGPASSWORD']=packer.unpack_str(conn.password)
    if self.work_dir==self.script_dir or self.work_dir==self.extend_dirs then
        self.work_path,self.work_dir=self.work_dir,env._CACHE_PATH
    end
    self:rebuild_commands(self.env['SQLPATH'])
    while #args>0 do
        local arg=args[1]:lower()
        env.checkerr(not (args[1]:find("^-[UpdWwh]$") or 
                          arg:find("^--username") or 
                          arg:find("^--port") or 
                          arg:find("^--password") or
                          arg:find("^--dbname")), "You should not specify user/password/port/database here, those information should be automatically provided.")
        
        if arg:lower()~='-n' and arg~="--unbuffered" then 
            props[#props+1]=arg
        end
        table.remove(args,1)
    end
    return props
end

function psql_exe:run_sql(g_sql,g_args,g_cmd,g_file)
    db:assert_connect()
    local context={}
    for k,v in pairs(g_args[1]) do
        context[#context+1]='SET '..k.." '"..v.."'\\g"
    end
    for i=1,#g_sql do
        context[#context+1]="\\i "..g_file[i]:gsub("[\\/]+","/")
    end
    local tmpfile=env.write_cache("psql.temp",table.concat(context,"\n"))
    self:call_process('-f "'..tmpfile:gsub("[\\/]+","/")..'"')
end

function psql_exe:after_script()
    self.work_path=nil
end

function psql_exe:onload()
    env.event.snoop("AFTER_MYSQL_CONNECT",self.terminate,self)
    env.event.snoop("ON_DB_DISCONNECTED",self.terminate,self)
end

return psql_exe.new()