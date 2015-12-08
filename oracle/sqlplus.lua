
local env,db,os,java=env,env.oracle,os,java
local ora=db.C.ora
local sqlplus=env.class(env.subsystem)

function sqlplus:ctor()
    self.db=env.oracle
    self.command={"sp",'@'}
    self.name="sqlplus"
    self.description="Switch to sqlplus with same login, the default working folder is 'oracle/sqlplus'. Usage: sqlplus [-n|-d<work_path>] [other args]"
    self.help_title='Run SQL*Plus script under the "sqlplus" directory. '
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."sqlplus",{}
    self.prompt_pattern="^(.+[>\\$#@] *| *\\d+ +)$"
end


function sqlplus:after_process_created()
    self.work_dir=self.work_path
    print(self:get_last_line("select * from(&prompt_sql);"))
    self:run_command('store set dbcli_sqlplus_settings.sql replace',false)
end

function sqlplus:rebuild_commands(work_dir)
    self.cmdlist=self.super.rehash(self,self.script_dir,self.ext_name,self.extend_dirs)
    if work_dir and work_dir~=self.script_dir and work_dir~=self.extend_dirs then
        local cmds=self.super.rehash(self,work_dir,self.ext_name)
        for k,v in pairs(cmds) do
            self.cmdlist[k]=v
        end
    end
end

function sqlplus:run_command(cmd,is_print)
    if not self.enter_flag and cmd then
        cmd=cmd..env.END_MARKS[1]
    end
    return self.super.run_command(self,cmd,is_print)
end

function sqlplus:set_work_dir(path,quiet)
    self.super.set_work_dir(self,path,quiet)
    if not quiet and path and path~="" then
        self:make_sqlpath()
        self:rebuild_commands(self.work_dir)
    end
end

function sqlplus:make_sqlpath()
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

function sqlplus:get_startup_cmd(args,is_native)
    local tnsadm=tostring(java.system:getProperty("oracle.net.tns_admin"))
    local export=env.OS=="windows" and "set " or "export "
    local props={}
    if tnsadm and tnsadm~="" then self.env["TNS_ADMIN"]=tnsadm end
    if db.props.db_nls_lang then self.env["NLS_LANG"]=db.props.db_nls_lang end
    self.env['NLS_DATE_FORMAT']='YYYY-MM-DD HH24:MI:SS'
    self:make_sqlpath()
    self.work_path,self.work_dir=self.work_dir,env._CACHE_PATH
    self:rebuild_commands(self.env['SQLPATH'])
    while #args>0 do
        local arg=args[1]:lower()
        if arg:sub(1,1)~='-' then break end
        if arg:lower()~='-s' or is_native then 
            props[#props+1]=arg
        end
        table.remove(args,1)
        if args[1] and arg=="-c" or arg=='-m' or arg=='-r' then
            props[#props+1]=args[1]
            table.remove(args,1)
        end
    end

    env.checkerr(not args[1] or not args[1]:find(".*/.*@.+"),"You cannot specify user/pwd here, default a/c should be used!")
    
    props[#props+1]=(env.packer.unpack_str(db.conn_str) or "/nolog")
    if db.props.service_name then
        props[#props]=props[#props]:gsub("%:[%w_]+ ",'/'..db.props.service_name)
    end
    
    return props
end

function sqlplus:run_sql(g_sql,g_args,g_cmd,g_file)
    for i=1,#g_sql do
        local sql,args,cmd,file=g_sql[i],g_args[i],g_cmd[i],g_file[i]
        local content=[[DEF _WORK_DIR_="%s"
                        DEF _FILE_DIR_="%s"
                        DEF _SQLPLUS_DIR_="%s"
                        %s
                        @"%s" %s
                        @dbcli_sqlplus_settings.sql]]

        env.checkerr(db:is_connect(),"Database is not connected.")
        local context=""
        for k,v in pairs(args) do
            if v==db.NOT_ASSIGNED then v='' end
            local msg='DEF '..k.."='"..v.."'\n"
            context=context..msg
            if k:match("^V%d+$") and v~='' then context=context..msg:gsub("V(%d+)",'%1',1) end
        end

        self.work_path=env._CACHE_PATH
        local subdir=args.FILE_OUTPUT_DIR
        if subdir then
            self.work_path=self.work_path..subdir
            os.execute('mkdir "'..self.work_path..'" >nul')
        end
        self.work_path=self.work_path:gsub(env.PATH_DEL..'+$','')
        local file_dir=file:gsub('[\\/][^\\/]+$',"")
        local tmpfile='sqlplus.tmp'
        tmpfile=self.work_path..env.PATH_DEL..tmpfile
        local f,err=io.open(tmpfile,'w')
        env.checkerr(f,"Unable to write file "..tmpfile)
        content=content:format(self.work_path,file_dir,self.script_dir,context,file,arg or ""):gsub('[\n\r]+%s+','\n')..'\n'
        f:write(content)
        f:close()
        self:call_process('@"'..tmpfile..'"')
    end
end

function sqlplus:after_script()
    self.work_path=nil
end

function sqlplus:f7(n,key_event,str)
    --VK_F7
    if self.enter_flag and key_event[2]==118 then
        self:run_command(str)
    end 
end

function sqlplus:onload()
    env.event.snoop("AFTER_ORACLE_CONNECT",self.terminate,self)
    env.event.snoop("ON_DB_DISCONNECTED",self.terminate,self)
    --env.event.snoop("ON_KEY_EVENT",self.f7,self)
end

return sqlplus.new()