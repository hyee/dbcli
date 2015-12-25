local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command

local module_list={
    "mysql/snap",
    "mysql/sql",
    "mysql/chart",
    "mysql/ssh",
}

local mysql=env.class(env.db_core)

function mysql:ctor(isdefault)
    self.type="mysql"
    self.C,self.props={},{}
    local default_desc='#mysql database SQL statement'
    self.C,self.props={},{}
end

function mysql:connect(conn_str)
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
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)[/:](.*)@(.+)")
        local args={}
        if conn_desc:match("%?.*=.*") then
            for k,v in conn_desc:gmatch("([^=%?&]+)%s*=%s*([^&]+)") do
                args[k]=v
            end
            conn_desc=conn_desc:gsub("%?.*","")
        end
        self:merge_props({
            user=usr,
            password=pwd,
            url="jdbc:mysql://"..conn_desc,
        },args)
    end

    if conn_desc == nil then return exec_command("HELP",{"CONNECT"}) end

    conn_desc=conn_desc:gsub('^(/+)','')
    local server,port,alt,database=conn_desc:match('^([^:/%^]+)(:?%d*)(%^?[^/]*)/(.+)$')
    if database then
        if port=="" then port=':3306' end
        conn_desc=server..port..'/'..database
        local alt_addr,alt_port=alt:gsub('[%s%^]+',''):match('([^:]+)(:*.*)')
    else
        database=conn_desc
    end
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')

    local url, isdba=conn_desc:match('^(.*) as (%w+)$')
    url = url or conn_desc

    args=args or {user=usr,password=pwd,
                  url="jdbc:mysql://"..url,
                  server=server,
                  database=database}

    self:merge_props(
        {driverClassName="com.mysql.jdbc.Driver",
         --retrieveMessagesFromServerOnGetMessage='true',
         --clientProgramName='SQL Developer',
         useCachedCursor=self.MAX_CACHE_SIZE,
         useUnicode='true',
         characterEncoding='UTF8',
         useCompression='true',
         callableStmtCacheSize=10,
         enableEscapeProcessing='false'
        },args)

    self:load_config(url,args)
    local prompt=(args.jdbc_alias or url):match('([^:/@]+)$')
    if event then event("BEFORE_mysql_CONNECT",self,sql,args,result) end
    env.set_title("")
    print(table.dump(args))
    self.super.connect(self,args)
--[[
    self.conn=java.cast(self.conn,"com.ibm.mysql.jcc.mysqlConnection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local version=self:get_value("select SERVICE_LEVEL FROM TABLE(sysproc.env_get_inst_info())")
    self.props.db_version=version:gsub('mysql',''):match('([%d%.]+)')
    self.props.db_user=args.user:upper()
    self.props.database=database
    self.conn_str=packer.pack_str(conn_str)

    prompt=(prompt or database:upper()):match("^([^,%.&]+)")
    env.set_prompt(nil,prompt,nil,2)

    env.set_title(('%s - User: %s   Server: %s   Version: mysql(%s)'):format(database,self.props.db_user,server,self.props.db_version))
    if event then event("AFTER_mysql_CONNECT",self,sql,args,result) end
    print("Database connected.")
    ]]--
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
    sql=event("BEFORE_mysql_EXEC",{self,sql,args}) [2]
    local result=self.super.exec(self,sql,args)
    if not bypass then event("AFTER_mysql_EXEC",self,sql,args,result) end
    if type(result)=="number" and cfg.get("feed")=="on" then
        local key=sql:match("(%w+)")
        if self.feed_list[key] then
            print(self.feed_list[key]:format(result)..".")
        else
            print("Statement completed.\n")
        end
    end
    return result
end

function mysql:command_call(sql,...)
    local bypass=self:is_internal_call(sql)
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_mysql_EXEC",{self,sql,args}) [2]
    local result=self.super.exec(self,sql,{args})
    if not bypass then event("AFTER_mysql_EXEC",self,sql,args,result) end
    self:print_result(result,sql)
end

function mysql:admin_cmd(cmd)
    self:command_call('call sysproc.admin_cmd(:1)',cmd)
end

function mysql:onload()
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.command_call,true,1,true)
        end
    end

    add_default_sql_stmt('update','delete','insert','merge','truncate','drop')
    add_default_sql_stmt('explain','lock','analyze','grant','revoke','call','select','with')

    local  conn_help = [[
        Connect to mysql database. Usage: conn <user>:<password>@[//]<host>[:<port>][/<database>] [&<other parameters>]
                                       or conn <user>/<password>@[//]<host>[:<port>][/<database>] [&<other parameters>] 
        Example: 
    ]]
    set_command(self,{"connect",'conn'},  conn_help,self.connect,false,2)
    set_command(self,{"reconnect","reconn"}, "Re-connect current database",self.reconnnect,false,2)
    set_command(self,{"declare","begin"}, default_desc,  self.command_call  ,self.check_completion,1,true)
    set_command(self,"create",   default_desc,  self.command_call      ,self.check_completion,1,true)
    set_command(self,"alter" ,   default_desc,  self.command_call      ,true,1,true)
    set_command(self,'adm', 'Run procedure ADMIN_CMD. Usage: adm <statement>',self.admin_cmd,true,2,true)
    self.C={}
    init.load_modules(module_list,self.C)
end

function mysql:onunload()
    env.set_title("")
    init.unload(module_list,self.C)
    self.C=nil
end

return mysql.new()