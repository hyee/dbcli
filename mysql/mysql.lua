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
    "snap",
    "sql",
    "list",
    "ps",
    "ti",
    "chart",
    "ssh",
    "dict",
    "mysqluc"
}

function mysql:ctor(isdefault)
    self.type="mysql"
    self.C,self.props={},{}
    self.C,self.props={},{}
    self.JDBC_ADDRESS='https://mvnrepository.com/artifact/mysql/mysql-connector-java'
end

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
            for k,v in conn_desc:gmatch("([^=%?&]+)%s*=%s*([^&]+)") do
                args[k]=v
            end
            conn_desc=conn_desc:gsub("%?.*","")
        end
        usr,pwd,url,args.url=args.user,args.password,conn_desc,"jdbc:mysql://"..conn_desc
    end
    
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')

    self:merge_props(
        {driverClassName="com.mysql.cj.jdbc.Driver",
         retrieveMessagesFromServerOnGetMessage='true',
         allowPublicKeyRetrieval=true,
         rewriteBatchedStatements='true',
         useCachedCursor=self.MAX_CACHE_SIZE,
         useUnicode='true',
         useServerPrepStmts='true',
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
    self.super.connect(self,args)
    --self.conn=java.cast(self.conn,"com.mysql.jdbc.JDBC4MySQLConnection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local info=self:get_value([[select database(),version(),CONNECTION_ID(),user(),@@hostname,@@sql_mode,@@port,@@character_set_client]])
    table.clear(self.props)
    local props=self.props
    if info then
        props.db_version,props.sub_version=info[2]:match('^([%d%.]+%d)[%W%.]+([%w%.]*)')
        props.server=info[5]
        props.db_user=info[4]:match("([^@]+)")
        props.db_conn_id=tostring(info[3])
        props.database=info[1] or ""
        props.sql_mode=info[6]
        props.charset=info[8]
        args.database=info[1] or ""
        args.hostname=url:match("^[^/%:]+")
        args.port=info[7]
        if props.sub_version:lower():find('tidb') then
            props.tidb,props.branch=true,'tidb'
            props.sub_version=info[2]:match(props.sub_version..'.-([%d%.]+%d)')
        elseif props.sub_version:lower():find('maria') then
            props.maria,props.branch=true,'maria'
            props.sub_version=nil
        elseif props.sub_version:find('^%a') then
            props.branch,props[props.sub_version:lower()]=props.sub_version:lower(),true
            props.sub_version=info[2]:match(props.sub_version..'.-([%d%.]+%d)')
        end

        env.set_title(('MySQL v%s(%s)   CID: %s'):format(
                props.db_version,
                (props.branch or '')..(props.branch and props.sub_version and ' v' or '')..(props.sub_version or ''),
                props.db_conn_id))
        if  tonumber(self.props.db_version:match("^%d+%.%d"))<5.5 then
            env.warn("You are connecting to a lower-vesion MySQL sever, some features may not support.")
        end
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
    local result=self.super.exec(self,sql,...)
    if is_not_prep and not bypass then 
        event("AFTER_MYSQL_EXEC",self,sql,args,result)
        self.print_feed(sql,result)
    end
    return result
end

function mysql:command_call(sql,...)
    local bypass=self:is_internal_call(sql)
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_MYSQL_EXEC",{self,sql,args}) [2]
    env.checkhelp(#env.parse_args(2,sql)>1)
    local result,verticals=self.super.exec(self,sql,{args})
    if not bypass then event("BEFORE_MYSQL_EXEC",self,sql,args,result) end
    self:print_result(result,sql)
end

function mysql:onload()
    local default_desc={"#MYSQL database SQL command",self.C.help.help_offline}
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.command_call,true,1,true)
        end
    end

    --[[
        select group_concat(concat('''',name,'''') order by name ) 
        from(
            select distinct coalesce(nullif(substring(name,1,instr(name," ")-1),''),name) as name 
            from help_topic where help_category_id in(10,27,40,28,21,8,29)) o
        where name not in('SET','DO','DUAL','JOIN','UNION','HELP','SHOW','USE','EXPLAIN','DESCRIBE','DESC','CONSTRAINT','CREATE')
        order by 1
    --]]
    env.set.rename_command('ENV')
    add_default_sql_stmt('SET','DO','ALTER','ANALYZE','BINLOG','CACHE','CALL','CHANGE','CHECK','CHECKSUM','DEALLOCATE','DELETE','DROP','EXECUTE','FLUSH','GRANT','HANDLER','INSERT','ISOLATION','KILL','LOAD','LOCK','OPTIMIZE','PREPARE','PURGE')
    add_default_sql_stmt('RENAME','REPAIR','REPLACE','RESET','REVOKE','SAVEPOINT','WITH','SELECT','START','STOP','TRUNCATE','UPDATE','XA',"SIGNAL","RESIGNAL",{"DESC","EXPLAIN","DESCRBE"})

    local  conn_help = [[
        Connect to mysql database. Usage: @@NAME <user>{:|/}<password>@<host>[:<port>][/<database>][?<properties>]
                                       or @@NAME <user>{:|/}<password>@[host1][:port1][,[host2][:port2]...][/database][?properties]
                                       or @@NAME <user>{:|/}<password>@address=(key1=value)[(key2=value)...][,address=(key3=value)[(key4=value)...][/database][?properties]

        Refer to "MySQL Connector/J Developer Guide" chapter 5.1 "Setting Configuration Propertie" for the available properties  
        Example:  @@NAME root/@localhost      --if not specify the port, then it is 3306
                  @@NAME root/root@localhost:3310
                  @@NAME root/root@localhost:3310/test?useCompression=false
                  @@NAME root:root@address=(protocol=tcp)(host=primaryhost)(port=3306),address=(protocol=tcp)(host=secondaryhost1)(port=3310)(user=test2)/test
    ]]
    set_command(self,{"connect",'conn'},  conn_help,self.connect,false,2)
    set_command(self,"create",   default_desc, self.command_call,self.check_completion,1,true)
    env.rename_command("HOST",{"SYSTEM","\\!","!"})
    env.rename_command("TEE",{"WRITE"})
    env.rename_command("SPOOL",{"TEE","\\t","SPOOL"})
    env.rename_command("PRINT",{"PRINTVAR","PR"})
    env.rename_command("PROMPT",{"PRINT","ECHO","\\p"})
    env.rename_command("HELP",{"HELP","\\h"})
    env.event.snoop('ON_SQL_ERROR',self.handle_error,self,1)
    set_command(nil,{"delimiter","\\d"},"Set statement delimiter. Usage: @@NAME {<text>|default|back}",
         function(sep) if sep then env.set.doset("SQLTERMINATOR",';,'..sep..',\\g') end end,false,2)

    set_command(nil,{"PROMPT","\\R"},"Change your mysql prompt. Usage: @@NAME {<text>|default|back}",
        function(sep) env.set.doset("PROMPT",sep) end,false,2)
end

local ignore_errors={

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

function mysql:set_session(name,value)
    self:assert_connect()
    return self:exec(table.concat({"SET",name,value}," "))
end

function mysql:set(item)
    if not self:is_connect() then return end
    local cmd="SET "..table.concat(item," ")
    item[1]=true
    self:exec(cmd)
end

function mysql:onunload()
    env.set_title("")
end

function mysql:finalize()
    env.set.change_default("NULL","NULL")
    env.set.change_default("SQLTERMINATOR",";,$$,\\g")
end

return mysql.new()