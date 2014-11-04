local java,env,table,math=java,env,table,math
local cfg,grid=env.set,env.grid
local event=env.event and env.event.callback or nil

local db_Types={}
function db_Types:set(typeName,value,conn)
	local typ=self[typeName]
	if value==nil then
		return 'setNull',typ.id
	else
		return typ.setter,typ.handler and typ.handler(value,'set',conn) or value
	end
end

--return column value according to the specific resulset and column index
function db_Types:get(position,typeName,res,conn)
	--local value=res:getObject(position)
	--if value==nil then return nil end	
	local getter=self[typeName].getter
	if getter=="getDouble" and not res:getObject(position) then
		return nil
	end
	local res,value=pcall(res[getter],res,position)
	if not res then
		print('Column:'..position,"Datatype:"..self[typeName].name,value)
		return nil
	end
	if value == nil then return value end
	if not self[typeName].handler then return value end
	return self[typeName].handler(value,'get',conn)
end

--
function db_Types:load_sql_types(className)
	local maxsiz=cfg.get("COLSIZE")
	local typ=java.require(className)
	local m2={
		[1]={getter="getBoolean",setter="setBoolean"},
		[2]={getter="getDouble",setter="setDouble"},
		[3]={getter="getArray",setter='setArray',
		     handler=function(result,action,conn)
				if action=="get" then
					local str="{"
					for k,v in java.ipairs(result:getArray()) do
						str=str..v..",\n "
					end
					if #str>1 then str=str:sub(1,-4) end
 					str=str.."}"
					return str
				else
					return conn:createArrayOf("VARCHAR", result);
				end
			end},

		[4]={getter='getClob',setter='setString',
		     handler=function(result,action,conn)
				if action=="get" then
					local str=result:getSubString(1,result:length())
					result:free()
					return str
				end
				return result
			end},

		[5]={getter='getBlob',setter='setBytes',
		     handler=function(result,action,conn)
				if action=="get" then
					local str=result:getBytes(1,result:length())
					str=java.require("java.lang.String").new(str)
					result:free()
					return str
				else
					return java.cast(result,'java.lang.String'):getBytes()
				end
			end},

		[6]={getter='getObject',setter='setObject',
		     handler=function(result,action,conn)
				if action=="get" then
					return java.cast(result,'java.sql.ResultSet')
				end
			end},
		[7]={getter='getCharacterStream',setter='setBytes',
		     handler=function(result,action,conn)
				if action=="get" then
					return ""
				end
			end},
	}
	local m1={
		BOOLEAN  = m2[1],
		BIGINT   = m2[2],
		DECIMAL  = m2[2],
		DOUBLE   = m2[2],
		FLOAT    = m2[2],
		INTEGER  = m2[2],
		NUMERIC  = m2[2],
		NUMBER   = m2[2],
		ARRAY    = m2[3],
		CLOB     = m2[4],
		NCLOB    = m2[4],
		BLOB     = m2[5],
		CURSOR   = m2[6] 
	}
	for k,v in java.fields(typ) do
		if type(k) == "string" and k:upper()==k then
			local m=m1[k] or {getter="getString",setter="setString"}
			self[k]={id=v,name=k,getter=m.getter,setter=m.setter,handler=m.handler}
			self[v]=self[k]
		end
	end
end

local ResultSet=env.class()

function ResultSet:getHeads(rs)
	if self[rs] then return self[rs] end
	local maxsiz=cfg.get("COLSIZE")	
	local meta=rs:getMetaData()
	local len=meta:getColumnCount()
	local colinfo={}
	for i=1,len,1 do
		local cname=meta:getColumnLabel(i)
		table.insert(colinfo,{
			column_name=cname:sub(1,maxsiz),
			data_typeName=meta:getColumnTypeName(i),
			data_type=meta:getColumnType(i),
			data_size=meta:getColumnDisplaySize(i),
			data_precision=meta:getPrecision(i),
			data_scale=meta:getScale(i)
		})
		colinfo[cname:upper()]=i
	end
	self[rs]=colinfo
	return colinfo
end

function ResultSet:get(column_id,data_type,rs,conn)
	if type(column_id) == "string" then
		local cols=self[rs] or self:getHeads(rs)
		column_id=cols[column_id:upper()]
		env.checkerr(column_id,"Unable to detect column '"..column_id.."' in db metadata!")
		data_type=cols[column_id].data_type
	end
	return db_Types:get(column_id,data_type,rs,conn)
end

--return one row for a result set, if packerounter EOF, then return nil
--The first rows is the title
function ResultSet:fetch(rs,conn)
	local cols=self[rs] 
	if not cols then
		cols = self:getHeads(rs)
		env.checkerr(cols,"No query result found!")
        local titles={}
        for k,v in ipairs(cols) do
            table.insert(titles,v.column_name)
        end
        return titles
	end

	if not rs:next() then
		self:close(rs)
		return nil
	end

	local size=#cols
	local result=table.new(size,2)
	local maxsiz=cfg.get("COLSIZE")
	for i=1,size,1 do
		local value=self:get(i,cols[i].data_type,rs,conn)
		value=type(value)=="string" and value:sub(1,maxsiz) or value
		result[i]=value or ""
	end

	return result
end

function ResultSet:close(rs)
	
	if rs then
		if not rs:isClosed() then rs:close() end
		if self[rs] then self[rs]=nil end
	end
	local clock=os.clock()
	--release the resultsets if they have been closed(every 1 min)
	if  self.__clock then
		if clock-self.__clock > 60 then
			for k,v in pairs(self) do
				if type(k)=='userdata' and k.isClosed and k:isClosed() then
					self[k]=nil
				end
			end
			self.__clock=clock
		end
	else
		self.__clock=clock
	end
end

function ResultSet:rows(rs,conn)
	local sets={}
	repeat
		local row=self:fetch(rs,conn)
		table.insert(sets,row)
	until not row
	return sets
end

function ResultSet:print(res,conn,feed)
	local result,hdl={},nil
	if res:isClosed() then
		return
	end
	local rows,maxrows,feedflag,pivot=0,cfg.get("printsize"),cfg.get("feed"),cfg.get("pivot")
	if pivot==0 then hdl=grid.new() end
	while true do
		--run statement
		local rs = self:fetch(res,conn)
        if type(rs) ~= "table" then
            if not rs then break end
            env.raise(tostring(rs))
        end
        if rows>maxrows or hdl==nil and rows>math.abs(pivot) then
        	self:close(res)
        	break
        end
        rows=rows+1
        if hdl then 
        	hdl:add(rs)
        else
			table.insert(result,rs)
		end
	end
	grid.print(hdl or result)
	print("")
	if feed ~= false and feedflag ~= "off" then print((rows-1) .. ' rows returned.\n') end
end

local db_core=env.class()
db_core.db_types   = db_Types
db_core.feed_list={
	UPDATE  ="%d rows updated",
	INSERT  ="%d rows inserted",
	DELETE  ="%d rows deleted",
	MERGE   ="%d rows merge",
	DROP    ="Object dropped",
	CREATE  ="Object created",
	COMMIT  ="Committed",
	ROLLBACK="Rollbacked",
	GRANT   ="Granted",
	REVOKE  ="Revoked",
}

function db_core:ctor()
	self.resultset  = ResultSet.new()
	self.db_types:load_sql_types('java.sql.Types')
	self.__stmts = {}
	self.MAX_CACHE_SIZE=30
	local help=[[
		Login with saved accounts. Usage: login [ -d | -r |<number|account_name>] 
		    login              : list all saved a/c
		    login -r           : reload a/c info
		    login -d <num|key> : delete matched a/c
		    login <num|key>    : login a/c]]
	env.set_command(self,"login", help,self.login,false,3)
	set_command(self,"commit",nil,self.commit,false,1)
	set_command(self,"rollback",nil,self.rollback,false,1)
end

function db_core:login(...)
	--print(self.connect,self.__instance.connect)
	env.password.login(self.__instance,...)
end

--[[
   execute sql statement. args is a map table, 
   For input parameter, 
        1) Its key - value structure is {parameter_name1 = value1, k2=v2...}
        2) The function would parse the sql to idendify the parameters with following rules:
            a) the text whose format is "&<key>", if args have matching items, then replace the text with keys's value
            b) the text whose format is ":<key>", use bind variable method, the binding datatype depends on the values' datatype
   For output parameter, then  {parameter_name1 = #<datatype_name1>, ...}, and datatype can be see for java.sql.Types
        The output parameters must be found in SQL text with :key format

   Both input or output parameter names are all case-insensitive

   returns: for the sql is a query stmt, then return the result set, otherwise return the affected rows(>=-1)	
]]

function db_core:parse(sql,params)
	local p1,counter={},0	
	sql=sql:gsub(':([%w_%$]+)',function(s)
			local v= params[s:upper()]
			if not v then return ':'..s end
			counter=counter+1;
			if type(v) =="table" then
				table.insert(v[2],counter)
				table.insert(p1,{'registerOutParameter',db_Types[v[3]].id})
				return "?"
			elseif type(v)=="number" then
				table.insert(p1,{db_Types:set('NUMBER',v)})
			elseif type(v)=="boolean" then
				table.insert(p1,{db_Types:set('BOOLEAN',v)})
			elseif v:sub(1,1)=="#" then
				local typ=v:upper():sub(2)
				params[s:upper()]={'#',{counter},typ}
				if not db_Types[typ] then
					env.raise("Cannot find '"..typ.."' in java.sql.Types!")
				end
				table.insert(p1,{'registerOutParameter',db_Types[typ].id})
			else
				table.insert(p1,{db_Types:set('VARCHAR',v)})
			end
			--return ':'..s
			return '?'
		end)
	
	local prep=self.conn:prepareCall(sql)
	
	for k,v in ipairs(p1) do
		prep[v[1]](prep,k,v[2])
	end

	return prep,sql,params
end

function db_core:exec(sql,args)
	collectgarbage("collect")
	java.system:gc()

	local params={}
	
	local prep;
	env.checkerr(args==nil or type(args) == "table", "Expected parameter as a table for SQL: \n"..sql)
	for k,v in pairs(args or {}) do
		if type(k)=="string" then
			params[k:upper()]=v
		else
			params[tostring(k)]=v
		end
	end

	if not self.conn or self.conn:isClosed() then
		self.__stmts={}
		env.raise("Database is not connected!")
	end

	local autocommit=cfg.get("AUTOCOMMIT")
	if self.autocommit~=autocommit then
		self.conn:setAutoCommit(autocommit=="on" and true or false)
		self.autocommit=autocommit
	end

	prep,sql,params=self:parse(sql,params)	

	if event then event("BEFORE_DB_EXEC",self,sql,args) end
	self.__stmts[#self.__stmts+1]=prep
	prep:setQueryTimeout(cfg.get("SQLTIMEOUT"))
	local success,is_query=pcall(prep.execute,prep)
	if success==false then
		print('SQL: '..sql:gsub("\n","\n     "))
		error(is_query)
	end

	--is_query=prep:execute()
	for k,v in pairs(params) do
		if type(v) == "table" and v[1] == "#" then
			if type(v[2]) == "table" then
				local res
				for _,key in ipairs(v[2]) do
					local res1=db_Types:get(key,v[3],prep,self.conn)
					if res1  then
						res=res1
					end
				end
				params[k]=res
			else 
				params[k]=db_Types:get(v[2],v[3],prep,self.conn)
			end
		end
	end

	if args then
		for k,v in pairs(args) do
			if type(v)=="string" and v:sub(1,1)=="#" then
				args[k]=params[tostring(k):upper()]
			end
		end
	end

	--close statments
	while #self.__stmts>self.MAX_CACHE_SIZE do
		if not self.__stmts[1]:isClosed() then
			pcall(self.__stmts[1].close,self.__stmts[1])
		end
		table.remove(self.__stmts,1)
	end

	params=nil
	local result
	if is_query then
		result=prep:getResultSet()
	else
		result=prep:getUpdateCount()
	end
	if event then event("AFTER_DB_EXEC",self,sql,args,result) end
	return result
end

function db_core:is_connect()
	if type(self.conn)~='userdata' or not self.conn.isClosed or self.conn:isClosed() then
		return false
	end
	return true
end

--the connection is a table that contain the connection properties
function db_core:connect(attrs)
	if not self.driver then
		self.driver= java.require("java.sql.DriverManager")
	end
	local url=attrs.url
	env.checkerr(url,"'url' property is not defined !")

	local conn=self.conn
	if conn and conn.isClosed and not conn:isClosed() then
		pcall(conn.close,conn)
		self.conn=nil
	end
	local props = java.new("java.util.Properties")
	for k,v in pairs(attrs) do
		props:put(k,v)
	end
	if event then event("BEFORE_DB_CONNECT",self,url,attrs) end
	local err,res=pcall(self.driver.getConnection,self.driver,url,props)
	if not err then		
		env.raise(tostring(res):gsub(".*Exception: ",""))
	end
	self.conn=res
	env.checkerr(self.conn,"Unable to connect to db!")
	local autocommit=cfg.get("AUTOCOMMIT")
	self.autocommit=autocommit
	self.conn:setAutoCommit(autocommit=="on" and true or false)
	if event then event("AFTER_DB_CONNECT",self,url,attrs) end
	self.__stmts = {}
	return self.conn
end

function db_core:clearStatements()
	while #self.__stmts>5 do
		if not self.__stmts[1]:isClosed() then
			pcall(self.__stmts[1].close,self.__stmts[1])
		end
		table.remove(self.__stmts,1)
	end
end

--
function db_core:query(sql,args)
	local result = self:exec(sql,args)
	if result and type(result)~="number" then
		self.resultset:print(result,self.conn)
	end
end

--if the result contains more than 1 columns, then return an array, otherwise return the value of the 1st column
function db_core:get_value(sql,args)
	local result = self:exec(sql,args)
	if not result or type(result)=="number" then
		return result
	end
	--bypass the titles
	self.resultset:fetch(result,self.conn)
	local rtn=self.resultset:fetch(result,self.conn)
	self.resultset:close(result)
	if type(rtn)~="table" then
		return rtn
	end
	return #rtn==1 and rtn[1] or rtn
end

function db_core:set_feed(value)
	self.feed=value
end

function db_core:commit()
	if self.conn then
		pcall(self.conn.commit,self.conn)
	end
end

function db_core:rollback()
	if self.conn then
		pcall(self.conn.rollback,self.conn)
	end
end

local function set_param(name,value)
	if name=="FEED" or name=="AUTOCOMMIT" then
		return value:lower()
	end
	return tonumber(value)
end

cfg.init("PRINTSIZE",300,set_param,"db.query","Max rows to be printed for a select statement",'1-3000')
cfg.init("COLSIZE",32767,set_param,"db.query","Max column size of a result set",'5-1073741824')
cfg.init("SQLTIMEOUT",600,set_param,"db.core","The max wait time(in second) for a single db execution",'10-86400')
cfg.init("FEED",'on',set_param,"db.core","Detemine if need to print the feedback after db execution",'on,off')
cfg.init("AUTOCOMMIT",'off',set_param,"db.core","Detemine if auto-commit every db execution",'on,off')

return db_core
