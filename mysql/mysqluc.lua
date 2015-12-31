
local env,db,os,java=env,env.getdb(),os,java
local ora=db.C.ora
local utils=env.class(env.subsystem)

function utils:ctor()
    self.db=env.getdb()
    self.support_redirect=false
    self.name="mysqluc"
    self.command=nil
    self.executable="mysqluc.exe"
    self.description="Switch to MySQL Utilities, the default working folder is 'mysql/util'. Usage: @@NAME [-n|-d<work_path>] [other args]"
    self.help_title='Run mysql script under the "mysqluc" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."mysqluc",{}
    self.prompt_pattern="^(.+[>\\$#@] *| *\\d+ +)$"
end


function utils:after_process_created()
    self.work_dir=self.work_path
    print(self:get_last_line("select * from(&prompt_sql);"))
    self:run_command('store set dbcli_utils_settings.sql replace',false)
end

function utils:rebuild_commands(work_dir)
    self.cmdlist=self.super.rehash(self,self.script_dir,self.ext_name,self.extend_dirs)
    if work_dir and work_dir~=self.script_dir and work_dir~=self.extend_dirs then
        local cmds=self.super.rehash(self,work_dir,self.ext_name)
        for k,v in pairs(cmds) do
            self.cmdlist[k]=v
        end
    end
end

function utils:run_command(cmd,is_print)
    if not self.enter_flag and cmd then
        cmd=cmd..env.END_MARKS[1]
    end
    return self.super.run_command(self,cmd,is_print)
end

function utils:set_work_dir(path,quiet)
    self.super.set_work_dir(self,path,quiet)
    if not quiet and path and path~="" then
        self:make_sqlpath()
        self:rebuild_commands(self.work_dir)
    end
end

function utils:make_sqlpath()
    local path={}
    if self.work_dir then path[#path+1]=self.work_dir end
    if self.extend_dirs then path[#path+1]=self.extend_dirs end
    if self.script_dir then path[#path+1]=self.script_dir end
    for i=#path,1,-1 do
        if path[i]:lower():find(env._CACHE_BASE:lower(),1,true) then table.remove(path,i) end
    end
    local dirs=io.popen('dir /s/b/a:d "'..table.concat(path,'" "')..'" 2>nul')
    for n in dirs:lines() do path[#path+1]=n end
    table.sort(path,function(a,b)
        a,b=a:lower(),b:lower()
        local c1=(a:find(self.script_dir:lower(),1,true) and 3) or (self.extend_dirs and a:find(self.extend_dirs:lower(),1,true) and 2) or 1
        local c2=(b:find(self.script_dir:lower(),1,true) and 3) or (self.extend_dirs and b:find(self.extend_dirs:lower(),1,true) and 2) or 1
        if c1~=c2 then return c1<c2 end
        return a<b
    end)
    self.env['SQLPATH']=table.concat(path,';')
    --self.proc:setEnv("SQLPATH",self.env['SQLPATH'])
end

function utils:get_startup_cmd(args,is_native)
    env.checkerr(db:is_connect(),"Database is not connected!")
    local conn=db.connection_info
    local props={"--utildir=="..self.work_dir,'--width=200'}
    self:make_sqlpath()
    self.work_path,self.work_dir=self.work_dir,env._CACHE_PATH
    self:rebuild_commands(self.env['SQLPATH'])
    for k,v in ipairs(args) do
        if args[i]:find("^--utildir=.+") then 
            props[1]=v
            self.work_dir=v:match("=(.*+)")
        elseif args[i]:find("^--width=.+") then
            props[2]=v
        else
            props[#props+1]=v
        end
    end
    return props
end

function utils:run_sql(g_sql,g_args,g_cmd,g_file)
    
end

function utils:after_script()
    self.work_path=nil
end

function utils:onload()
    env.event.snoop("AFTER_MYSQL_CONNECT",self.terminate,self)
    env.event.snoop("ON_DB_DISCONNECTED",self.terminate,self)
end

return utils.new()