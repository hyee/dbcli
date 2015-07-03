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
    "oracle/unwrap",
    "oracle/sys"
}

local oracle=env.class(env.db_core)

function oracle:ctor(isdefault)
    self.type="oracle"
    java.loader:addPath(env.WORK_DIR..'oracle'..env.PATH_DEL.."ojdbc7.jar")    
    self.db_types:load_sql_types('oracle.jdbc.OracleTypes')
    local default_desc='#Oracle database SQL statement'
    local header = "set feed off sqlbl on define off;\n";
    header = header.."ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';\n"
    header = header.."ALTER SESSION SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SSXFF';\n"
    header = header.."ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SSXFF TZH';\n"
    self.sql_export_header=header
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
    local args,usr,pwd,conn_desc,url,isdba
    local sqlplustr
    if type(conn_str)=="table" then --from 'login' command
        args=conn_str
        usr,pwd,url,isdba=conn_str.user,packer.unpack_str(conn_str.password),conn_str.url,conn_str.internal_logon
        args.password=pwd
    else
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)/(.*)@(.+)")
        if conn_desc == nil then return exec_command("HELP",{"CONNECT"}) end
        url, isdba=conn_desc:match('^(.*) as (%w+)$')
        sqlplustr,url=conn_str,url or conn_desc
        local server,port,database=url:match('^([^:/]+)(:?%d*)[:/](.+)$')
        if port=="" then url=server..':1521/'..database end
    end

    args=args or {user=usr,password=pwd,url="jdbc:oracle:thin:@"..url,internal_logon=isdba}
    
    self:merge_props(
        {driverClassName="oracle.jdbc.driver.OracleDriver",
         defaultRowPrefetch="100",
         defaultLobPrefetchSize="32767",
         useFetchSizeWithLongColumn='true',
         ['v$session.program']='SQL Developer'
        },args)
    
    self:load_config(url,args)
    if args.jdbc_alias or not sqlplustr then
        local pwd=args.password
        if not pwd:find('^[%w_%$#]+$') and not pwd:find('^".*"$') then pwd='"'..pwd..'"' end
        sqlplustr=string.format("%s/%s@%s%s",args.user,pwd,args.url:match("@(.*)$"),
                                            args.internal_logon and " as "..args.internal_logon or "")
    end
    local prompt=(args.jdbc_alias or url):match('([^:/@]+)$')
    self.conn_str=packer.pack_str(sqlplustr)
    
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
                sys_context('userenv','language'),
                userenv('sid'),
                sys_context('userenv','instance_name'),
                sys_context('userenv','isdba'),
                sys_context('userenv','db_name')||nullif('.'||sys_context('userenv','db_domain'),'.')
       from dual]])

    self.props={db_user=params[1],db_version=params[2],db_nls_lang=params[3],service_name=params[7],isdba=params[6]=='TRUE' and true or false}

    self:internal_call([[/*INTERNAL_DBCLI_CMD*/
        begin 
            execute immediate 'alter session set nls_date_format=''yyyy-mm-dd hh24:mi:ss''';
            execute immediate 'alter session set statistics_level=all';
        end;]],{})
        
    prompt=(prompt or self.props.service_name):match("^([^,%.&]+)") 
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
    local prep=java.cast(self.conn:prepareCall(sql,1003,1007),"oracle.jdbc.OracleCallableStatement")
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
            schem         VARCHAR2(30);
            part1         VARCHAR2(30);
            part2         VARCHAR2(30);
            part2_temp    VARCHAR2(30);
            dblink        VARCHAR2(30);
            part1_type    PLS_INTEGER;
            object_number PLS_INTEGER;
            flag          BOOLEAN := TRUE;
            obj_type      VARCHAR2(30);
            objs          VARCHAR2(2000) := 'dba_objects';
            target        VARCHAR2(100) := :target;
        BEGIN
            <<CHECKER>>
            FOR i IN 0 .. 9 LOOP
                BEGIN
                    sys.dbms_utility.name_resolve(NAME          => target,
                                                  CONTEXT       => i,
                                                  SCHEMA        => schem,
                                                  part1         => part1,
                                                  part2         => part2,
                                                  dblink        => dblink,
                                                  part1_type    => part1_type,
                                                  object_number => object_number);
                    EXIT;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;
            END LOOP;

            IF schem IS NULL AND flag AND USER != sys_context('USERENV', 'CURRENT_SCHEMA') THEN
                flag   := FALSE;
                target := sys_context('USERENV', 'CURRENT_SCHEMA') || '.' || target;
                GOTO CHECKER;
            END IF;

            BEGIN
                EXECUTE IMMEDIATE 'select 1 from dba_objects where rownum<1';
            EXCEPTION
                WHEN OTHERS THEN
                    objs := 'all_objects';
            END;

            target := REPLACE(upper(target),' ');

            IF schem IS NULL AND objs != 'all_objects' THEN
                flag  := FALSE;
                schem := regexp_substr(target, '[^\.]+', 1, 1);
                part1 := regexp_substr(target, '[^\.]+', 1, 2);
                objs  := 'dba_objects a WHERE owner IN(''PUBLIC'',sys_context(''USERENV'', ''CURRENT_SCHEMA''),''' ||schem || ''') AND object_name IN(''' || schem || ''',''' || part1 || '''))';
            ELSE
                flag  := TRUE;
                objs  := objs || ' a WHERE OWNER in(''PUBLIC'',''' || schem || ''') AND OBJECT_NAME=''' || part1 || ''')';
            END IF;

            objs:='SELECT /*+no_expand*/ 
                   MIN(OBJECT_TYPE)    keep(dense_rank first order by s_flag),
                   MIN(OWNER)          keep(dense_rank first order by s_flag),
                   MIN(OBJECT_NAME)    keep(dense_rank first order by s_flag),
                   MIN(SUBOBJECT_NAME) keep(dense_rank first order by s_flag),
                   MIN(OBJECT_ID)      keep(dense_rank first order by s_flag)
            FROM (
                SELECT a.*,
                       case when owner=''' || schem || ''' then 0 else 100 end +
                       case when ''' || target || q'[' like upper('%'||OBJECT_NAME||nullif('.'||SUBOBJECT_NAME||'%','.%')) then 0 else 10 end +
                       case substr(object_type,1,3) when 'TAB' then 1 when 'CLU' then 2 else 3 end s_flag
                FROM   ]' || objs;       

            --dbms_output.put_line(objs);
            EXECUTE IMMEDIATE objs
                INTO obj_type, schem, part1, part2_temp,object_number;

            IF part2 IS NULL THEN
                IF part2_temp IS NULL AND NOT flag THEN
                    part2_temp := regexp_substr(target, '[^\.]+', 1, CASE WHEN part1=regexp_substr(target, '[^\.]+', 1, 1) THEN 2 ELSE 3 END);
                END IF;
                part2 := part2_temp;
            END IF;

            :owner          := schem;
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

function oracle:check_access(obj_name)
    local obj=self:check_obj(obj_name)
    if not obj then return false end
    obj.count='#NUMBER'
    self:internal_call([[
        DECLARE
            x   PLS_INTEGER := 0;
            e   VARCHAR2(500);
            obj VARCHAR2(30) := :owner||'.'||:object_name;
        BEGIN
            IF instr(obj,'PUBLIC.')=1 THEN 
                obj := :object_name;
            END IF;
            BEGIN
                EXECUTE IMMEDIATE 'select count(1) from ' || obj || ' where rownum<1';
                x := 1;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            IF x = 0 THEN
                BEGIN
                    EXECUTE IMMEDIATE 'begin ' || obj || '."_test_access"; end;';
                    x := 1;
                EXCEPTION
                    WHEN OTHERS THEN
                        e := SQLERRM;
                        IF INSTR(e,'PLS-00225')>0 OR INSTR(e,'PLS-00302')>0 THEN
                            x := 1;
                        END IF;
                END;
            END IF;
            :count := x;
        END;
    ]],obj)

    return obj.count==1 and true or false;
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
    if obj and not objs[obj:upper()] and not objs[cmd] then
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
    ['SQLRecoverableException']='Connection is lost, please login again.',
    ['ORA-01013']='default',
    ['connection abort']='default'
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
            if v~='default' then
                info.error=v
                env.set_title("")
            else
                info.error=info.error:match('^([^\n\r]+)')
            end
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

    add_default_sql_stmt('update','delete','insert','merge','truncate','drop','flashback')
    add_default_sql_stmt('explain','lock','analyze','grant','revoke','purge')   
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