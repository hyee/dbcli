local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command
local pgsql=env.class(env.db_core)
pgsql.module_list={
   "dict","findobj","desc","sql","list","gaussdb","chart","ssh","snap",
   "show","psql_exe",
}

function pgsql:ctor(isdefault)
    self.type="pgsql"
    self.props={}
    self.JDBC_ADDRESS='https://jdbc.postgresql.org/download.html'
end

local prev_conn=nil
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
        if conn_desc == nil then
            if prev_conn==nil or not (conn_str or ""):find("^[a-zA-Z][a-zA-Z0-9$_]+$") then
                return exec_command("HELP",{"CONNECT"})
            end
            args=prev_conn
            usr,pwd,conn_desc=args.user,args.password,args.url:match("//(.*)$"):gsub('/.-$','/'..conn_str)
            print('Trying to connecte to database "'..conn_str..'" with account "'..usr..'" ...')
        else
            args={user=usr,password=pwd}
        end
        
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
    
    if event then event("BEFORE_PGSQL_CONNECT",self,args) end
    env.set_title("")

    for k,v in pairs(args) do args[k]=tostring(v) end
    self.super.connect(self,args)
    self.conn=java.cast(self.conn,"org.postgresql.jdbc.PgConnection")
    prev_conn=table.clone(args)
    prev_conn.password=pwd
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local info=self:get_value([[
        select current_database(),
               substring(version() from '[0-9\.]+'),
               current_user,
               inet_server_addr(),
               inet_server_port(),
               pg_backend_pid(),
               (select count(1) cnt from pg_proc where proname like '%gauss_version') gaussdb,
               (select setting from pg_settings where name='plan_cache_mode'),
               (select 1 from pg_views where viewname='pg_stat_statements')]])
    table.clear(self.props)
    self.props.privs={}
    self.props.db_version,self.props.server=info[2]:match('^([%d%.]+)'),info[4]
    self.props.db_user,self.props.pid,self.props.port=info[3],info[6],info[5]
    self.props.gaussdb=info[7]>0 and true or nil 
    self.props.plan_cache_mode=info[8]~='' and info[8] or nil
    self.props.pg_stmts=info[9]==1 and true or nil
    self.props.database=info[1] or ""
    self.connection_info=args
    if not self.props.db_version or tonumber(self.props.db_version:match("^%d+"))<5 then self.props.db_version=info[2]:match('^([%d%.]+)') end
    if tonumber(self.props.db_version:match("^%d+%.%d"))<5 then
        env.warn("You are connecting to a lower-vesion pgsql sever, some features may not support.")
    end
    env._CACHE_PATH=env.join_path(env._CACHE_BASE,self.props.database:lower():trim(),'')
    loader:mkdir(env._CACHE_PATH)
    env.set_title(('%s - User: %s   PID: %s   Version: %s   Database: %s'):format(self.props.server,self.props.db_user,self.props.pid,self.props.db_version,self.props.database))
    local prompt=self.props.database=="" and "SQL" or self.props.database
    env.set_prompt(nil,prompt,nil,2)
    if event then event("AFTER_PGSQL_CONNECT",self,args,self.props) end
    print("Database connected.")
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
    if not bypass then event("BEFORE_PGSQL_EXEC",self,sql,args,result) end
    self:print_result(result,sql)
end

function pgsql:after_db_exec()
    if self.current_statement and not self.current_statement:isClosed() then
        local warnings=self.current_statement:getWarnings()
        local flag
        while warnings ~= nil do
            flag=true
            local warn=tostring(warnings)
            if warn then 
                print((warn:gsub('org.postgresql%S+: (.*)','%1',1)))
            end
            warnings=warnings:getNextWarning()
        end
        if flag then self.current_statement:clearWarnings() end
    end
end

function pgsql:onload()
    env.set.rename_command('ENV')
    local default_desc={"#PgSQL database SQL command",self.help_topic}
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.command_call,true,1,true)
        end
    end

    add_default_sql_stmt('ABORT','ALTER','ANALYZE','BEGIN','CHECKPOINT','CLOSE','CLUSTER','COMMENT','COPY','DEALLOCATE','DECLARE')
    add_default_sql_stmt('DELETE','DISCARD','DROP','END','EXECUTE','EXPLAIN','FETCH','GRANT','IMPORT','INSERT','LISTEN','LOAD','LOCK','MOVE','NOTIFY','PREPARE')
    add_default_sql_stmt('SET','REASSIGN','REFRESH','REINDEX','RELEASE','RESET','REVOKE','SECURITY','SELECT','START','TRUNCATE','UNLISTEN','UPDATE','VACUUM','WITH')
    set_command(self,"create", default_desc, self.exec,self.check_completion,1,true)
    set_command(self,"do", default_desc, self.exec,self.check_completion,1,true)
    local  conn_help = [[
        Connect to pgsql database. Usage: @@NAME {<user>/<password>@<host>[:<port>][/<database>][?<properties>] | <database> }
        Example:  @@NAME postgres/@localhost/postgres              --if not specify the port, then it is 5432
                  @@NAME postgres/newpwd@localhost:5432/postgres
                  @@NAME <database>                                --switch to another database with current account
    ]]
    set_command(self,{"connect",'conn'},  conn_help,self.connect,false,2)
    --env.set.change_default("null","nil")
    env.set.change_default("autocommit","on")
    env.event.snoop('AFTER_DB_EXEC',self.after_db_exec,self,1)
    env.event.snoop('ON_SQL_ERROR',self.handle_error,self,1)
    self.source_objs.DO=1
    self.source_objs.DECLARE=nil
    self.source_objs.BEGIN=nil
    local end_='[eE][nN][dD];?%s*'
    env.db_core.source_obj_pattern={end_.."$%w*$%s*%w+%s+%w+","$%w*$"}
end

function pgsql:handle_error(info)
    info.position=tonumber(info.error:match("%s+Position: (%d+)"))
    if self:is_connect() and cfg.get("AUTOCOMMIT")=="off" then
        cfg.set('feed','off')
        self:rollback()
        cfg.set('feed','back')
    end
    return info;
end

function pgsql:set_session(name,value)
    self:assert_connect()
    return self:exec(table.concat({"SET",name,value}," "))
end


function pgsql:onunload()    
    env.set_title("")
end

function pgsql:finalize()
    env.set.change_default("SQLTERMINATOR",";,\\n%s*/,\\g")

end

return pgsql.new()