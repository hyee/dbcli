local env,db,os,java=env,env.getdb(),os,java
local ora=db.C.ora
local sqlplus=env.class(env.subsystem)

function sqlplus:ctor()
    self.db=env.getdb()
    self.command={"sp",'@'}
    self.name="sqlplus"
    self.description="Switch to sqlplus with same login, the default working folder is 'oracle/sqlplus'. Usage: @@NAME [-n|-d<work_path>] [other args]"
    self.help_title='Run SQL*Plus script under the "sqlplus" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."sqlplus",{}
    self.prompt_pattern="^(.+[>\\$#@:] *| *\\d+ +)$"
    self.block_input=true
    self.support_redirect=false
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
        cmd=cmd..'\0'
    end
    return env.subsystem.run_command(self,cmd,is_print)
end

function sqlplus:set_work_dir(path,quiet)
    env.subsystem.set_work_dir(self,path,quiet)
    if not quiet and path and path~="" then
        self:make_sqlpath()
        self:rebuild_commands(self.work_dir)
    end
end

local _os=env.PLATFORM
function sqlplus:make_sqlpath()
    local path={}
    if self.work_dir then path[#path+1]=self.work_dir end
    if self.extend_dirs then path[#path+1]=self.extend_dirs end
    if self.script_dir then path[#path+1]=self.script_dir end
    for i=#path,1,-1 do
        if path[i]:lower():find(env._CACHE_BASE:lower(),1,true) then table.remove(path,i) end
    end
    local cmd='dir /s/b/a:d "'..table.concat(path,'" "')..'" 2>NUL'
    if not env.IS_WINDOWS then
        cmd='find "'..table.concat(path,'" "')..'" -type d 2>/dev/null'
    end
    
    local dirs=io.popen(cmd)
    for n in dirs:lines() do path[#path+1]=n end
    table.sort(path,function(a,b)
        a,b=a:lower(),b:lower()
        local c1=(a:find(self.script_dir:lower(),1,true) and 3) or (self.extend_dirs and a:find(self.extend_dirs:lower(),1,true) and 2) or 1
        local c2=(b:find(self.script_dir:lower(),1,true) and 3) or (self.extend_dirs and b:find(self.extend_dirs:lower(),1,true) and 2) or 1
        if c1~=c2 then return c1<c2 end
        return a<b
    end)
    
    self.env['SQLPATH']=table.concat(path,env.IS_WINDOWS and ';' or ':')
    self.env['ORACLE_PATH']=self.env['SQLPATH']
    env.uv.os.setenv("SQLPATH",self.env['SQLPATH'])
    env.uv.os.setenv("ORACLE_PATH",self.env['ORACLE_PATH'])
    --self.proc:setEnv("SQLPATH",self.env['SQLPATH'])
end

function sqlplus:get_startup_cmd(args,is_native)
    local tnsadm=tostring(java.system:getProperty("oracle.net.tns_admin"))
    local props={}
    --self.env['ORACLE_HOME']="d:\\Soft\\InstanceClient\\bin"
    self:make_sqlpath()
    self.work_path,self.work_dir=self.work_dir,env._CACHE_PATH
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

        db:assert_connect()
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
            loader:mkdir(self.work_path)
        end
        self.work_path=self.work_path:gsub(env.PATH_DEL..'+$','')
        local file_dir=file:gsub('[\\/][^\\/]+$',"")
        local tmpfile='sqlplus.tmp'
        tmpfile=env.join_path(self.work_path,tmpfile)
        local f,err=io.open(tmpfile,'w')
        env.checkerr(f,"Unable to write file "..tmpfile)
        local param=""
        if type(args)=="table" then
            param={}
            for k,v in ipairs(args) do
                if not tostring(v):find('^".*"$') and tostring(v):find("%s") then
                    param[k]='"'..v..'"'
                else
                    param[k]=v
                end
            end
            param=table.concat(param," ") or ""
        end
        content=content:format(self.work_path,file_dir,self.script_dir,context,file,param):gsub('[\n\r]+%s+','\n')..'\n'
        f:write(content)
        f:close()
        self:call_process('@"'..tmpfile..'"')
    end
end

function sqlplus:copy_data(dest,login,table,query)
    env.checkhelp(table)
    local list,account,dest_mask,acc_mask
    local stmt="set long 8000 arraysize 5000 copycommit 1;\n"
    if not query then
        dest,login,table,query="from",dest,login,table
    end
    dest = dest:lower()
    if dest ~="from" and dest ~="to" then
        list,account=env.login.search(dest)
        env.checkerr(account,"Cannot find the login account that exactly matches '%s', type 'login' for more information!",dest)
        dest=string.format('from %s to',env.packer.unpack_str(list.oci_connection))
        if not dest then 
            dest=string.format('from %s/%s@%s to',list.user,env.packer.unpack_str(list.password),list.url:match('[^@]+$'))
        end
        dest_mask=string.format('from %s/***@%s to',list.user,list.url:match('[^@]+$'))
    end
    list,account=env.login.search(login)
    env.checkerr(account,"Cannot find the login account that exactly matches '%s', type 'login' for more information!",login)
    account=env.packer.unpack_str(list.oci_connection)
    if not account then
        account=string.format('from %s/%s@%s to',list.user,env.packer.unpack_str(list.password),list.url:match('[^@]+$'))
    end
    acc_mask=string.format('%s/***@%s',list.user,list.url:match('[^@]+$'))
    stmt=string.format("%scopy %s %s append %s using %s;",stmt,dest,account,table,query:gsub("[\n\r]+"," "))
    local output="SQL*Plus Command:\n=================\n"..stmt:replace(account,acc_mask,true,1)
    if dest_mask then
        output=output:replace(dest,dest_mask,true,1)
    end
    env.rawprint(output)
    if not dest_mask then db:assert_connect() end
    local file="last_sqlplus_script.sql"
    env.write_cache(file,stmt.."\n")
    self:call_process('@"'..env._CACHE_PATH..file..'"')
end    

function sqlplus:after_script()
    self.work_path=nil
end

function sqlplus:f7(n,key_event,str)
    --VK_F7
    if self.enter_flag and key_event.name=='F7' then
        --self:run_command(str)
    end 
end

function sqlplus:__onload()
    
end

function sqlplus:onload()
    --self:make_sqlpath()
    env.event.snoop("AFTER_ORACLE_CONNECT",self.terminate,self)
    env.event.snoop("ON_DB_DISCONNECTED",self.terminate,self)
    local help=[[
    Copy data from one database to another. Usage: @@NAME {[from|to|<source_login>] <login> <table> <query>}
    This command requires sql*plus to be included into current path. 
    The performance of the copy highly relies on the network speed between client and db servers.
    Parameters:
        <login>               : Refer to command 'login', can be the login id or login alias
        <table>               : Target table name, if exists then append data, else create table firstly
        <query>               : Select statement that used as the source data
        from|to|<source_login>: 1) from(default): copy data from <login> db to current db.
                                2) to: copy data from current db to <login> db
                                3) <source_login>:  copy data from <source_login> db to <login> db
    Examples: 
              1) copy 1 objs select * from all_objects; 
              2) copy to 1 objs select * from all_objects;
              3) copy qa uat objs select * from all_objects;]]
    env.set_command(self,{"COPY"},help,self.copy_data,'__SMART_PARSE__',5,true)
end

return sqlplus.new()