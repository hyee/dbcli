local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command

local module_list={
    "oracle/ora",
    "oracle/dbmsoutput",
    "oracle/sqlplus",
    "oracle/xplan",
    "oracle/desc",
    "oracle/snap",
    "oracle/sqlprof",
    "oracle/tracefile",
    "oracle/awrdump",
    "oracle/unwrap"
}

local oracle=env.class(env.db_core)

function oracle:ctor(isdefault)
    self.type="oracle"
    java.loader:addPath(env.WORK_DIR..'oracle'..env.PATH_DEL.."ojdbc7.jar")    
    self.db_types:load_sql_types('oracle.jdbc.OracleTypes')
    java.system:setProperty('jdbc.drivers','oracle.jdbc.driver.OracleDriver')
    local default_desc='#Oracle database SQL statement'
    self.C,self.props={},{}
end

function oracle:helper(cmd) 
    return ({
        CONNECT=[[
        Connect to Oracle database.
        Usage  : connect <user>/<password>@<tns_name>  or 
                 connect <user>/<password>@[//]<ip_address|host_name>[:<port>]/<service_name> or
                 connect <user>/<password>@[//]<ip_address|host_name>[:<port>]:<sid>
        ]],
        CONN=[[Refer to command 'connect']],
        RECONNECT=[[Re-connect the last connection, normally used when previous connection was disconnected for unknown reason.]],
        RECONN=[[Refer to command 'reconnect']],        
    })[cmd]
end

function oracle:connect(conn_str)
    --print(conn_str)
    local props={}
    local usr,pwd,conn_desc 
    if type(conn_str)=="table" then
        usr,pwd,conn_desc=conn_str.user,
            packer.unpack_str(conn_str.password),
            conn_str.url:match("@(.*)$")..
            (conn_str.internal_logon and " as "..conn_str.internal_logon or "")
        conn_str=string.format("%s/%s@%s",usr,pwd,conn_desc)        
    else
        usr,pwd,conn_desc = string.match(conn_str or "","(.+)/(.+)@(.+)")
    end

    if conn_desc == nil then
        exec_command("HELP",{"CONNECT"})
        return
    end
    
    local args={driverClassName="oracle.jdbc.driver.OracleDriver",
                user=usr,
                password=pwd,
                defaultRowPrefetch="100",
                defaultLobPrefetchSize="32767",
                useFetchSizeWithLongColumn='true',
                ['v$session.program']='SQL Developer'}
    local server,port,database=conn_desc:match('^([^:/]+)([:%d]*)([:/].+)$')
    if port=="" then conn_desc=server..':1521'..database end      
    local url, isdba=conn_desc:match('^(.*) as (%w+)$')
    args.url,args.internal_logon="jdbc:oracle:thin:@"..(url or conn_desc),isdba
    if event then event("BEFORE_ORACLE_CONNECT",self,sql,args,result) end
    env.set_title("")
    self.super.connect(self,args)    
    
    self.conn=java.cast(self.conn,"oracle.jdbc.OracleConnection")
    self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
    self.conn:setStatementCacheSize(self.MAX_CACHE_SIZE)
    self.conn:setImplicitCachingEnabled(true)
    local params=self:get_value([[
       select /*INTERNAL_DBCLI_CMD*/ user,
           (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_RDBMS_VERSION') version,
           (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_LANGUAGE')||'_'||
           (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_TERRITORY')||'.'||VALUE nls,
           userenv('sid'),sys_context('userenv','INSTANCE_NAME')
       from Nls_Database_Parameters WHERE parameter='NLS_CHARACTERSET']])
    self.props.db_user,self.props.db_version,self.props.db_nls_lang=params[1],params[2],params[3]
    local args={"#VARCHAR","#VARCHAR","#VARCHAR"}
    self:internal_call([[/*INTERNAL_DBCLI_CMD*/
        begin 
            execute immediate 'alter session set nls_date_format=''yyyy-mm-dd hh24:mi:ss''';
            execute immediate 'alter session set statistics_level=all';
            :1:=dbms_utility.get_parameter_value('db_name',:2,:3);
        end;]],args)
    self.conn_str=packer.pack_str(conn_str)
    
    self.props.service_name=args[3]
    local prompt=url or conn_desc
    if not prompt:match("^[%w_]+$") then
        prompt=self.props.service_name:match("^([^,]+)")    
    end    
    env.set_prompt(nil,prompt)
    self.session_title=('%s - Instance: %s   User: %s   SID: %s   Version: Oracle(%s)'):format(prompt:upper(),params[5],params[1],params[4],params[2])
    env.set_title(self.session_title)
    if event then event("AFTER_ORACLE_CONNECT",self,sql,args,result) end
    print("Database connected.")
end


function oracle:parse(sql,params)
    local p1,counter={},0

    if cfg.get('SQLCACHESIZE') ~= self.MAX_CACHE_SIZE then
        self.MAX_CACHE_SIZE=cfg.get('SQLCACHESIZE')
        self.conn:setStatementCacheSize(self.MAX_CACHE_SIZE)
    end
    
    sql=sql:gsub('%f[%w_%$:]:([%w_%$]+)',function(s)
        local k,s=s:upper(),':'..s 
        local v=params[k]
        if not v then return s end
        if p1[k] then return s:upper() end

        local args={}
        if type(v) =="table" then
            return s
        elseif type(v)=="number" then
            args={self.db_types:set('NUMBER',v)}
        elseif type(v)=="boolean" then
            args={self.db_types:set('BOOLEAN',v)}
        elseif v:sub(1,1)=="#" then        
            local typ=v:upper():sub(2)
            if not self.db_types[typ] then
                env.raise("Cannot find '"..typ.."' in java.sql.Types!")
            end                                
            args={'#',self.db_types[typ].id}
        else
            args={self.db_types:set('VARCHAR',v)}
        end
        
        if args[1]=='#' then 
            if counter<2 then counter=counter+2 end
        else
            if counter~=1 and counter~=3 then counter=counter+1 end
        end

        p1[k]=args

        return s:upper()
    end)
    
    if counter<0 or counter==3 then return self.super.parse(self,sql,params,':') end
    local prep=java.cast(self.conn:prepareCall(sql,1005,1007),"oracle.jdbc.OracleCallableStatement")
    --self:check_params(sql,prep,p1,params)
    for k,v in pairs(p1) do
        if v[2]=="" then v[1]="setNull" end
        if v[1]=='#' then
            prep['registerOutParameter'](prep,k,v[2])
            params[k]={'#',k,self.db_types[v[2] ].name}
        else
            prep[v[1].."AtName"](prep,k,v[2])
        end
    end

    return prep,sql,params 
end

function oracle:exec(sql,...)
    local bypass=self:is_internal_call(sql) 
    local args=type(select(1,...)=="table") and ... or {...}
    sql=event("BEFORE_ORACLE_EXEC",{self,sql,args}) [2]
    local result=self.super.exec(self,sql,args)
    if not bypass then event("AFTER_ORACLE_EXEC",self,sql,args,result) end
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

function oracle:internal_call(sql,args)
    self.internal_exec=true
    local result=self.super.exec(self,sql,args)
    self.internal_exec=false    
    return result
end

function oracle:is_internal_call(sql)
    if self.internal_exec then return true end
    return sql and sql:find("/%*INTERNAL_DBCLI_CMD%*/",1,true) and true or false 
end


function oracle:run_proc(sql) 
    return self:exec('BEGIN '..sql..';END;')
end

function oracle:asql_single_line(...)
    self.asql:exec(...)
end

function oracle:check_obj(obj_name)
    local args={target=obj_name,owner='#VARCHAR',object_type='#VARCHAR',object_name='#VARCHAR',object_subname='#VARCHAR',object_id='#INTEGER'}
    self:internal_call([[
    DECLARE
        SCHEM         VARCHAR2(30);
        part1         VARCHAR2(30);
        part2         VARCHAR2(30);
        part2_temp    VARCHAR2(30);
        dblink        VARCHAR2(30);
        part1_type    PLS_INTEGER;
        object_number PLS_INTEGER;
        obj_type      VARCHAR2(30);
        TYPE t IS TABLE OF VARCHAR2(30);
        t1 t := t('TABLE','PL/SQL','SEQUENCE','TRIGGER','JAVA_SOURCE','JAVA_RESOURCE','JAVA_CLASS','TYPE','JAVA_SHARED_DATA','INDEX');
    BEGIN
        FOR i IN 0 .. 9 LOOP
            BEGIN
                sys.dbms_utility.name_resolve(NAME          => :target,
                                              CONTEXT       => i,
                                              SCHEMA        => SCHEM,
                                              part1         => part1,
                                              part2         => part2,
                                              dblink        => dblink,
                                              part1_type    => part1_type,
                                              object_number => object_number);
                SELECT /*+no_expand*/ 
                       MIN(OBJECT_TYPE)    keep(dense_rank first order by s_flag),
                       MIN(OWNER)          keep(dense_rank first order by s_flag),
                       MIN(OBJECT_NAME)    keep(dense_rank first order by s_flag),
                       MIN(SUBOBJECT_NAME) keep(dense_rank first order by s_flag)
                INTO  obj_type,SCHEM,part1,part2_temp
                FROM (
                    SELECT a.*,case when upper(:target) like upper('%'||OBJECT_NAME||NVL2(SUBOBJECT_NAME,'.'||SUBOBJECT_NAME||'%','')) then 0 else 1 end s_flag
                    FROM   ALL_OBJECTS a
                    WHERE  OWNER=SCHEM
                    AND    OBJECT_NAME=part1);

                IF part2 is null THEN 
                    part2 := part2_temp;
                END IF;         
                EXIT;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;
        :owner          := SCHEM;
        :object_type    := obj_type;
        :object_name    := part1;
        :object_subname := part2;
        :object_id      := object_number;
    END;]],args)

    if not args.owner or args.owner=="" then
        return nil
    end    

    return args
end

function oracle:check_date(string,fmt)
    fmt=fmt or "YYMMDDHH24MI"    
    local args={string and string~="" and string or " ",fmt,'#INTEGER'}
    self:internal_call([[
        DECLARE
           d DATE;
        BEGIN
            d:=to_date(:1,:2);
            :3 := 1;
        EXCEPTION WHEN OTHERS THEN
            :3 := 0;    
        END;]],args)
    env.checkerr(args[3]==1,'Invalid date format("%s"), expected as "%s"!',string,fmt)    
end


function oracle.check_completion(cmd,other_parts)
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

local ignore_errors={
    ['ORA-00028']='Connection is lost, please login again.',
    ['socket']='Connection is lost, please login again.',
    ['SQLRecoverableException']='Connection is lost, please login again.'
}

function oracle:handle_error(info)
    local ora_code,msg=info.error:match('ORA%-(%d+):%s*([^\n\r]+)')
    if ora_code and tonumber(ora_code)>=20001 and tonumber(ora_code)<20999 then
        info.sql=nil
        info.error=msg
        return info
    end
    
    for k,v in pairs(ignore_errors) do
        if info.error:lower():find(k:lower(),1,true) then
            info.sql=nil
            info.error=v=='default' and info.error or v
            env.set_title("")
            return info
        end
    end
    
    return info
end

function oracle:onload()
    local function add_default_sql_stmt(...)
        for i=1,select('#',...) do
            set_command(self,select(i,...), default_desc,self.exec,true,1,true)
        end
    end

    add_default_sql_stmt('update','delete','insert','merge','truncate','drop')
    add_default_sql_stmt('explain','lock','analyze','grant','revoke')   
    set_command(self,{"connect",'conn'},  self.helper,self.connect,false,2)
    set_command(self,{"reconnect","reconn"}, "Re-connect current database",self.reconnnect,false,2)
    set_command(self,{"select","with"},   default_desc,        self.query     ,true,1,true)
    set_command(self,{"execute","exec","call"},default_desc,self.run_proc,false,2)
    set_command(self,{"declare","begin"},  default_desc,  self.exec  ,self.check_completion,1,true)
    set_command(self,"create",   default_desc,        self.exec      ,self.check_completion,1,true)
    set_command(self,"alter" ,   default_desc,        self.exec      ,self.check_completion,1,true)
    self.C={}
    init.load_modules(module_list,self.C)
    env.event.snoop('ON_SQL_ERROR',self.handle_error,self,1)  
end

function oracle:onunload()
    env.set_title("")
    init.unload(module_list,self.C)
    self.C=nil
end

return oracle.new()