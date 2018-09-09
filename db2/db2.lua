local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command
local db2=env.class(env.db_core)
db2.module_list={
    "sqlstate",
    "snap",
    "sql",
    "chart",
    "ssh",
}



function db2:ctor(isdefault)
    self.type="db2"
    self.C,self.props={},{}
    self.C,self.props={},{}
end

function db2:connect(conn_str)
    
    java.system:setProperty('db2.jcc.charsetDecoderEncoder',3)

    local args
    local usr,pwd,conn_desc
    if type(conn_str)=="table" then
        args=conn_str
        usr,pwd,conn_desc=conn_str.user,
            packer.unpack_str(conn_str.password),
            conn_str.url:match("//(.*)$")--..(conn_str.internal_logon and " as "..conn_str.internal_logon or "")
        args.password=pwd
        conn_str=string.format("%s/%s@%s",usr,pwd,conn_desc)
    else
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)/(.*)@(.+)")
    end

    if conn_desc == nil then return exec_command("HELP",{"CONNECT"}) end

    conn_desc=conn_desc:gsub('^(/+)','')
    local server,port,alt,database=conn_desc:match('^([^:/%^]+)(:?%d*)(%^?[^/]*)/(.+)$')
    if database then
        if port=="" then port=':50000' end
        conn_desc=server..port..'/'..database
        local alt_addr,alt_port=alt:gsub('[%s%^]+',''):match('([^:]+)(:*.*)')
    else
        database=conn_desc
    end
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')

    local url, isdba=conn_desc:match('^(.*) as (%w+)$')
    url = url or conn_desc

    args=args or {user=usr,password=pwd,url="jdbc:db2://"..url,
                  internal_logon=isdba,
                  server=server,
                  database=database,
                  enableSysplexWLB='true',
                  enableSeamlessFailover='1',
                  clientRerouteAlternateServerName=alt_addr,
                  clientRerouteAlternatePortNumber=alt_addr and (alt_port or port):sub(2)}

    self:merge_props(
        {driverClassName="com.ibm.db2.jcc.DB2Driver",
         retrieveMessagesFromServerOnGetMessage='true',
         clientProgramName='SQL Developer',
         useCachedCursor=self.MAX_CACHE_SIZE
        },args)

    self:load_config(url,args)
    local prompt=(args.jdbc_alias or url):match('([^:/@]+)$')
    if event then event("BEFORE_DB2_CONNECT",self,sql,args,result) end
    env.set_title("")

    self.super.connect(self,args)

    self.conn=java.cast(self.conn,"com.ibm.db2.jcc.DB2Connection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local version=self:get_value("select SERVICE_LEVEL FROM TABLE(sysproc.env_get_inst_info())")
    self.props.db_version=version:gsub('DB2',''):match('([%d%.]+)')
    self.props.db_user=args.user:upper()
    self.props.database=database
    self.conn_str=packer.pack_str(conn_str)

    prompt=(prompt or database:upper()):match("^([^,%.&]+)")
    env.set_prompt(nil,prompt,nil,2)

    env.set_title(('%s - User: %s   Server: %s   Version: DB2(%s)'):format(database,self.props.db_user,server,self.props.db_version))
    if event then event("AFTER_DB2_CONNECT",self,sql,args,result) end
    print("Database connected.")
end

function db2:disconnect(...)
    self.super.disconnect(self,...)
    env.set_title("")
end

function db2:exec(sql,...)
    local bypass=self:is_internal_call(sql)
    local args,prep_params=nil,{}
    local is_not_prep=type(sql)~="userdata"
    if type(select(1,...) or "")=="table" then
        args=select(1,...)
        if type(select(2,...) or "")=="table" then prep_params=select(2,...) end
    else
        args={...}
    end
    
    if is_not_prep then sql=event("BEFORE_DB2_EXEC",{self,sql,args}) [2] end
    local result=self.super.exec(self,sql,...)
    if is_not_prep and not bypass then 
        event("AFTER_DB2_EXEC",self,sql,args,result)
        self.print_feed(sql,result)
    end
    return result
end

function db2:command_call(sql,...)
    local bypass=self:is_internal_call(sql)
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_DB2_EXEC",{self,sql,args}) [2]
    local result=self.super.exec(self,sql,{args})
    if not bypass then event("AFTER_DB2_EXEC",self,sql,args,result) end
    self:print_result(result,sql)
end

function db2:admin_cmd(cmd)
    env.checkhelp(cmd)
    self:command_call('call sysproc.admin_cmd(:1)',cmd or "")
end

function db2:onload()
    local default_desc='#DB2 database SQL statement'
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.command_call,true,1,true)
        end
    end

    add_default_sql_stmt('update','delete','insert','merge','truncate','drop')
    add_default_sql_stmt('explain','lock','analyze','grant','revoke','call','select','with')

    local  conn_help = [[
        Connect to db2 database. Usage: conn <user>/<password>@[//]<host>[:<port>][^<alt_purescale_hosts>[:<alt_purescale_ports>] ]/<database>
        Example: 1) Connect to local  db port 50000 : conn db2admin/db2pwd@localhost/sample
                 2) Connect to remote db port 60000 : conn db2admin/db2pwd@remote_host:60000/sample
                 3) Connect to remote PureScale db#1: conn db2admin/db2pwd@192.168.6.1:60000^192.168.6.2,192.168.6.3/sample
                 4) Connect to remote PureScale db#2: conn db2admin/db2pwd@192.168.6.1:60001^192.168.6.2:60002/sample
    ]]
    set_command(self,{"connect",'conn'},  conn_help,self.connect,false,2)
    set_command(self,{"declare","begin"}, default_desc,  self.command_call  ,self.check_completion,1,true)
    set_command(self,"create",   default_desc,  self.command_call      ,self.check_completion,1,true)
    set_command(self,"alter" ,   default_desc,  self.command_call      ,true,1,true)
    for _,k in ipairs{'DESCRIBE','add','AUTOCONFIGURE','BACKUP','LOAD','IMPORT','EXPORT','FORCE','QUIESCE','PRUNE',
                      'REDISTRIBUTE','RUNSTATS','UNQUIESCE','REWIND','RESET'} do
        set_command(self,k, default_desc,self.admin_cmd,true,1,true)
    end
    set_command(self,'adm', 'Run procedure ADMIN_CMD. Usage: adm <statement>',self.admin_cmd,true,2,true)
    self.C={}
    --env.event.snoop('ON_SQL_ERROR',self.handle_error,nil,1)
end

function db2:onunload()
    env.set_title("")
end

return db2.new()