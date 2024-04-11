local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command
local mysql=env.class(env.db_core)
mysql.module_list={
    "help",
    "findobj",
    "mysql_exe",
    "usedb",
    "show",
    "info",
    "snap",
    "sql",
    "list",
    "ps",
    "tidb",
    "chart",
    "ssh",
    "dict",
    "autotrace",
    "mysqluc"
}

function mysql:ctor(isdefault)
    self.type="mysql"
    self.C,self.props={},{}
    self.JDBC_ADDRESS='https://mvnrepository.com/artifact/mysql/mysql-connector-java'
end
local native_cmds={}
function mysql:connect(conn_str)
    local args
    local usr,pwd,conn_desc,url
    if type(conn_str)=="table" then
        args=conn_str
        usr,pwd,url=conn_str.user,packer.unpack_str(conn_str.password),conn_str.url:match("//(.*)$")
        args.password=pwd
        conn_str=string.format("%s/%s@%s",usr,pwd,url)
    else
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)[/:](.*)@(.+)")
        if conn_desc == nil then return exec_command("HELP",{"CONNECT"}) end
        args={user=usr,password=pwd}
        if conn_desc:match("%?.*=.*") then
            local use_ssl=0
            for k,v in conn_desc:gmatch("([^=%?&]+)%s*=%s*([^&]+)") do
                if k:lower()=='ssl_key' or k=='trustCertificateKeyStoreUrl' then
                    local typ,ssl=os.exists(v)
                    env.checkerr(typ=='file','Cannot find SSL TrustStore file: '..v)
                    if ssl:find(':') and ssl:sub(1,1)~='/' then ssl='/'..ssl end
                    args['trustCertificateKeyStoreUrl']='file://'..ssl:gsub('\\','/')
                    args['verifyServerCertificate']='true'
                    args['useSSL']='true'
                    args['sslMode']='PREFERRED'
                    use_ssl=use_ssl+1
                elseif k:lower()=='ssl_pwd' or  k:lower()=='ssl_password' or k=='trustCertificateKeyStorePassword' then
                    env.checkerr(#v>=6,"Incorrect SSL TrustStore passowrd, it's length should not be less than 6 chars.")
                    args['trustCertificateKeyStorePassword']=v
                    use_ssl=use_ssl+2
                else    
                    args[k]=v
                end
            end
            conn_desc=conn_desc:gsub("%?.*","")
        end
        usr,pwd,url,args.url=args.user,args.password,conn_desc,"jdbc:mysql://"..conn_desc
    end
    
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')

    self:merge_props(--https://docs.pingcap.com/tidb/stable/java-app-best-practices
        {driverClassName="com.mysql.cj.jdbc.Driver",
         allowPublicKeyRetrieval='true',
         rewriteBatchedStatements='true',
         useCachedCursor=self.MAX_CACHE_SIZE,
         useCursorFetch='true',
         useUnicode='true',
         useServerPrepStmts='true',
         cachePrepStmts='true',
         characterEncoding='utf8',
         connectionCollation='utf8mb4_unicode_ci',
         useCompression='true',
         callableStmtCacheSize=10,
         enableEscapeProcessing='false',
         allowMultiQueries="true",
         useSSL='false',
         serverTimezone='UTC',
         zeroDateTimeBehavior='convertToNull'
        },args)
    if event then event("BEFORE_mysql_CONNECT",self,sql,args,result) end
    env.set_title("")
    for k,v in pairs(args) do args[k]=tostring(v) end
    local data_source=java.new('com.mysql.cj.jdbc.MysqlDataSource')
    self.super.connect(self,args)
    --self.conn=java.cast(self.conn,"com.mysql.jdbc.JDBC4MySQLConnection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local info=self:get_value([[select database(),
                                       version(),
                                       CONNECTION_ID(),
                                       user(),
                                       @@hostname,
                                       @@global.sql_mode,
                                       @@port,
                                       @@character_set_client,
                                       COLLATION(USER())]])
    table.clear(self.props)
    local props=self.props
    props.privs={}
    if info then
        --[[
        for _,n in ipairs(native_cmds) do
            local c=self:get_value('select count(1) from mysql.help_topic where name like :1',{n..'%'})
            if c==0 then print(n) end
        end
        --]]
        local sql="set group_concat_max_len=4194304,sql_mode='"..info[6]..",ANSI'"
        props.db_version,props.sub_version=info[2]:match('^([%d%.]+%d)[^%w%.]*([%w%.]*)')
        props.db_server=info[5]
        props.db_user=info[4]:match("([^@]+)")
        props.db_conn_id=tostring(info[3])
        props.database=info[1] or ""
        props.sql_mode=info[6]
        props.charset=info[8]
        props.collation=info[9]
        args.database=info[1] or ""
        args.hostname=props.db_server
        args.port=info[7]
        self:check_readonly(cfg.get('READONLY'),self.conn:isReadOnly() and 'on' or 'off')
        if props.sub_version=='' then
            props.sub_version='Oracle'
        elseif props.sub_version:lower():find('tidb') then
            props.tidb,props.branch=true,'tidb'
            props.sub_version=info[2]:match(props.sub_version..'.-([%d%.]+%d)')
            sql=sql..",tidb_multi_statement_mode=ON"
        elseif props.sub_version:lower():find('maria') then
            props.maria,props.branch=true,'maria'
            props.sub_version=nil
        elseif props.sub_version:find('^%a') then
            props.branch,props[props.sub_version:lower()]=props.sub_version:lower(),true
            props.sub_version=info[2]:match(props.sub_version..'.-([%d%.]+%d)')
        end
        pcall(self.internal_call,self,sql)
        env._CACHE_PATH=env.join_path(env._CACHE_BASE,props.db_server,'')
        loader:mkdir(env._CACHE_PATH)
        env.set_title(('MySQL v%s(%s)   Server: %s   CID: %s'):format(
                props.db_version,
                (props.branch or '')..(props.branch and props.sub_version and ' v' or '')..(props.sub_version or ''),
                props.db_server,
                props.db_conn_id))
    end
    if (tonumber(self.props.db_version:match("^%d+%.%d")) or 1)<5.5 then
        env.warn("You are connecting to a lower-vesion MySQL sever, some features may not support.")
    end
    self.connection_info=args
    if event then event("AFTER_MYSQL_CONNECT",self,sql,args,result) end
    print("Database connected.")
end

function mysql:exec(sql,...)
    local bypass=self:is_internal_call(sql)
    local args,prep_params=nil,{}
    local is_not_prep=type(sql)~="userdata"
    if type(select(1,...) or "")=="table" then
        args=select(1,...)
        if type(select(2,...) or "")=="table" then prep_params=select(2,...) end
    else
        args={...}
    end
    
    if is_not_prep then sql=event("BEFORE_MYSQL_EXEC",{self,sql,args}) [2] end
    local result,verticals=self.super.exec(self,sql,...)
    if is_not_prep and not bypass then 
        event("AFTER_MYSQL_EXEC",self,sql,args,result)
        self.print_feed(sql,result)
    end
    return result,verticals
end

local cmd_no_arguments={
    SHUTDOWN=1
}
function mysql:command_call(sql,...)
    local bypass=self:is_internal_call(sql)
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_MYSQL_EXEC",{self,sql,args}) [2]
    local params=env.parse_args(2,sql)
    env.checkhelp(#params>1 or cmd_no_arguments[params[1]])
    local result,verticals=self.super.exec(self,sql,{args},nil,nil,true)
    if not bypass then 
        self.print_feed(sql,result)
        event("AFTER_MYSQL_EXEC",self,sql,args,result)
    end
end

function mysql:onload()
    self.db_types:load_sql_types('com.mysql.cj.MysqlType')
    local default_desc={"#MYSQL database SQL command",self.C.help.help_offline}
    local function add_default_sql_stmt(...)
        for _,cmd in ipairs({...}) do
            set_command(self,cmd, default_desc,self.command_call,true,1,true)
            native_cmds[#native_cmds+1]=type(cmd)=='table' and cmd[1] or cmd
        end
    end

    env.set.rename_command('ENV')
    add_default_sql_stmt({"SELECT","WITH"},'SET','DO','ALTER','ANALYZE','BINLOG','CACHE','CALL','CHANGE','CHECK','CHECKSUM','DEALLOCATE','DELETE','DROP','EXECUTE','FLUSH','GRANT','HANDLER','INSERT','ISOLATION','KILL','LOCK','OPTIMIZE','PREPARE','PURGE')
    add_default_sql_stmt('RENAME','REPAIR','REPLACE','RESET','REVOKE','SAVEPOINT','RELEASE','START','STOP','TRUNCATE','UPDATE','XA',"SIGNAL","RESIGNAL",{"DESC","EXPLAIN","DESCRIBE"})
    add_default_sql_stmt('IMPORT','LOAD','TABLE','VALUES','BEGIN','DECLARE','INSTALL','UNINSTALL','RESTART','SHUTDOWN','GET','CLONE')
    local  conn_help = [[
        Connect to mysql database. 
        Usage: 
              @@NAME <user>{:|/}<password>@<host>[:<port>][/<database>][?<properties>]
           or @@NAME <user>{:|/}<password>@<host>[:<port>][/<database>]?ssl_key=<jks_path>[&ssl_pwd=<jks_password>][&<properties>]
           or @@NAME <user>{:|/}<password>@[host1][:port1][,[host2][:port2]...][/database][?properties]
           or @@NAME <user>{:|/}<password>@address=(key1=value)[(key2=value)...][,address=(key3=value)[(key4=value)...][/database][?properties]

        Refer to "MySQL Connector/J Developer Guide" chapter 5.1 "Setting Configuration Propertie" for the available properties  
        Example:  @@NAME root/@localhost          -- if not specify the port, then it is 3306
                  @@NAME root/root@localhost:3310
                  @@NAME root/root@localhost:3310/test?useCompression=false
                  @@NAME root/root@localhost:3310/test?ssl_key=/home/hyee/trust.jks&ssl_pwd=123456
                  @@NAME root:root@address=(protocol=tcp)(host=primaryhost)(port=3306),address=(protocol=tcp)(host=secondaryhost1)(port=3310)(user=test2)/test
    ]]
    set_command(self,{"connect",'conn'},  conn_help,self.connect,false,2)
    set_command(self,"create",   default_desc, self.command_call,self.check_completion,1,true)
    env.rename_command("HOST",{"SYSTEM","\\!","!"})
    env.rename_command("TEE",{"WRITE"})
    env.rename_command("SPOOL",{"TEE","\\t","SPOOL"})
    env.rename_command("PRINT",{"PRINTVAR","PRI"})
    env.rename_command("PROMPT",{"PRINT","ECHO","\\p"})
    env.rename_command("HELP",{"HELP","\\h"})
    env.event.snoop('ON_SQL_ERROR',self.handle_error,self)
    env.event.snoop('ON_SETTING_CHANGED',self.check_readonly,self)
    set_command(nil,{"delimiter","\\d"},"Set statement delimiter. Usage: @@NAME {<text>|default|back}",
         function(sep) if sep then env.set.doset("SQLTERMINATOR",';,'..sep..',\\g') end end,false,2)

    set_command(nil,{"PROMPT","\\R"},"Change your mysql prompt. Usage: @@NAME {<text>|default|back}",
        function(sep) env.set.doset("PROMPT",sep) end,false,2)
end

function mysql:check_readonly(name,value,org_value)
    if name~='READONLY' or value==org_value or not self:is_connect() then return end
    self.conn:setReadOnly(value=='on')
end

local ignore_errors={
    ['No operations allowed after statement closed']='Connection is lost, please login again.',
    ['Software caused connection abort']='Connection is lost, please login again.'
}

function mysql:handle_error(info)
    for k,v in pairs(ignore_errors) do
        if info.error:lower():find(k:lower(),1,true) then
            info.sql=nil
            if v~='default' then
                info.error=v
            else
                info.error=info.error:match('^([^\n\r]+)')
            end
            return info
        end
    end
    local line,col=info.error:sub(1,1024):match('line (%d+) column (%d+)')
    if not line then
        line=info.error:sub(1,1024):match('at line (%d+) *[\r\n]+')
    end
    info.row,info.col=line,col or (line and 0 or nil)
    if line then
        info.error=info.error:gsub('You have an error.-syntax to use','Syntax error at',1)
    end
end

function mysql:check_datetime(datetime)
    local v=self:get_value([[select str_to_date(:1,'%y%m%d%H%i%s')]],{datetime},'')
    if v=='' then
        datetime=datetime:sub(3)
        v=self:get_value([[select str_to_date(:1,'%y%m%d%H%i%s')]],{datetime},'')
        env.checkerr(v~="","Invalid datetime format")
    end
    return datetime
end

function mysql:onunload()
    env.set_title("")
end

function mysql:finalize()
    env.set.change_default("NULL","NULL")
    env.set.change_default("AUTOCOMMIT","on")
    env.set.change_default("SQLTERMINATOR",";,$$,\\g")
end

return mysql.new()