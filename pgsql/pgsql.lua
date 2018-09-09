local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command
local pgsql=env.class(env.db_core)
pgsql.module_list={
   "sql","chart","ssh","snap",
   "show","psql_exe",
}

function pgsql:ctor(isdefault)
    self.type="pgsql"
    self.C,self.props={},{}
    self.C,self.props={},{}
    self.JDBC_ADDRESS='https://jdbc.postgresql.org/download.html'
end

function pgsql:connect(conn_str)
    local args
    local usr,pwd,conn_desc,url
    if type(conn_str)=="table" then
        args=conn_str
        usr,pwd,url=conn_str.user,packer.unpack_str(conn_str.password),conn_str.url:match("//(.*)$")
        args.password=pwd
        conn_str=string.format("%s/%s@%s",usr,pwd,url)
    else
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)/(.*)@(.+)")
        if conn_desc == nil then return exec_command("HELP",{"CONNECT"}) end
        args={user=usr,password=pwd}
        if conn_desc:match("%?.*=.*") then
            for k,v in conn_desc:gmatch("([^=%?&]+)%s*=%s*([^&]+)") do
                args[k]=v
            end
            conn_desc=conn_desc:gsub("%?.*","")
        end
        usr,pwd,url,args.url=args.user,args.password,conn_desc,"jdbc:postgresql://"..conn_desc
    end
    
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')

    self:merge_props(
        {driverClassName="org.postgresql.Driver",
         application_name='psql',
         defaultRowFetchSize=tostring(cfg.get("FETCHSIZE")),
         charSet="UTF8",
         allowEncodingChanges="true",
         preparedStatementCacheQueries=tostring(cfg.get("SQLCACHESIZE")),
         loadBalanceHosts="true"
        },args)
    --print(table.dump(args))   
    
    if event then event("BEFORE_PGSQL_CONNECT",self,sql,args,result) end
    env.set_title("")

    for k,v in pairs(args) do args[k]=tostring(v) end
    self.super.connect(self,args)
    self.conn=java.cast(self.conn,"org.postgresql.jdbc.PgConnection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local info=self:get_value([[select current_database(),substring(version() from '[0-9\.]+'),current_user,inet_server_addr(),inet_server_port(),pg_backend_pid()]])
    self.props.db_version,self.props.server=info[2]:match('^([%d%.]+)'),info[4]
    self.props.db_user,self.props.pid,self.props.port=info[3],info[6],info[5]
    self.props.database=info[1] or ""
    self.connection_info=args
    if not self.props.db_version or tonumber(self.props.db_version:match("^%d+"))<5 then self.props.db_version=info[2]:match('^([%d%.]+)') end
    if tonumber(self.props.db_version:match("^%d+%.%d"))<5.5 then
        env.warn("You are connecting to a lower-vesion pgsql sever, some features may not support.")
    end
    env.set_title(('%s - User: %s   PID: %s   Version: %s   Database: %s'):format(self.props.server,self.props.db_user,self.props.pid,self.props.db_version,self.props.database))
    local prompt=self.props.database..'> '
    env.set_prompt(nil,prompt,nil,2)
    if event then event("AFTER_PGSQL_CONNECT",self,sql,args,result) end
    print("Database connected.")
end

function pgsql:disconnect(...)
    self.super.disconnect(self,...)
    env.set_title("")
end

function pgsql:exec(sql,...)
    local bypass=self:is_internal_call(sql)
    local args,prep_params=nil,{}
    local is_not_prep=type(sql)~="userdata"
    if type(select(1,...) or "")=="table" then
        args=select(1,...)
        if type(select(2,...) or "")=="table" then prep_params=select(2,...) end
    else
        args={...}
    end
    
    if is_not_prep then sql=event("BEFORE_PGSQL_EXEC",{self,sql,args}) [2] end
    local result=self.super.exec(self,sql,...)
    if is_not_prep and not bypass then 
        event("AFTER_PGSQL_EXEC",self,sql,args,result)
        self.print_feed(sql,result)
    end
    return result
    
end

function pgsql:command_call(sql,...)
    local bypass=self:is_internal_call(sql)
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_PGSQL_EXEC",{self,sql,args}) [2]
    env.checkhelp(#env.parse_args(2,sql)>1)
    local result=self.super.exec(self,sql,{args})
    if not bypass then event("BEFORE_MYSQL_EXEC",self,sql,args,result) end
    self:print_result(result,sql)
end

function pgsql:onload()
    local default_desc={"#PgSQL database SQL command",self.help_topic}
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.command_call,true,1,true)
        end
    end



    add_default_sql_stmt('ABORT','ALTER','ANALYZE','BEGIN','CHECKPOINT','CLOSE','CLUSTER','COMMENT','COPY','DEALLOCATE','DECLARE')
    add_default_sql_stmt('DELETE','DISCARD','DROP','END','EXECUTE','EXPLAIN','FETCH','GRANT','IMPORT','INSERT','LISTEN','LOAD','LOCK','MOVE','NOTIFY','PREPARE')
    add_default_sql_stmt('REASSIGN','REFRESH','REINDEX','RELEASE','RESET','REVOKE','SECURITY','SELECT','START','TRUNCATE','UNLISTEN','UPDATE','VACUUM','WITH')
    set_command(self,"create", default_desc, self.exec,self.check_completion,1,true)
    set_command(self,"do", default_desc, self.exec,self.check_completion,1,true)
    local  conn_help = [[
        Connect to pgsql database. Usage: @@NAME <user>/<password>@<host>[:<port>][/<database>][?<properties>]
        Example:  @@NAME postgres/@localhost/postgres     --if not specify the port, then it is 5432
                  @@NAME postgres/newpwd@localhost:5432/postgres
    ]]
    set_command(self,{"connect",'conn'},  conn_help,self.connect,false,2)
    env.set.change_default("null","NULL")
    env.set.change_default("autocommit","on")
    env.event.snoop("ON_SET_NOTFOUND",self.set,self)
    env.event.snoop("BEFORE_EVAL",self.on_eval,self)
    env.event.snoop('ON_SQL_PARSE_ERROR',self.handle_error,self,1)
    self.C={}
    self.source_objs.DO=1
    self.source_objs.DECLARE=nil
    self.source_objs.BEGIN=nil
    env.db_core.source_obj_pattern={"$$%s+%w+%s+%w+%s*$","$$%s*$"}
end

function pgsql:handle_error(info)
    --print(self:is_connect(),cfg.get("AUTOCOMMIT"))
    if self:is_connect() and cfg.get("AUTOCOMMIT")=="off" then
        cfg.set('feed','off')
        self:rollback()
        cfg.set('feed','back')
    end
    return info;
end

function pgsql:on_eval(line)
    --[[
    local first,near,symbol,rest=line:match("^(.*)(.)\\([gG])(.*)")
    if not first or near=="\\" then return end
    if near==env.COMMAND_SEPS[1] then near="" end
    if not env.pending_command() then

    end
    --]]
    local c=line[1]:sub(-2)
    if c:lower()=="\\g" then
        line[1]=line[1]:sub(1,-3)..'\0'
        if c=="\\G" then
            env.set.doset("PIVOT",20)
        end
    end
end

function pgsql:set_session(name,value)
    self:assert_connect()
    return self:exec(table.concat({"SET",name,value}," "))
end

function pgsql:set(item)
    if not self:is_connect() then return end
    local cmd="SET "..table.concat(item," ")
    item[1]=true
    self:exec(cmd)
end

function pgsql:onunload()    
    env.set_title("")
end

return pgsql.new()