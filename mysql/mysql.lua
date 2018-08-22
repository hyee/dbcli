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
    "mysqluc"
}

function mysql:ctor(isdefault)
    self.type="mysql"
    self.C,self.props={},{}
    self.C,self.props={},{}
    self.JDBC_ADDRESS='http://dev.mysql.com/downloads/connector/j/'
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
         useServerPrepStmts='true',
         characterEncoding='UTF8',
         useCompression='true',
         callableStmtCacheSize=10,
         enableEscapeProcessing='false',
         allowMultiQueries="true",
        },args)
    
    if event then event("BEFORE_mysql_CONNECT",self,sql,args,result) end
    env.set_title("")
    for k,v in pairs(args) do args[k]=tostring(v) end
    self.super.connect(self,args)
    self.conn=java.cast(self.conn,"com.mysql.jdbc.JDBC4MySQLConnection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local info=self:get_value([[
        select database(),version(),CONNECTION_ID(),user(),@@hostname,@@sql_mode,@@port,plugin_version 
        from   INFORMATION_SCHEMA.PLUGINS
        where  plugin_name='InnoDB']])
    self.props.db_version,self.props.server=info[8]:match('^([%d%.]+)'),info[5]
    self.props.db_user=info[4]:match("([^@]+)")
    self.props.db_conn_id=tostring(info[3])
    self.props.database=info[1] or ""
    self.props.sql_mode=info[6]
    args.database=info[1] or ""
    args.hostname=url:match("^[^/%:]+")
    args.port=info[7]
    self.connection_info=args
    if not self.props.db_version or tonumber(self.props.db_version:match("^%d+"))<5 then self.props.db_version=info[2]:match('^([%d%.]+)') end
    if tonumber(self.props.db_version:match("^%d+%.%d"))<5.5 then
        env.warn("You are connecting to a lower-vesion MySQL sever, some features may not support.")
    end
    env.set_title(('%s - User: %s   CID: %s   Version: %s(InnoDB-%s)'):format(self.props.server,self.props.db_user,self.props.db_conn_id,info[2],info[8]))
    if event then event("AFTER_MYSQL_CONNECT",self,sql,args,result) end
    print("Database connected.")
end

function mysql:disconnect(...)
    self.super.disconnect(self,...)
    env.set_title("")
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
    local result=self.super.exec(self,sql,args,prep_params)
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

    --[[
        select group_concat(concat('''',name,'''') order by name ) 
        from(
            select distinct coalesce(nullif(substring(name,1,instr(name," ")-1),''),name) as name 
            from help_topic where help_category_id in(10,27,40,28,21,8,29)) o
        where name not in('SET','DO','DUAL','JOIN','UNION','HELP','SHOW','USE','EXPLAIN','DESCRIBE','DESC','CONSTRAINT','CREATE')
        order by 1
    --]]

    add_default_sql_stmt('DO','ALTER','ANALYZE','BINLOG','CACHE','CALL','CHANGE','CHECK','CHECKSUM','DEALLOCATE','DELETE','DROP','EXECUTE','FLUSH','GRANT','HANDLER','INSERT','ISOLATION','KILL','LOAD','LOCK','OPTIMIZE','PREPARE','PURGE')
    add_default_sql_stmt('RENAME','REPAIR','REPLACE','RESET','REVOKE','SAVEPOINT','SELECT','START','STOP','TRUNCATE','UPDATE','XA',"SIGNAL","RESIGNAL",{"DESC","EXPLAIN","DESCRBE"})

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
    set_command(self,"create",   default_desc,  self.command_call      ,self.check_completion,1,true)
    set_command(self,{"?","\\?"},nil,self.help_topic,false,9)

    env.set.change_default("null","NULL")
    env.event.snoop("ON_HELP_NOTFOUND",self.help_topic,self)
    env.event.snoop("ON_SET_NOTFOUND",self.set,self)
    env.event.snoop("BEFORE_EVAL",self.on_eval,self)
    env.rename_command("TEE",{"write"})
    env.rename_command("SPOOL",{"TEE","\\t","SPOOL"})
    env.rename_command("PRINT","PRINTVAR")
    env.rename_command("PROMPT",{"PRINT","ECHO","\\p"})
    env.rename_command("HELP",{"HELP","\\h"})
    set_command(nil,{"delimiter","\\d"},"Set statement delimiter. Usage: @@NAME {<text>|default|back}",
         function(sep)
            if #env.RUNNING_THREADS<=2 then
                return env.set.force_set("SQLTERMINATOR",sep)
            else
                env.set.doset("SQLTERMINATOR",sep)
            end
        end,false,2)
    self.C={}

    set_command(nil,{"PROMPT","\\R"},"Change your mysql prompt. Usage: @@NAME {<text>|default|back}",
        function(sep)
            if #env.RUNNING_THREADS<=2 then
                return env.set.force_set("PROMPT",sep)
            else
                env.set.doset("PROMPT",sep)
            end
        end,false,2)
end

function mysql:on_eval(line)
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

function mysql:set_session(name,value)
    self:assert_connect()
    return self:exec(table.concat({"SET",name,value}," "))
end

function mysql:help_topic(...)
    local keyword=table.concat({...}," "):upper():trim()
    local liker={keyword:find("%$") and keyword or (keyword.."%")}
    local desc
    env.set.set("feed","off")
    local help_table=" from mysql.help_topic as a join mysql.help_category as b using(help_category_id) "
    if keyword=="C" or keyword=="CONTENTS" then
        self:query("select help_category_id as `Category#`,b.name as `Category`,group_concat(distinct coalesce(nullif(substring(a.name,1,instr(a.name,' ')-1),''),a.name) order by a.name) as `Keywords`"..help_table.."group by help_category_id,b.name order by 2")
    elseif keyword:find("^SEARCH%s+") or keyword:find("^S%s+") then
        keyword=keyword:gsub("^[^%s+]%s+","")
        liker={keyword:find("%$") and keyword or ("%"..keyword.."%")}
        self:query("select a.name,b.name as category,a.url"..help_table.."where (upper(a.name) like :1 or upper(b.name) like :1) order by a.name",liker)
    else
        local topic=self:get_value("select 1"..help_table.."where upper(b.name)=:1 or convert(help_category_id,char)=:1",{keyword})
        if topic then
            self:query("select a.name,b.name as category,a.url"..help_table.." where upper(b.name)=:1 or convert(help_category_id,char)=:1 order by a.name",{keyword})
        else
            local topic=self:get_value("select a.name,description,example,b.name as category"..help_table.."where a.name like :1 order by a.name limit 1",liker)
            env.checkerr(topic,"No such topic: "..keyword)
            topic[1]='Name:  '..topic[4].." / "..topic[1]
            local desc='$HEADCOLOR$'..topic[1].."$NOR$ \n"..('='):rep(#topic[1])
                      ..(" \n"..topic[2]:gsub("^%s*Syntax:%s*","")):gsub("\r?\n\r?","\n  ")
            if (topic[3] or ""):trim()~="" then
                desc=desc.."\n$HEADCOLOR$Examples: $NOR$\n========= "..(("\n"..topic[3]):gsub("\r?\n\r?","\n  "))
            end
            print(ansi.convert_ansi((desc:gsub("%s+$",""))))
        end
    end
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