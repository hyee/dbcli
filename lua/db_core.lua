local java,env,table,math,loader=java,env,table,math,loader
local cfg,grid=env.set,env.grid
local read=reader
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
    
    local rtn,value=pcall(res[getter],res,position)
    if not rtn then
        print('Column:',position,"    Datatype:",self[typeName].name,"    ",value)
        return nil
    end
    --print(typeName,self[typeName].handler)
    if value == nil or res:wasNull() then return nil end
    if not self[typeName].handler then return value end
    return self[typeName].handler(value,'get',conn)
end

--
function db_Types:load_sql_types(className)
    
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

        [4]={getter='getClob',setter='setStringForClob',--setString
             handler=function(result,action,conn)
                if action=="get" then
                    local str=result:getSubString(1,result:length())
                    result:free()
                    return str
                end
                return result
            end},

        [5]={getter='getBlob',setter='setBytesForBlob', --setBytes
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
        --Oracle date    
        [8]={getter='getString',setter='setString',
             handler=function(result,action,conn)
                if action=="get" then
                    result= result:gsub('%.0+$',''):gsub('%s0+:0+:0+$','')
                    return result
                end
            end}
    }
    local m1={
        BOOLEAN  = m2[1],
        BIGINT   = m2[2],
        TINYINT  = m2[2],
        SMALLINT = m2[2],
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
        CURSOR   = m2[6],
        DATE     = m2[8],
        TIMESTAMP= m2[8]
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
    self.type="unknown"
    set_command(self,"commit",nil,self.commit,false,1)
    set_command(self,"rollback",nil,self.rollback,false,1)
end

function db_core:login(...)
    --print(self.connect,self.__instance.connect)
    env.login.login(self.__instance,...)
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

function db_core:check_sql_method(event_name,sql,method,...)
    local res,obj=pcall(method,...)
    if res==false then
        local info={db=self,sql=sql,error=tostring(obj):gsub('[%s\t\n\r]+$','')}
        info.error=info.error:gsub('.*Exception:?%s*','')
        event(event_name,info)    
        if info and info.error and info.error~="" then
            if info.sql and info.sql:find(env.CURRENT_ROOT_CMD,1,true)~=1 then
                print('SQL: '..info.sql:gsub("\n","\n     ")) 
            end
            env.raise_error(info.error) 
        end
        env.raise("000-00000: ")
    end 
    return obj 
end

function db_core:check_params(sql,prep,p1,params)
    local meta=self:check_sql_method('ON_SQL_PARSE_ERROR',sql,prep.getParameterMetaData,prep)
    local param_count=meta:getParameterCount()
    if param_count~=#p1 then
        local errmsg="Parameters are unexpected, below are the detail:\nSQL:"..string.rep('-',80).."\n"..sql
        local hdl=env.grid.new()
        hdl:add({"Param Sequence","Param Name","Param Type","Param Value","Description"})
        for i=1,math.max(param_count,#p1) do
            local v=p1[i] or {}
            local res,typ=pcall(meta.getParameterTypeName,meta) 
            typ=res and typ or v[4]
            local param_value=v[3] and params[v[3]]
            hdl:add{i,v[3],typ,type(param_value)=="table" and "OUT" or param_value,
             (#p1<i and "Miss Binding") or (param_count<i and "Extra Binding") or "Matched"}

        end
        errmsg=errmsg..'\n'..hdl:tostring()
        if errmsg then
            print(errmsg)
            env.raise("000-00000: ")
        end
    end
end    

function db_core:parse(sql,params,prefix,prep)
    local p1,counter={},0    
    prefix=(prefix or ':')
    sql=sql:gsub('%f[%w_%$'..prefix..']'..prefix..'([%w_%$]+)',function(s)            
            local k,s = s:upper(),prefix..s
            local v= params[k]
            if not v then return s end
            counter=counter+1;
            local args,typ={}
            if type(v) =="table" then
                table.insert(v[2],counter)
                typ=v[3]
                args={'registerOutParameter',db_Types[v[3]].id}
            elseif type(v)=="number" then
                typ='NUMBER'
                args={db_Types:set(typ,v)}
            elseif type(v)=="boolean" then
                typ='BOOLEAN'
                args={db_Types:set(typ,v)}
            elseif v:sub(1,1)=="#" then
                typ=v:upper():sub(2)
                params[k]={'#',{counter},typ,v}
                if not db_Types[typ] then
                    env.raise("Cannot find '"..typ.."' in java.sql.Types!")
                end
                args={'registerOutParameter',db_Types[typ].id}
            else
                typ='VARCHAR'
                args={db_Types:set(typ,v)}
            end
            args[#args+1],args[#args+2]=k,typ            
            p1[#p1+1]=args
            return '?'
        end)
    local res
    if not prep then prep=self:check_sql_method('ON_SQL_PARSE_ERROR',sql,self.conn.prepareCall,self.conn,sql,1003,1007) end

    self:check_params(sql,prep,p1,params)

    local meta=prep:getParameterMetaData() 

    local param_count=meta:getParameterCount()  
    if param_count==0 then return prep,sql,params end
    local checkerr=pcall(meta.getParameterMode,meta,1)     

    if not checkerr then
        for k,v in ipairs(p1) do
            prep[v[1]](prep,k,v[2])        
        end
    else
        for i=1,param_count do
            local mode=meta:getParameterMode(counter)
            local v,param_value=p1[i],params[p1[i][3]]
            if mode<=2 then
                prep[db_Types[p1[i][4]].setter](prep,i,type(param_value)=="table" and param_value[4] or param_value)                
            end

            --output parameter
            if mode>=2 then
                if type(param_value)~='table' then
                    params[p1[i][3]]={'#',{counter},typename,param_value}
                else
                    table.insert(params[p1[i][3]][2],counter)
                end                               
                prep['registerOutParameter'](prep,i,db_Types[typename].id)               
            end
        end
    end
    return prep,sql,params
end

local current_stmt

function db_core:abort_statement()
    --print('abort_stmt')
    if self.current_stmt then
        self.current_stmt:cancel()
        self.current_stmt=nil
    end
end

function db_core:exec(sql,args)
    collectgarbage("collect")
    java.system:gc()
    java.system:runFinalization ();
    local params={}
    args=type(args)=="table" and args or {args}
    local prep;
    env.checkerr(type(args) == "table", "Expected parameter as a table for SQL: \n"..sql)
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

    sql=event("BEFORE_DB_EXEC",{self,sql,args,params}) [2]

    if type(sql)~="string" then
        return sql
    end
    
    prep,sql,params=self:parse(sql,params)        
    self.__stmts[#self.__stmts+1]=prep
    prep:setQueryTimeout(cfg.get("SQLTIMEOUT"))
    self.current_stmt=prep
    --reader:setRunning(true)
    --loader:setStatement(prep)
    local is_query=self:check_sql_method('ON_SQL_ERROR',sql,loader.setStatement,loader,prep)
    self.current_stmt=nil
    --is_query=prep:execute()    
    for k,v in pairs(params) do
        if type(v) == "table" and v[1] == "#"  then
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
    
    params=nil
    local result={is_query and prep:getResultSet() or prep:getUpdateCount()}

    while true do
        params,is_query=pcall(prep.getMoreResults,prep,2) 
        if not params or not is_query then break end
        result[#result+1]=prep:getResultSet()
    end

    self:clearStatements()
    if event then event("AFTER_DB_EXEC",{self,sql,args,result}) end
    return #result==1 and result[1] or result
end

function db_core:is_connect()
    if type(self.conn)~='userdata' or not self.conn.isClosed or self.conn:isClosed() then
        return false
    end
    return true
end

function db_core:is_internal_call(sql)
    if self.internal_exec then return true end
    return sql and sql:find("INTERNAL_DBCLI_CMD",1,true) and true or false 
end

function db_core:print_result(rs)
    if type(rs)=='userdata' then
        self.resultset:print(rs,self.conn)
    elseif type(rs)=='table' then
        for k,v in ipairs(rs) do
            if type(v)=='userdata' then
                self.resultset:print(v,self.conn)
            else
                print(v)
            end
        end
    elseif v==-1 and cfg.get("feed")=="on" then
        print('Statement Completed.')
    elseif type(v)=="number" and cfg.get("feed")=="on" then
        print(v..' Rows Impacted.')
    end
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
    if event then event("BEFORE_DB_CONNECT",self,attrs.jdbc_alias or url,attrs) end
    local err,res=pcall(self.driver.getConnection,self.driver,url,props)
    env.checkerr(err,tostring(res):gsub(".*Exception.%s*",""))
    self.conn=res
    env.checkerr(self.conn,"Unable to connect to db!")
    local autocommit=cfg.get("AUTOCOMMIT")
    self.autocommit=autocommit
    self.conn:setAutoCommit(autocommit=="on" and true or false)
    if event then event("AFTER_DB_CONNECT",self,attrs.jdbc_alias or url,attrs) end
    self.__stmts = {}
    return self.conn
end

function db_core:reconnnect()
    if self.conn_str then
        self:connect(packer.unpack_str(self.conn_str))
    end
end

function db_core:clearStatements()
    while #self.__stmts>cfg.get('SQLCACHESIZE') do
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
        if cfg.get('feed')=='on' then print('Committed.') end
    end
end

function db_core:rollback()
    if self.conn then
        pcall(self.conn.rollback,self.conn)
        if cfg.get('feed')=='on' then print('Rollbacked.') end
    end
end

local function set_param(name,value)
    if name=="FEED" or name=="AUTOCOMMIT" then
        return value:lower()
    end
    return tonumber(value)
end

local function print_export_result(filename,start_clock,counter)
    if start_clock then
        counter = (counter and (counter..' rows') or 'Data')..' exported'
        print(counter..' in '..math.round(os.clock()-start_clock,3)..' seconds.')
    end
    print('Result written to file '..filename)
end

function db_core:sql2file(filename,sql,method)
    sql=sql:gsub(env.END_MARKS[1]..'$',''):gsub(env.END_MARKS[2]..'$','')
    local clock,counter,result
    if type(sql)~='string' then 
        result=sql
    else  
        result=self:exec(sql)
    end

    if type(result)=="userdata" then
        clock,counter=os.clock(),loader[method](loader,result,filename,self.sql_export_header)
        print_export_result(filename,clock,counter)
    elseif type(result)=="table" then
        for idx,rs in pairs(rs) do
            if type(rs)=="userdata" then
                clock,counter=os.clock(),loader[method](loader,rs,filename..tostring(idx),header)
                print_export_result(filename..tostring(idx),clock,counter)
            end
        end
    end
end

function db_core:sql2sql(filename,sql)
    env.checkerr(sql,'Usage: sql2file <file_name> <SQL>')
    self:sql2file(env.resolve_file(filename,{'sql','zip','gz'}),sql,'ResultSet2SQL')
end

function db_core:sql2csv(filename,sql)
    env.checkerr(sql,'Usage: sql2csv <file_name> <SQL>')
    self:sql2file(env.resolve_file(filename,{'csv','zip','gz'}),sql,'ResultSet2CSV')
end

function db_core:csv2sql(target,src)
    env.checkerr(src,'Usage: csv2sql <sql_file> <csv_file>')
    target=env.resolve_file(target,{'sql','zip','gz'})
    local table_name=target:match('([^\\/]+)%.%w+$')
    local _,rs=pcall(self.exec,self,'select * from '..table_name..' where 1=2')
    if type(rs)~='userdata' then rs=nil end
    src=env.resolve_file(src)
    local clock,counter=os.clock(),loader:CSV2SQL(src,target,self.sql_export_header,rs)
    print_export_result(target,clock,counter)
end

function db_core:load_config(db_alias,props)
    local file=env.WORK_DIR..'data'..env.PATH_DEL..'jdbc_url.cfg'
    local f=io.open(file,"a")
    if f then f:close() end
    local config,err=env.loadfile(file)
    env.checkerr(config,err)
    config=config()
    config=config and config[self.type]
    if not config then return end
    props=props or {}
    for alias,url in pairs(config) do
        if alias:upper()==(props.jdbc_alias or db_alias:upper())  then
            props=self:merge_props(url,props)
            if props.driverClassName then java.system:setProperty('jdbc.drivers',props.driverClassName) end
            props.jdbc_alias=alias:upper()
            return props
        end
    end
    if props.driverClassName then java.system:setProperty('jdbc.drivers',props.driverClassName) end
    return nil
end

function db_core:merge_props(src,target)
    if type(src)~='table' then return target end
    for k,v in pairs(src) do
        if type(v)=="string" and (v:lower()=="nil" or v:lower()=="null") then v=nil end
        target[k]=v 
    end
    return target
end

function db_core:__onload()
    local help_login=[[
        Login with saved accounts. Usage: login [ -d | -a |<number|account_name>] 
            login                     : list all saved a/c
            login -d <num|name|alias> : delete matched a/c
            login <num|name|alias>    : login a/c
            login -a <alias> <id|name>: set alias to an existing account]]
    cfg.init("PRINTSIZE",1000,set_param,"db.query","Max rows to be printed for a select statement",'1-10000')
    cfg.init("COLSIZE",32767,set_param,"db.query","Max column size of a result set",'5-1073741824')
    cfg.init("SQLTIMEOUT",600,set_param,"db.core","The max wait time(in second) for a single db execution",'10-86400')
    cfg.init("FEED",'on',set_param,"db.core","Detemine if need to print the feedback after db execution",'on,off')
    cfg.init("AUTOCOMMIT",'off',set_param,"db.core","Detemine if auto-commit every db execution",'on,off')
    cfg.init("SQLCACHESIZE",30,set_param,"db.core","Number of cached statements in JDBC",'5-500')
    env.event.snoop('ON_COMMAND_ABORT',self.abort_statement,self)
    env.set_command(self,"login",help_login,self.login,false,3)
    env.set_command(self,"sql2file","Export Query Result into SQL file. Usage: sql2file <file_name>[.sql|gz|zip] <sql|cursor>" ,self.sql2sql,'__SMART_PARSE__',3)
    env.set_command(self,"sql2csv","Export Query Result into CSV file. Usage: sql2csv <file_name>[.csv|gz|zip] <sql|cursor>" ,self.sql2csv,'__SMART_PARSE__',3)
    env.set_command(self,"csv2sql","Convert CSV file into SQL file. Usage: csv2sql <sql_file>[.sql|gz|zip] <csv_file>" ,self.csv2sql,false,3)
end

function db_core:__onunload()
    if self:is_connect() then 
        pcall(self.conn.close,self.conn)
        print("Database disconnected.") 
    end
end

return db_core

