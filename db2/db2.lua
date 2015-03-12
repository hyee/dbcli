local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command

local module_list={
    "db2/sqlstate",
    "db2/snap",
    "db2/sql",
}

local db2=env.class(env.db_core)

function db2:ctor(isdefault)
    self.type="db2"
    self.C,self.props={},{}
    java.loader:addPath(env.WORK_DIR..'db2'..env.PATH_DEL.."db2jcc4.jar")   
    java.loader:addPath(env.WORK_DIR..'db2'..env.PATH_DEL.."db2jcc_license_cu.jar") 
    java.system:setProperty('jdbc.drivers','com.ibm.db2.jcc.DB2Driver')
    --self.db_types:load_sql_types('oracle.jdbc.OracleTypes')
    local default_desc='#DB2 database SQL statement'
    self.C,self.props={},{}
end

function db2:connect(conn_str)
    java.loader:addPath(env.WORK_DIR..'db2'..env.PATH_DEL.."db2jcc.jar")
    --print(conn_str)
    local usr,pwd,conn_desc 
    if type(conn_str)=="table" then
        usr,pwd,conn_desc=conn_str.user,
            packer.unpack_str(conn_str.password),
            conn_str.url:match("//(.*)$")--..(conn_str.internal_logon and " as "..conn_str.internal_logon or "")
        conn_str=string.format("%s/%s@%s",usr,pwd,conn_desc)        
    else
        usr,pwd,conn_desc = string.match(conn_str or "","(.+)/(.+)@(.+)")
    end

    if conn_desc == nil then
        exec_command("HELP",{"CONNECT"})
        return
    end

    conn_desc=conn_desc:gsub('^(/+)','')
    local server,port,database=conn_desc:match('^([^:/]+)([:%d]*)([:/].+)$')
    if port=="" then port='50000';conn_desc=server..':'..port..database end
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE') 
    local args={driverClassName="com.ibm.db2.jcc.DB2Driver",
                user=usr,
                password=pwd,
                driverType='4',
                retrieveMessagesFromServerOnGetMessage='true',
                clientProgramName='SQL Developer',
                useCachedCursor=self.MAX_CACHE_SIZE
            }

    local url, isdba=conn_desc:match('^(.*) as (%w+)$')
    args.url,args.internal_logon="jdbc:db2://"..(url or conn_desc),isdba
    if event then event("BEFORE_DB2_CONNECT",self,sql,args,result) end
    env.set_title("")
    self.super.connect(self,args)    
    
    self.conn=java.cast(self.conn,"com.ibm.db2.jcc.DB2Connection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    local version=self:get_value("select SERVICE_LEVEL FROM TABLE(sysproc.env_get_inst_info())")
    self.props.db_version=version:gsub('DB2',''):match('([%d%.]+)')
    self.props.db_user=usr:upper()
    self.conn_str=packer.pack_str(conn_str)
    database=database:upper():sub(2)
    env.set_prompt(nil,database)
    env.set_title(('%s - User: %s   Server: %s   Version: DB2(%s)'):format(database,self.props.db_user,server,self.props.db_version))
    if event then event("AFTER_DB2_CONNECT",self,sql,args,result) end
    print("Database connected.")
end

function db2.check_completion(cmd,other_parts)
    local p1=env.END_MARKS[2]..'[%s\t]*$'
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
        p2=env.END_MARKS[1].."+[%s\t\n]*$"
    end
    local match = (other_parts:match(p1) and 1) or (p2 and other_parts:match(p2) and 2) or false
    --print(match,other_parts)
    if not match then
        return false,other_parts
    end
    return true,other_parts:gsub(match==1 and p1 or p2,"")
end

function db2:onload()
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.exec,true,1,true)
        end
    end

    add_default_sql_stmt('describe','update','delete','insert','merge','truncate','drop')
    add_default_sql_stmt('explain','lock','analyze','grant','revoke')   
    set_command(self,{"connect",'conn'},  'Connect to db2 database. Usage: conn <user>/<password>@[//]<address|host>[:<port>]/<database>',self.connect,false,2)
    set_command(self,{"reconnect","reconn"}, "Re-connect current database",self.reconnnect,false,2)
    set_command(self,{"select","with"},   default_desc,        self.query     ,true,1,true)
    set_command(self,{"execute","exec","call"},default_desc,self.exec,false,2)
    set_command(self,{"declare","begin"},  default_desc,  self.exec  ,self.check_completion,1,true)
    set_command(self,"create",   default_desc,        self.exec      ,self.check_completion,1,true)
    set_command(self,"alter" ,   default_desc,        self.exec      ,self.check_completion,1,true)
    self.C={}
    init.load_modules(module_list,self.C)
    --env.event.snoop('ON_SQL_ERROR',self.handle_error,nil,1)  
end

function db2:onunload()
    env.set_title("")
    init.unload(module_list,self.C)
    self.C=nil
end

return db2.new()