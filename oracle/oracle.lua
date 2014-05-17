local env,java=env,java
local event,enc,cfg,init=env.event.callback,env.enc,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command

local module_list={
	"oracle/var",
	"oracle/ora",
	"oracle/dbmsoutput",
	"oracle/sqlplus",
	"oracle/plan",
	"oracle/desc",
	"oracle/snap"
}


local oracle=env.class(env.db_core)

function oracle:ctor()
	java.loader:addPath(env.WORK_DIR..'oracle'..env.PATH_DEL.."ojdbc6.jar")
	self.db_types:load_sql_types('oracle.jdbc.OracleTypes')
	if type(set_command)=="function" then
		set_command(self,{"connect",'conn'},  self.helper,self.connect,false,2)
		set_command(self,"login",  self.helper,self.login,false,3)
		set_command(self,{"reconnect","reconn"}, "Re-connect current database",self.reconnnect,false,2)
		set_command(self,{"select","with"},   nil,        self.query     ,true,1,true)
		set_command(self,"explain",  nil,        self.exec     ,true,1,true)
		set_command(self,"update",   nil,        self.exec      ,true,1,true)
		set_command(self,"delete",   nil,        self.exec      ,true,1,true)
		set_command(self,"insert",   nil,        self.exec      ,true,1,true)
		set_command(self,"merge" ,   nil,        self.exec      ,true,1,true)
		set_command(self,"drop"  ,   nil,        self.exec      ,false,1,true)
		set_command(self,"lock"  ,   nil,        self.exec      ,false,1,true)
		set_command(self,"analyze"  ,   nil,     self.exec      ,false,1,true)
		set_command(self,"grant"  ,   nil,       self.exec      ,false,1,true)
		set_command(self,"revoke"  ,   nil,      self.exec      ,false,1,true)
		set_command(self,{"declare","begin"},  nil,  self.exec  ,self.check_completion,1,true)
		set_command(self,"create",   nil,        self.exec      ,self.check_completion,1,true)
		set_command(self,"alter" ,   nil,        self.exec      ,self.check_completion,1,true)
		set_command(self,"/*"    ,   nil,        nil   ,self.check_completion,2)
		set_command(self,"--"    ,   nil,        nil   ,false,2)
		set_command(self,{"execute","exec","call"}  ,   nil,      self.run_proc  ,false,2)

		--set_command(self,{"describe","desc"},'Describe datbase object',self.asql_single_line,false,1)
		--set_command(self,"show",'Describe datbase object',self.asql_single_line,false,1)
		set_command(self,"commit",nil,self.commit,false,1)
		set_command(self,"rollback",nil,self.rollback,false,1)
		--set_command(self,"ora",'Run customized SQL script',self.asql_single_line,false,1)
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
		LOGIN=[[Login with saved accounts. Usage: login [<account_name>] ]]
	})[cmd]
end

function oracle:connect(conn_str)
	local props={}
	local usr,pwd,conn_desc 
	if type(conn_str)=="table" then
		usr,pwd,conn_desc=conn_str.user,
			enc.decrypt_str(conn_str.password),
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

	self.type="oracle"
	local args={driverClassName="oracle.jdbc.driver.OracleDriver",
	            user=usr,
	            password=pwd,
	            defaultRowPrefetch="100",
	            defaultLobPrefetchSize="32767",
	            useFetchSizeWithLongColumn='true',
	            ["v$session.program"]="dbcli.exe"}
	local url, isdba=conn_desc:match('^(.*) as (%w+)$')
	args.url,args.internal_logon=url,isdba
	if event then event("BEFORE_ORACLE_CONNECT",self,sql,args,result) end
	self.props.connection="jdbc:oracle:thin:@"..(url or conn_desc)
	self.super.connect(self,self.props.connection,args)	
	self.conn=java.cast(self.conn,"oracle.jdbc.OracleConnection")
	self.conn:setStatementCacheSize(self.MAX_CACHE_SIZE)
	self.conn:setImplicitCachingEnabled(true)
	local params=self:get_value([[
	   select /*INTERNAL_DBCLI_CMD*/ user,
		   (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_RDBMS_VERSION') version,
		   (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_LANGUAGE')||'_'||
	       (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_TERRITORY')||'.'||VALUE nls
       from Nls_Database_Parameters WHERE parameter='NLS_CHARACTERSET']])
	self.props.db_user,self.props.db_version,self.props.db_nls_lang=params[1],params[2],params[3]
	local args={"#VARCHAR","#VARCHAR","#VARCHAR"}
	self:internal_call([[/*INTERNAL_DBCLI_CMD*/
		begin 
		    execute immediate 'alter session set nls_date_format=''yyyy-mm-dd hh24:mi:ss''';
		    :1:=dbms_utility.get_parameter_value('db_name',:2,:3);
		end;]],args)
	self.conn_str=enc.encrypt_str(conn_str)
	--[[self.asql=java.require("com.asql.core.DBConnection")
			self.asql:setConnection(self.conn)]]
	self.props.service_name=args[3]
	local prompt=url or conn_desc
	if prompt:match("^[%w_]+$") then
		cfg.set('prompt',prompt)
	else
		cfg.set('prompt',self.props.service_name:match("^([^,]+)"))
	end	
	if event then event("AFTER_ORACLE_CONNECT",self,sql,args,result) end
	print("Database connected.")
end

function oracle:login(...)
	env.password.login(self,...)
end

function oracle:parse(sql,params)
	local p1,counter={},0
	sql=(sql..' '):gsub('&([%w_%$]+)',function(s)
			local v= params[s:upper()]
			if not v then return '&'..s end
			return v
		end)

	sql=sql:gsub(':([%w_%$]+)',function(s)
			local k=s:upper()
			local v= params[k]
			if not v then return ':'..s end
			counter=counter+1
			if type(v)=="number" then
				p1[k]={self.db_types:set('NUMBER',v)}
			elseif type(v)=="boolean" then
				p1[k]={self.db_types:set('BOOLEAN',v)}
			elseif v:sub(1,1)=="#" then
				counter=-999
			else
				p1[k]={self.db_types:set('VARCHAR',v)}
			end
			return ':'..s
			--return '?'
		end)
	
	if counter<0 then return self.super.parse(self,sql,params) end
	local prep=java.cast(self.conn:prepareCall(sql),"oracle.jdbc.OracleCallableStatement")

	for k,v in pairs(p1) do
		if v[2]=="" then v[1]="setNull" end
		pcall(prep[v[1].."AtName"],prep,k,v[2])
	end

	return prep,sql,params
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
		self:connect(enc.decrypt_str(self.conn_str))
	end
end

function oracle:run_proc(sql) 
	return self:exec('BEGIN '..sql..';END;')
end

function oracle:asql_single_line(...)
	self.asql:exec(...)
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
		local obj=other_parts:match("([%w_%$;]+)")
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
	init.load(module_list,self.C)
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