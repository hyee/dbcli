local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command
local mysql=env.class(env.db_core)
mysql.module_list={
    "mysql_exe",
    "usedb",
    "show",
    "snap",
    "sql",
    "chart",
    "ssh",
}

function mysql:ctor(isdefault)
    self.type="mysql"
    self.C,self.props={},{}
    self.C,self.props={},{}
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
        {driverClassName="com.mysql.jdbc.Driver",
         retrieveMessagesFromServerOnGetMessage='true',
         --clientProgramName='SQL Developer',
         useCachedCursor=self.MAX_CACHE_SIZE,
         useUnicode='true',
         characterEncoding='UTF8',
         useCompression='true',
         callableStmtCacheSize=10,
         enableEscapeProcessing='false'
        },args)
    --print(table.dump(args))   
    
    if event then event("BEFORE_mysql_CONNECT",self,sql,args,result) end
    env.set_title("")

    for k,v in pairs(args) do args[k]=tostring(v) end
    self.super.connect(self,args)
    self.conn=java.cast(self.conn,"com.mysql.jdbc.JDBC4MySQLConnection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local info=self:get_value("select database(),version(),CONNECTION_ID(),user(),@@hostname,@@sql_mode,@@port")
    self.props.db_version,self.props.server=info[2]:match('^([%d%.]+)'),info[5]
    self.props.db_user=info[4]:match("([^@]+)")
    self.props.db_conn_id=tostring(info[3])
    self.props.database=info[1] or ""
    self.props.sql_mode=info[6]
    args.database=info[1] or ""
    args.hostname=url:match("^[^/%:]+")
    args.port=info[7]
    self.connection_info=args

    env.set_title(('%s - User: %s   ID: %s   Version: %s'):format(self.props.server,self.props.db_user,self.props.db_conn_id,info[2]))
    if event then event("AFTER_MYSQL_CONNECT",self,sql,args,result) end
    print("Database connected.")
end

function mysql.check_completion(cmd,other_parts)
    local p1=env.END_MARKS[2]..'[ \t]*$'
    local p2
    local objs={
        OR=1,
        VIEW=1,
        TRIGGER=1,
        TYPE=1,
        PACKAGE=1,
        PROCEDURE=1,
        FUNCTION=1,
        DECLARE=1,
        BEGIN=1,
        JAVA=1
    }

    local obj=env.parse_args(2,other_parts)[1]
    if obj and not objs[obj] and not objs[cmd] then
        p2=env.END_MARKS[1].."+%s*$"
    end
    local match = (other_parts:match(p1) and 1) or (p2 and other_parts:match(p2) and 2) or false
    --print(match,other_parts)
    if not match then
        return false,other_parts
    end
    return true,other_parts:gsub(match==1 and p1 or p2,"")
end

function mysql:exec(sql,...)
    local bypass=self:is_internal_call(sql)
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_MYSQL_EXEC",{self,sql,args}) [2]
    local result=self.super.exec(self,sql,args)
    if not bypass then 
        event("AFTER_MYSQL_EXEC",self,sql,args,result)
        self.print_feed(sql,result)
    end
    return result
end

function mysql:command_call(sql,...)
    local bypass=self:is_internal_call(sql)
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_MYSQL_EXEC",{self,sql,args}) [2]
    local result=self.super.exec(self,sql,{args})
    if not bypass then event("BEFORE_MYSQL_EXEC",self,sql,args,result) end
    self:print_result(result,sql)
end

function mysql:onload()
    local default_desc={"#MYSQL database SQL command",self.help_topic}
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.command_call,true,1,true)
        end
    end

    add_default_sql_stmt('update','delete','insert','merge','truncate','drop','BINLOG')
    add_default_sql_stmt('lock','analyze','grant','revoke','call','select','with',{"DESC","EXPLAIN","DESCRBE"})

    local  conn_help = [[
        Connect to mysql database. Usage: conn <user>{:|/}<password>@<host>[:<port>][/<database>][?<properties>]
                                       or conn <user>{:|/}<password>@[host1][:port1][,[host2][:port2]...][/database][?properties]
                                       or conn <user>{:|/}<password>@address=(key1=value)[(key2=value)...][,address=(key3=value)[(key4=value)...][/database][?properties]

        Refer to "MySQL Connector/J Developer Guide" chapter 5.1 "Setting Configuration Propertie" for the available properties  
        Example:  conn root/@localhost      --if not specify the port, then it is 3306
                  conn root/root@localhost:3310
                  conn root/root@localhost:3310/test?useCompression=false
                  conn root:root@address=(protocol=tcp)(host=primaryhost)(port=3306),address=(protocol=tcp)(host=secondaryhost1)(port=3310)(user=test2)/test
    ]]
    set_command(self,{"connect",'conn'},  conn_help,self.connect,false,2)
    set_command(self,{"reconnect","reconn"}, "Re-connect current database",self.reconnnect,false,2)
    set_command(self,"create",   default_desc,  self.command_call      ,self.check_completion,1,true)
    set_command(self,"alter" ,   default_desc,  self.command_call      ,true,1,true)
    self.C={}
    env.set.inject_cfg({"password","role","constraint","constraints"},self.set_session,self)
    env.event.snoop("ON_HELP_NOTFOUND",self.help_topic,self)
    env.event.snoop("ON_SET_NOTFOUND",self.set,self)
end

function mysql:set_session(name,value)
    env.checkerr(self:is_connect(),"Database is not connected!")
    return self:exec(table.concat({"SET",name,value}," "))
end

function mysql:help_topic(...)
    local keyword=table.concat({...}," "):upper():trim()
    local topic=self:get_value("select name,description,example from mysql.help_topic where name like :1 order by name limit 1",{keyword..(keyword:find("%$") and "" or "%")})
    env.checkerr(topic,"No such topic: "..keyword)
    topic[1]="Name: "..topic[1]
    local desc=topic[1]..":\n"..('='):rep(#topic[1]+1)..("\n"..topic[2]):gsub("\r?\n\r?","\n  ")
    if (topic[3] or ""):trim()~="" then
        desc=desc.."\nExamples:\n============"..(("\n"..topic[3]):gsub("\r?\n\r?","\n  "))
    end
    print(desc:gsub("%s+$",""))
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

return mysql.new()