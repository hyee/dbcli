local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command

local module_list={
    "oracle/var",
    "oracle/ora",
    "oracle/dbmsoutput",
    "oracle/sqlplus",
    "oracle/xplan",
    "oracle/desc",
    "oracle/snap",
    "oracle/sqlprof",
    "oracle/tracefile",
    "oracle/awrdump"
}


local oracle=env.class(env.db_core)

function oracle:ctor(isdefault)
    self.type="oracle"
    java.loader:addPath(env.WORK_DIR..'oracle'..env.PATH_DEL.."ojdbc7.jar")    
    self.db_types:load_sql_types('oracle.jdbc.OracleTypes')
    local default_desc='#Oracle database SQL statement'
    if isdefault~=false then            
        if type(set_command)=="function" then
            set_command(self,{"connect",'conn'},  self.helper,self.connect,false,2)
            set_command(self,{"reconnect","reconn"}, "Re-connect current database",self.reconnnect,false,2)
            set_command(self,{"select","with"},   default_desc,        self.query     ,true,1,true)
            set_command(self,"explain",  default_desc,     self.exec     ,true,1,true)
            set_command(self,"update",   default_desc,     self.exec      ,true,1,true)
            set_command(self,"delete",   default_desc,     self.exec      ,true,1,true)
            set_command(self,"insert",   default_desc,     self.exec      ,true,1,true)
            set_command(self,"merge" ,   default_desc,     self.exec      ,true,1,true)
            set_command(self,"drop"  ,   default_desc,     self.exec      ,false,1,true)
            set_command(self,"lock"  ,   default_desc,     self.exec      ,false,1,true)
            set_command(self,"analyze",  default_desc,     self.exec      ,false,1,true)
            set_command(self,"grant"  ,  default_desc,     self.exec      ,false,1,true)
            set_command(self,"revoke"  , default_desc,     self.exec      ,false,1,true)
            set_command(self,{"declare","begin"},  default_desc,  self.exec  ,self.check_completion,1,true)
            set_command(self,"create",   default_desc,        self.exec      ,self.check_completion,1,true)
            set_command(self,"alter" ,   default_desc,        self.exec      ,self.check_completion,1,true)
            set_command(self,"/*"    ,   '#Comment',        nil   ,self.check_completion,2)
            set_command(self,"--"    ,   '#Comment',        nil   ,false,2)
            set_command(self,{"execute","exec","call"}  ,   default_desc,      self.run_proc  ,false,2)        
        end
        env.event.snoop('BEFORE_COMMAND',self.clearStatements,self)        
    end
    self.C,self.props={},{}
end

function oracle:helper(cmd) 
    return ({
        CONNECT=[[
        Connect to Oracle database.
        Usage  : connect <user>/<password>@<tns_name>  or 
                 connect <user>/<password>@[//]<ip_address|host_name>:<port>/<service_name> or
                 connect <user>/<password>@[//]<ip_address|host_name>:<port>:<sid>
        ]],
        CONN=[[Refer to command 'connect']],
        RECONNECT=[[Re-connect the last connection, normally used when previous connection was disconnected for unknown reason.]],
        RECONN=[[Refer to command 'reconnect']],        
    })[cmd]
end

function oracle:connect(conn_str)
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
                ["v$session.program"]="dbcli.exe"}
    local url, isdba=conn_desc:match('^(.*) as (%w+)$')
    args.url,args.internal_logon="jdbc:oracle:thin:@"..(url or conn_desc),isdba
    if event then event("BEFORE_ORACLE_CONNECT",self,sql,args,result) end

    self.super.connect(self,args)    
    
    self.conn=java.cast(self.conn,"oracle.jdbc.OracleConnection")
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
            :1:=dbms_utility.get_parameter_value('db_name',:2,:3);
        end;]],args)
    self.conn_str=packer.pack_str(conn_str)
    
    self.props.service_name=args[3]
    local prompt=url or conn_desc
    if not prompt:match("^[%w_]+$") then
        prompt=self.props.service_name:match("^([^,]+)")    
    end    
    env.set_prompt(nil,prompt)
    self.session_title=prompt:upper().." - Instance: "..params[5].."    User: "..params[1].. "    SID: "..params[4].."    Version: "..params[2]
    env.set_title(self.session_title)
    if event then event("AFTER_ORACLE_CONNECT",self,sql,args,result) end
    print("Database connected.")
end


function oracle:parse(sql,params)
    local p1,counter={},0

    sql=sql:gsub('%f[%w_%$&]&([%w%_%$]+)',function(s) return params[s:upper()] or '&'..s end)
    return self.super.parse(self,sql,params,':')
--[[
    sql=sql:gsub('%f[%w_%$:]:([%w_%$]+)',function(s)
            local k,s=s:upper(),':'..s 
            local v=params[k]
            if not v then return s end
            if p1[k] then return s end

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

            return s
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
--]]    
end

function oracle:exec(sql,...)
    local bypass=self:is_internal_call(sql) 
    local args=type(select(1,...)=="table") and ... or {...}
    if not bypass then event("BEFORE_ORACLE_EXEC",self,sql,args) end
    local result=self.super.exec(self,sql,args)
    if not bypass then event("AFTER_ORACLE_EXEC",self,sql,args,result) end
    if type(result)=="number" and cfg.get("feed")=="on" then
        local key=sql:match("(%w+)")
        if self.feed_list[key] then
            print(self.feed_list[key]:format(result)..".")
        else
            print("Statement completed .")
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


function oracle:reconnnect()
    if self.conn_str then
        self:connect(packer.unpack_str(self.conn_str))
    end
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
                SELECT /*+no_expand*/ MIN(OBJECT_TYPE),MIN(OWNER),MIN(OBJECT_NAME)
                INTO   obj_type,SCHEM,part1
                FROM   ALL_OBJECTS
                WHERE  OBJECT_ID=object_number;   
                IF obj_type IS NULL THEN 
                    part2 := NULL;
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
    local p1='\n[%s\t]*/[%s\t]*$'
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
    if cmd=="/*" then 
        p1=".*%*/[%s\t\n]*$" 
    else        
        local obj=env.parse_args(2,other_parts)[1]
        if obj and not objs[obj] and not objs[cmd] then
            p2=";+[%s\t\n]*$"
        end
    end
    local match = (other_parts:match(p1) and 1) or (p2 and other_parts:match(p2) and 2) or false
    --print(match,other_parts)
    if not match then
        return false,other_parts
    end
    return true,other_parts:gsub(match==1 and p1 or p2,"")
end

function oracle:onload()
    self.C={}
    init.load_modules(module_list,self.C)
end

function oracle:onunload()
    init.unload(module_list,self.C)
    self.C=nil
    if self.conn then 
        pcall(self.conn.close,self.conn) 
        print("Database disconnected.")
    end    
end

return oracle.new()