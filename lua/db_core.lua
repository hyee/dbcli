local java,env,table,math,loader,pcall,os=java,env,table,math,loader,pcall,os
local cfg,grid,bit,string=env.set,env.grid,env.bit,env.string
local read=reader
local event=env.event and env.event.callback or nil
local db_core=env.class()
local db_Types={}

db_core.NOT_ASSIGNED='__NO_ASSIGNMENT__'
function db_Types:set(typeName,value,conn)
    local typ=self[typeName]
    if value==nil or value==db_core.NOT_ASSIGNED then
        return 'setNull',typ.id
    else
        return typ.setter,typ.handler and typ.handler(value,'set',conn) or value
    end
end

function db_Types:getTyeName(typeID)
    return self[typeID] and self[typeID].name
end

--return column value according to the specific resulset and column index
function db_Types:get(position,typeName,res,conn)
    --local value=res:getObject(position)
    --if value==nil then return nil end
    local getter=self[typeName].getter

    local rtn,value=pcall(res[getter],res,position)
    env.checkerr(rtn,value)
   
    if value == nil or res:wasNull() then return nil end
    if not self[typeName].handler then return value end
    return self[typeName].handler(value,'get',conn,res)
end

local number_types={
        INT      = 1,
        MEDIUMINT= 1,
        BIGINT   = 1,
        TINYINT  = 1,
        SMALLINT = 1,
        DECIMAL  = 1,
        DOUBLE   = 1,
        FLOAT    = 1,
        INTEGER  = 1,
        NUMERIC  = 1,
        NUMBER   = 1
    }
--
function db_Types:load_sql_types(className)
    local typ=java.require(className)
    local m2={
        [1]={getter="getBoolean",setter="setBoolean"},
        [2]={getter="getString",setter="setDouble",
            handler=function(result,action,conn)
                if action=='get' then
                    local num=tonumber(result)
                    if num and not tostring(num):find("[eE]") then
                        return num
                    end
                end
                return result
            end},
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
             handler=function(result,action,conn,res)
                if action=="get" then
                    local succ,len=pcall(result.length,result)
                    if not succ then return nil end
                    local str=result:getSubString(1,len)
                    result:free()
                    return str
                end
                return result
            end},

        [5]={getter='getBlob',setter='setBytesForBlob', --setBytes
             handler=function(result,action,conn)
                if action=="get" then
                    local succ,len=pcall(result.length,result)
                    if not succ then return nil end
                    local str=result:getBytes(1,math.min(255,len))
                    result:free()
                    str=string.rep('%2X',#str):format(str:byte(1,#str)):gsub(' ','0')
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
            local m=m1[k] or (number_types[k] and m2[2]) or {getter="getString",setter="setString"}
            self[k]={id=v,name=k,getter=m.getter,setter=m.setter,handler=m.handler}
            self[v]=self[k]
        end
    end
end

local ResultSet=env.class()

function ResultSet:getHeads(rs,limit)
    if self[rs] then return self[rs] end
    loader:setCurrentResultSet(rs)
    local maxsiz=cfg.get("COLSIZE")
    local meta=rs:getMetaData()
    local len=meta:getColumnCount()
    local colinfo={}
    local titles={}
    for i=1,len,1 do
        local cname=meta:getColumnLabel(i)
        colinfo[i]={
            column_name=limit and cname:sub(1,maxsiz) or cname,
            data_typeName=meta:getColumnTypeName(i),
            data_type=meta:getColumnType(i),
            data_size=meta:getColumnDisplaySize(i),
            data_precision=meta:getPrecision(i),
            data_scale=meta:getScale(i),
            is_number=number_types[meta:getColumnTypeName(i):match("^%w+")]
        }
        titles[i]=colinfo[i].column_name
        colinfo[cname:upper()]=i
    end

    colinfo.__titles,titles.colinfo,self[rs]=titles,colinfo,colinfo
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
    if not self[rs] then return self:getHeads(rs).__titles end
   
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
    local clock=os.timer()
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

function ResultSet:rows(rs,count,limit,null_value)
    if not rs.isClosed or rs:isClosed() then return end
    count=tonumber(count) or -1
    local titles=self:getHeads(rs,limit)
    local head=titles.__titles
    local rows={}
    local cols=#head
    local dtype=titles[1].data_typeName
    local is_lob=cols==1 and (dtype:find("[BC]LOB") or dtype:find("XML"))
    null_value=null_value or ""
    if count~=0 then
        rows=loader:fetchResult(rs,count)
        local maxsiz=cfg.get("COLSIZE")
        for i=1,#rows do
            for j=1,cols do
                if rows[i][j]~=nil then
                    if is_lob and type(rows[i][j])=="string" and #rows[i][j]>255 then
                        print('Result written to '..env.write_cache(dtype:lower()..'_'..i..'.txt',rows[i][j]))
                    end
                    if limit and type(rows[i][j])=="string" then rows[i][j]=rows[i][j]:sub(1,maxsiz) end
                    if head.colinfo[j].data_typeName=="DATE" or head.colinfo[j].data_typeName=="TIMESTAMP" then
                        rows[i][j]=rows[i][j]:gsub('%.0+$',''):gsub('%s0+:0+:0+$','')
                    elseif head.colinfo[j].data_typeName=="BLOB" then
                        rows[i][j]=rows[i][j]:sub(1,255)
                    elseif head.colinfo[j].is_number and type(rows[i][j])~="number" then
                        local int=tonumber(rows[i][j])
                        rows[i][j]=tostring(int)==rows[i][j] and int or rows[i][j]
                    end
                else
                    rows[i][j]=null_value
                end
            end
        end
    end
    table.insert(rows,1,head)
    return rows
end

function ResultSet:print(res,conn,prefix)
    local result,hdl={},nil
    if not res.isClosed or res:isClosed() then return end
    local cols=self:getHeads(res,limit)
    if #cols==1 then
        if cfg.get("pipequery")=="on" then
            res:setFetchSize(2)
            loader:AsyncPrintResult(res,env.space,300)
            return
        end
    end
    res:setFetchSize(cfg.get("FETCHSIZE"))
    local maxrows,pivot=cfg.get("printsize"),cfg.get("pivot")
    if pivot~=0 then maxrows=math.abs(pivot) end
    local result=self:rows(res,maxrows,true,cfg.get("null"))
    if not result then return end
    if pivot==0 then 
        hdl=grid.new()
        for idx,row in ipairs(result) do 
            hdl:add(row)
        end
    end
    grid.print(hdl or result,nil,nil,nil,nil,prefix,(cfg.get("feed")=="on" and '\n'..(#result-1).." rows returned." or "").."\n")
end

function ResultSet:print_old(res,conn)
    local result,hdl={},nil
    if res:isClosed() then return end
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
    db_core.print_feed("SELECT",rows-1)
    print("")
end


db_core.db_types   = db_Types
db_core.feed_list={
    UPDATE  ="%d rows updated",
    INSERT  ="%d rows inserted",
    DELETE  ="%d rows deleted",
    SELECT  ="\n%d rows returned",
    WITH    ="\n%d rows returned",
    SHOW    ="\n%d rows returned",
    MERGE   ="%d rows merged",
    ALTER   ="%s altered",
    DROP    ="%s dropped",
    CREATE  ="%s created",
    COMMIT  ="Committed",
    ROLLBACK="Rollbacked",
    GRANT   ="Granted",
    REVOKE  ="Revoked",
    TRUNCATE="Truncated",
    SET     ="Variable set",
    USE     ="Database changed"
}

db_core.readonly_list={
    SELECT=true,
    WITH=true,
    FETCH=true,
    DECLARE=true,
    BEGIN=true,
    ALTER={SESSION=true},
    EXECUTE=true,
    CALL=true,
    EXEC=true,
    DO=true,
    START=true,
    HELP=true,
    USE=true,
    DESCRIBE=true,
    DESC=true,
    EXPLAIN=true,
    SHOW=true,
    SET=true
}

local excluded_keywords={
    OR=1,
    REPLACE=1,
    NONEDITIONABLE=1,
    EDITIONABLE=1,
    NO=1,
    FORCE=1,
    EDITIONING=1
}

function db_core.get_command_type(sql)
    local list={}
    for word in sql:gsub("%s*/%*.-%*/%s*",' '):gmatch("[^%s%(%)]+") do
        local w=word:upper()
        if not excluded_keywords[w] then
            list[#list+1]=(#list < 3 and w or word):gsub('["`]','')
            if #list > 3 then break end
        end
    end
    for i=#list+1,3 do list[i]='' end
    return table.unpack(list)
end

function db_core.print_feed(sql,result)
    if cfg.get("feed")~="on" or not sql then return end
    local secs=''
    if cfg.get("PROMPT")=='TIMING' and db_core.__start_clock then
        secs=' (' ..math.round(os.timer()-db_core.__start_clock,3)..' secs)'
    end
    local cmd,obj=db_core.get_command_type(sql)
    local feed=db_core.feed_list[cmd] 
    if feed then
        feed=feed..secs..'.'
        if feed:find('%d',1,true) then
            if type(result)=="number" then print(feed:format(result)) end
            return
        else
            return print(feed:format(obj:initcap()))
        end
    end
    if type(result)=="number" and result>0 then return print(result.." rows impacted.") end
    return print('Statement completed.')
end

function db_core:ctor()
    self.resultset  = ResultSet.new()
    self.db_types:load_sql_types('java.sql.Types')
    self.__stmts = {}
    self.type="unknown"
    env.set_command(self,"commit",nil,self.commit,false,1)
    env.set_command(self,"rollback",nil,self.rollback,false,1)
end

function db_core:login(account,list)
    if list.account_type and list.account_type~='database' then return end
    if not list.account_type and not list.url:lower():match("^jdbc") then return end
    self.__instance:connect(list)
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

function db_core:call_sql_method(event_name,sql,method,...)
    if cfg.get("READONLY")=="on" then
        local root_cmd,sub_cmd=self.get_command_type(sql)
        local enabled=self.readonly_list[root_cmd]
        if not enabled then
            enabled=type(self.readonly_list[cfg.get("platform")])=="table" and self.readonly_list[cfg.get("platform")][root_cmd]
        end

        if sub_cmd then
            if type(enabled)=="table" then enabled=enabled[sub_cmd] end
            sub_cmd=" "..sub_cmd
        else
            sub_cmd=""
        end

        if enabled ~=true then
            env.raise('Command "'..root_cmd..sub_cmd..'" is disallowed in read-only mode!')
        end
    end

    local res,obj=pcall(method,...)
    if res==false then
        local info,internal={db=self,sql=sql,error=tostring(obj):gsub('%s+$','')}
        info.error=info.error:gsub('.*Exception:?%s*','')
        event(event_name,info)
        if info and info.error and info.error~="" then
            if not self:is_internal_call(sql) and info.sql and env.ROOT_CMD~=self.get_command_type(sql) then
                if cfg.get("SQLERRLINE")=="off" then
                    print('SQL: '..info.sql:gsub("\n","\n     "))
                else
                    local lineno=0
                    local fmt='\n%5d|  '
                    print(('\n'..info.sql):gsub("\n",function() lineno=lineno+1;return fmt:format(lineno) end):sub(2))
                end
            end
            env.raise_error(info.error)
        end
        env.raise("000-00000: ")
    end
    return obj
end

function db_core:check_params(sql,prep,bind_info,params)
    local meta=self:call_sql_method('ON_SQL_PARSE_ERROR',sql,prep.getParameterMetaData,prep)
    local param_count=meta:getParameterCount()
    if param_count~=#bind_info then
        local errmsg="Parameters are unexpected, below are the detail:\nSQL:"..string.rep('-',80).."\n"..sql
        local hdl=env.grid.new()
        hdl:add({"Param Sequence","Param Name","Param Type","Param Value","Description"})
        for i=1,math.max(param_count,#bind_info) do
            local v=bind_info[i] or {}
            local res,typ=pcall(meta.getParameterTypeName,meta,i)
            typ=res and typ or v[4]
            local param_value=v[3] and params[v[3]]
            hdl:add{i,v[3],typ,type(param_value)=="table" and "OUT" or param_value,
             (#bind_info<i and "Miss Binding") or (param_count<i and "Extra Binding") or "Matched"}

        end
        errmsg=errmsg..'\n'..hdl:tostring()
        if errmsg then
            print(errmsg)
            env.raise("000-00000: ")
        end
    end
end

function db_core:parse(sql,params,prefix,prep)
    local bind_info,binds,counter={},{},0

    local temp={}
    for k,v in pairs(params) do
        temp[type(k)=="string" and k:upper() or k]={k,v}
    end

    for k,v in pairs(temp) do
        params[v[1]]=nil
        params[k]=v[2]
    end

    prefix=(prefix or ':')
    sql=sql:gsub('%f[%w_%$'..prefix..']'..prefix..'([%w_%$]+)',function(s)
            local k,s = s:upper(),prefix..s
            local v= params[k]
            if not v then return s end
            counter=counter+1;
            local args,typ={}
            if type(v) =="table" then
                table.insert(params[k][2],counter)
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
                params[k]={'#',{counter},typ}
                binds[k]={'#',{counter},typ}
                if not db_Types[typ] then
                    env.raise("Cannot find '"..typ.."' in java.sql.Types!")
                end
                args={'registerOutParameter',db_Types[typ].id}
            else
                typ='VARCHAR'
                args={db_Types:set(typ,v)}
            end
            args[#args+1],args[#args+2]=k,typ
            bind_info[#bind_info+1]=args
            return '?'
        end)

    if not prep then prep=self:call_sql_method('ON_SQL_PARSE_ERROR',sql,self.conn.prepareCall,self.conn,sql,1003,1007) end

    self:check_params(sql,prep,bind_info,params)

    if #bind_info==0 then return prep,sql,params end
    local binds={}
    local method,typeid,value,varname,typename=1,2,2,3,4
    for k,v in ipairs(bind_info) do
        prep[v[method]](prep,k,v[value])
        local inout=type(params[bind_info[varname]])=='table' and params[bind_info[varname]]=='#' and '#' or '$'
        if binds[varname] then
            table.insert(binds[varname][2],k)
        else
            binds[varname]={inout,inout=='$' and k or {k},v[typename],v[method],v[value]}
        end
    end
    env.log_debug("parse","Standard-Params:",table.dump(binds))
    return prep,sql,binds
end

local current_stmt

function db_core:abort_statement()
    --print('abort_stmt')
    if self.current_stmt then
        self.current_stmt:cancel()
        self.current_stmt=nil
    end
end

function db_core:exec_cache(sql,args,description)
    if not self.__preparedCaches or not self.__preparedCaches.__list then
        self.__preparedCaches={__list={}}
    end

    local cache=self.__preparedCaches[sql]
    local prep,org,params,_sql
    if not cache then
        org=table.clone(args)
        prep,_sql,params=self:parse(sql,org)
        cache={prep,org,params}
        self.__preparedCaches[sql]=cache
        if type(description)=="string" and description~='' then
            local prep1=self.__preparedCaches.__list[description]
            if prep1 then
                pcall(prep1[1].close,prep1[1])
                for k,v in pairs(self.__preparedCaches) do
                    if prep1==v then
                        self.__preparedCaches[k]=nil
                        break
                    end
                end
            end
            self.__preparedCaches.__list[description]=cache
        end
    else
        prep,org,params=table.unpack(cache)
        for k,n in pairs(args) do
            k=type(k)=="string" and k:upper() or k
            local o,typ=org[k]
            if params[k] and o ~= n and tostring(n):sub(1,1)~='#' and tostring(o):sub(1,1)~='#' then
                local idx=params[k][6] or params[k][2]
                local method=params[k][4]
                org[k]=n
                if method:find('setNull',1,true) and n~=nil and n~='' then
                    if type(v)=='boolean' then
                        typ='setBoolean'
                    elseif type(v)=="number" then
                        typ='setDouble'
                    elseif type(v)=='string' and #v>32000 then
                        typ='setStringForClob'
                    else
                        typ='setString'
                    end
                    method=method:gsub('setNull',typ)
                elseif not method:find('setNull',1,true) and (n==nil or n=='') then
                    typ,n=self.db_types:set("VARCHAR",nil)
                    method=typ..(method:match('AtName') or '')
                end
                prep[method](prep,idx,n)
            end
        end
    end
    args._description=description and ('('..description..')') or ''
    return self:exec(prep,args,table.clone(params),sql),cache
end

function db_core:exec(sql,args,prep_params,src_sql)
    local is_not_prep=type(sql)~="userdata"

    if is_not_prep and sql:find('/*DBCLI_EXEC_CACHE*/',1,true) then
        return self:exec_cache(sql,args,prep_params)
    end

    if is_not_prep and not self:is_internal_call(sql) then
        db_core.__start_clock=os.timer()
    end
    if #env.RUNNING_THREADS<=2 then
        collectgarbage("collect")
        java.system:gc()
        java.system:runFinalization();
    end
    local params,prep={}
    args=type(args)=="table" and args or {args}
    for k,v in pairs(args) do
        if type(k)=="string" then
            params[k:upper()]=v
        else
            params[tostring(k)]=v
        end
    end
    
    self:assert_connect()

    local autocommit=cfg.get("AUTOCOMMIT")
    if self.autocommit~=autocommit then
        if self.autocommit=="on" then self.conn:commit() end
        self.conn:setAutoCommit(autocommit=="on" and true or false)
        self.autocommit=autocommit
    end

    if is_not_prep then
        sql=event("BEFORE_DB_EXEC",{self,sql,args,params}) [2]
        if type(sql)~="string" then
            return sql
        end
        prep,sql,params=self:parse(sql,params)
        prep:setEscapeProcessing(false)
        self.__stmts[#self.__stmts+1]=prep
        prep:setFetchSize(1)
        prep:setQueryTimeout(cfg.get("SQLTIMEOUT"))
        self.current_stmt=prep
        env.log_debug("db","SQL:",sql)
        env.log_debug("db","Parameters:",params)
    else
        local desc ="PreparedStatement"..(args._description or "")
        env.log_debug("db","SQL Cache:",desc)
        prep,sql,params=sql,src_sql or desc,prep_params or {}
    end

    local is_query=self:call_sql_method('ON_SQL_ERROR',sql,loader.setStatement,loader,prep)
    self.current_stmt=nil
    local is_output,index,typename=1,2,3
    for k,v in pairs(params) do
        if type(v) == "table" and v[is_output] == "#"  then
            if type(v[index]) == "table" then
                local res
                for _,idx in ipairs(v[index]) do
                    local res1=db_Types:get(idx,v[typename],prep,self.conn) or res
                    if res1~=nil then res=res1 end
                end
                params[k]=res or db_core.NOT_ASSIGNED
            else
                params[k]=db_Types:get(v[index],v[typename],prep,self.conn) or db_core.NOT_ASSIGNED
            end
        end
    end

    local outputs={}

    for k,v in pairs(args) do
        if type(v)=="string" and v:sub(1,1)=="#" then
            args[k]=params[tostring(k):upper()]
            outputs[k]=true
        end
    end
    --close statments

    local params1=nil
    local result={is_query and prep:getResultSet() or prep:getUpdateCount()}
    local i=0;
    while true do
        params1,is_query=pcall(prep.getMoreResults,prep,2)
        if not params1 or not is_query then break end
        if result[1]==-1 then table.remove(result,1) end
        result[#result+1]=prep:getResultSet()
    end

    self:clearStatements()
    if event then event("AFTER_DB_EXEC",{self,sql,args,result,params}) end
    
    for k,v in pairs(outputs) do
        if args[k]==db_core.NOT_ASSIGNED then args[k]=nil end
    end

    return #result==1 and result[1] or result
end

function db_core:is_connect()
    if type(self.conn)~='userdata' or not self.conn.isClosed or self.conn:isClosed() then
        self.__stmts={}
        self.__preparedCaches={}
        return false
    end
    return true
end

function db_core:assert_connect()
    env.checkerr(self:is_connect(),2,"%s database is not connected!",env.set.get("database"):initcap())
end

function db_core:internal_call(sql,args,prep_params)
    self.internal_exec=true
    --local exec=self.super.exec or self.exec
    local succ,result=pcall(self.exec,self,sql,args,prep_params)
    self.internal_exec=false
    if not succ then error(result) end
    return result
end

function db_core:is_internal_call(sql)
    if self.internal_exec then return true end
    if type(sql)=="userdata" then return true end
    return sql and sql:find("INTERNAL_DBCLI_CMD",1,true) and true or false
end

function db_core:print_result(rs,sql)
    if type(rs)=='userdata' then
        return self.resultset:print(rs,self.conn)
    elseif type(rs)=='table' then
        for k,v in ipairs(rs) do
            if type(v)=='userdata' then
                self.resultset:print(v,self.conn)
            else
                print(v)
            end
        end
        return
    end
    self.print_feed(sql,rs)
end

--the connection is a table that contain the connection properties
function db_core:connect(attrs,data_source)
    env.log_debug("connect",table.dump(attrs))
    if not self.driver then
        self.driver= java.require("java.sql.DriverManager")
    end
    if attrs.driverClassName then java.require('java.lang.Class',true):forName(attrs.driverClassName) end

    env.log_debug("db","Start connecting:\n",attrs)
    attrs.account_type="database"

    local url=attrs.url
    env.checkerr(url,"'url' property is not defined !")

    self:disconnect(false)
    local props = java.new("java.util.Properties")
    for k,v in pairs(attrs) do
        props:put(k,v)
    end
    self.login_alias=env.login.generate_name(attrs.jdbc_alias or url,attrs)
    if event then event("BEFORE_DB_CONNECT",self,attrs.jdbc_alias or url,attrs) end
    local err,res

    if data_source then
        for k,v in pairs{setURL=url,
                         setUser=attrs.user,
                         setPassword=attrs.password,
                         setConnectionProperties=props} do
            if data_source[k] then data_source[k](data_source,v) end
        end
        err,res=pcall(loader.asyncCall,loader,data_source,'getConnection')
    else
        err,res=pcall(loader.asyncCall,loader,self.driver,'getConnection',url,props)
    end

    env.checkerr(err,tostring(res))

    self.conn=res
    env.checkerr(self.conn,"Unable to connect to db!")
    self.autocommit=cfg.get("AUTOCOMMIT")
    self.conn:setAutoCommit(self.autocommit=="on" and true or false)
    if event then
        event("TRIGGER_CONNECT",self,attrs.jdbc_alias or url,attrs)
        event("AFTER_DB_CONNECT",self,attrs.jdbc_alias or url,attrs)
    end
    self.__stmts = {}
    self.__preparedCaches={}
    self.properties={}
    for k in java.methods(self.conn) do
        if k=='getProperties' then
            for k,v in java.pairs(self.conn:getProperties()) do
                --print(k)
                self.properties[k]=v
            end
            env.log_debug("db","Connection properties:\n",self.properties)
        end
    end

    pcall(self.conn.setReadOnly,self.conn,cfg.get("READONLY")=="on")
    self.last_login_account=attrs
    return self.conn,attrs
end

function db_core:reconnnect()
    if self.last_login_account then
        self:connect(self.last_login_account)
    end
end

function db_core:clearStatements(is_force)
    while #self.__stmts>(is_force==true and 0 or cfg.get('SQLCACHESIZE')) do
        if not self.__stmts[1]:isClosed() then
            pcall(self.__stmts[1].close,self.__stmts[1])
        end
        table.remove(self.__stmts,1)
    end
end

--
function db_core:query(sql,args,prep_params)
    local result = self:exec(sql,args,prep_params)
    if result and type(result)~="number" then
        if type(result)=="table" then
            for _,rs in ipairs(result) do
                if type(rs) ~='number' then
                    self.resultset:print(rs,self.conn)
                end
            end
        else
            self.resultset:print(result,self.conn)
        end
    end
end

--if the result contains more than 1 columns, then return an array, otherwise return the value of the 1st column
function db_core:get_value(sql,args)
    local result = self:internal_call(sql,args)
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
    return rtn and #rtn==1 and rtn[1] or rtn
end

function db_core:grid_call(tabs,rows_limit,args,is_cache)
    local db_call=self.grid_db_call
    local rs_idx={}
    local function parse_sqls(tabs)
        local result={}
        for k,v in ipairs(tabs) do result[k]=v end
        for i=#result,1,-1 do
            local tab=result[i]
            if type(tab) == "table" then
                result[i]=parse_sqls(tab,rows_limit)
            elseif type(tab) ~= "string" then
                env.raise("Unexpected table element, string only:"..tostring(tab))
            elseif #tab>1 then
                local grid_cfg
                tab,grid_cfg=env.grid.get_config(tab)
                grid_cfg._is_result=true
                result[i]={grid_cfg=grid_cfg,sql=tab,index=i}
                rs_idx[#rs_idx+1]=result[i]
            end
        end
        return result
    end
    
    --execute all SQLs firstly, then fetch later
    local function fetch_result(tabs)
        for k=#tabs,1,-1 do
            local v=tabs[k]
            if type(v)=="table" then
                local rs=v.rs
                if not rs and not v.sql then 
                    tabs[k]=fetch_result(v)
                elseif v.sql and type(rs)~="table" and type(rs)~="userdata" then
                    table.remove(tabs,k)
                elseif type(rs)=="table" then
                    local tab={}
                    for x,y in ipairs(rs) do 
                        tab[x]=self.resultset:rows(y,rows_limit)
                        for a,b in pairs(v.grid_cfg) do tab[x][a]=b end
                    end
                    tabs[k]=tab
                else
                    tabs[k]=self.resultset:rows(rs,rows_limit)
                    for a,b in pairs(v.grid_cfg) do tabs[k][a]=b end
                end
            elseif type(v)~='string' or #v~=1 then
                table.remove(tabs,k)
            end
        end
        return tabs
    end

    local result=parse_sqls(tabs)
    if type(db_call)=='function' then
        db_call(self,rs_idx,args,is_cache)
    else
        local clock=os.timer()
        for idx,info in ipairs(rs_idx) do
            info.rs=self:internal_call(info.sql,args)
        end
        self.grid_cost=os.timer()-clock
    end

    return fetch_result(result)
end


function db_core:grid_print(sqls)
    env.checkhelp(sqls)
    local grid_cfg=table.totable(sqls)
    local tabs=self:grid_call(grid_cfg,cfg.get("printsize"),{})
    env.grid.merge(tabs,true)
end

function db_core:set_feed(value)
    self.feed=value
end

function db_core:commit()
    if self.conn then
        pcall(self.conn.commit,self.conn)
        self.print_feed("COMMIT")
    end
end

function db_core:rollback()
    if self.conn then
        pcall(self.conn.rollback,self.conn)
        self.print_feed("ROLLBACK")
    end
end

local exp=java.require("com.opencsv.ResultSetHelperService")
local csv=java.require("com.opencsv.CSVWriter")
local cparse=java.require("com.opencsv.CSVParser")
local sqlw=java.require("com.opencsv.SQLWriter")

local function set_param(name,value)
    if name=="FEED" or name=="AUTOCOMMIT" then
        return value:lower()
    elseif name=="READONLY" then
        value=value:lower()
        if env.getdb():is_connect() then
            env.getdb().conn:setReadOnly(value=="on")
        end

        if value=='on' then
            env.set_title("ReadOnly: "..value)
        else
            env.set_title("")
        end

        return value
    elseif name=="ASYNCEXP" then
        return value and value:lower()=="true" and true or false
    elseif name=="CSVSEP" then
        env.checkerr(#value==1,'CSV separator can only be one char!')
        cparse.DEFAULT_SEPARATOR=value:byte()
        return value
    end

    return tonumber(value)
end

local function print_export_result(filename,start_clock,counter)
    local str=""
    if start_clock then
        counter = (counter and (counter..' rows') or 'Data')..' exported'
        str=counter..' in '..math.round(os.timer()-start_clock,3)..' seconds. '
    end
    print(str..'Result written to file '..filename)
end

function db_core:sql2file(filename,sql,method,ext,...)
    local clock,counter,result
    if sql then
        sql=type(sql)=="string" and env.var.get_input(sql:upper()) or sql
        if type(sql)~='string' then
            env.checkerr(not sql:isClosed(),"Target ResultSet is closed!")
            result=sql
        else
            sql=env.COMMAND_SEPS.match(sql)
            result=self:internal_call(sql)
        end

        if ext and filename:lower():match("%.gz$") and not filename:lower():match("%."..ext.."%.gz$") then
            filename=filename:gsub("[gG][zZ]$",ext..".gz")
        end
    end

    if method~='CSV2SQL' then
        exp.RESULT_FETCH_SIZE=tonumber(env.ask("Please set fetch array size",'10-100000',exp.RESULT_FETCH_SIZE))
    end
    if method:find("SQL",1,true) then
        sqlw.maxLineWidth=tonumber(env.ask("Please set line width","100-32767",sqlw.maxLineWidth))
        sqlw.COLUMN_ENCLOSER=string.byte(env.ask("Please define the column name encloser","^%W$",'"'))
    end
    if method:find("CSV",1,true) then
        local quoter=string.byte(env.ask("Please define the field encloser",'^.$','"'))
        cparse.DEFAULT_QUOTE_CHARACTER=quoter
        cfg.set("CSVSEP",env.ask("Please define the field separator",'^[^'..string.char(quoter)..']$',','))
    end

    local file=io.open(filename,"w")
    env.checkerr(file,"File "..filename.." cannot be accessed because it is being used by another process!")
    file:close()
    if cfg then cfg.set("SQLTIMEOUT",86400) end
    if type(result)=="table" then
        for idx,rs in pairs(rs) do
            if type(rs)=="userdata" then
                local file=filename..tostring(idx)
                print("Start to extract result into "..file)
                clock,counter=os.timer(),loader[method](loader,rs,file,...)
                print_export_result(file,clock,counter)
            end
        end
    else
        print("Start to extract result into "..filename)
        clock,counter=os.timer(),loader[method](loader,result,filename,...)
        print_export_result(filename,clock,counter)
    end
    self:clearStatements(true)
end

db_core.source_objs={
    TRIGGER=1,
    TYPE=1,
    PACKAGE=1,
    PROCEDURE=1,
    FUNCTION=1,
    DECLARE=1,
    BEGIN=1,
    JAVA=1,
    DEFINER=1,
    EVENT=1}

function db_core.check_completion(cmd,other_parts)
    --alter package xxx compile ...
    local action,obj=db_core.get_command_type(cmd..' '..other_parts)
    local match,typ,index=env.COMMAND_SEPS.match(other_parts)
    obj=obj or ""
    if index==0 then return false,other_parts end
    if index==1 and (db_core.source_objs[cmd] or db_core.source_objs[obj:upper()]) then
        typ=type(db_core.source_obj_pattern)
        local patterns={}
        if typ=='table' then 
            patterns=db_core.source_obj_pattern
        elseif typ=="string" then
            patterns[1]=db_core.source_obj_pattern
        end
        for _,pattern in ipairs(patterns) do
            if match:match(pattern) then
                if action=="WITH" then match=match:gsub('[%s;]+$','') end
                return true,match
            end
        end
        return false,other_parts
    end
    if action=="WITH" then match=match:gsub('[%s;]+$','') end
    return true,match
end

function db_core:resolve_expsql(sql)
    self.EXCLUDES=nil
    self.REMAPS=nil
    if type(sql)~="string" then return sql end
    local args=env.parse_args(3,sql)
    if #args<2 then return sql end
    for i=2,1,-1 do
        if args[i]:lower():sub(1,2)=="-e" then
            self.EXCLUDES=args[i]:sub(3):gsub('^"(.*)"$','%1')
            table.remove(args,i)
        elseif args[i]:lower():sub(1,2)=="-r" then
            local remap=args[i]:sub(3):gsub('^"(.*)"$','%1')
            self.REMAPS={}
            while true do
                local k,v,v1=remap:match("([%w%$#%_]+)=(.*)")
                if k then
                    v1,remap=v:match("^(.-),([%w%$#%_]+=.*)")
                    table.insert(self.REMAPS,k..'='..(v1 or v):gsub(',+$',''))
                    if not v1 then break end
                else
                    break
                end
            end
            table.remove(args,i)
       end;
    end
    return table.concat(args," ")
end

function db_core:sql2sql(filename,sql)
    env.checkhelp(sql)
    sql=self:resolve_expsql(sql)
    self:sql2file(env.resolve_file(filename,{'sql','zip','gz'}),sql,'ResultSet2SQL','sql',self.sql_export_header,cfg.get("ASYNCEXP"),self.EXCLUDES,self.REMAPS)
end

function db_core:sql2csv(filename,sql)
    env.checkhelp(sql)
    sql=self:resolve_expsql(sql)
    filename=env.resolve_file(filename,{'csv','zip','gz'})
    self:sql2file(filename,sql,'ResultSet2CSV','csv',self.sql_export_header,cfg.get("ASYNCEXP"),self.EXCLUDES,self.REMAPS)
end

function db_core:csv2sql(filename,src)
    env.checkhelp(src)
    filename=env.resolve_file(filename,{'sql','zip','gz'})
    local table_name=filename:match('([^\\/]+)%.%w+$')
    local _,rs=pcall(self.exec,self,'select * from '..table_name..' where 1=2')
    if type(rs)~='userdata' then rs=nil end
    src=self:resolve_expsql(src)
    src=env.resolve_file(src)
    self:sql2file(filename,rs,'CSV2SQL','sql',src,self.sql_export_header,self.EXCLUDES,self.REMAPS)
end

function db_core:load_config(db_alias,props)
    local file=env.join_path(env.WORK_DIR,'data','jdbc_url.cfg')
    local f=io.open(file,"a")
    if f then f:close() end
    local config,err=env.loadfile(file)
    env.checkerr(config,err)
    config=config()
    config=config and config[self.type]
    if not config then return end
    props=props or {}
    local url_props
    for alias,url in pairs(config) do
        if type(url)=="table" then
            if alias:upper()==(props.jdbc_alias or db_alias:upper())  then
                url_props=url
                props.jdbc_alias=alias:upper()
            end
            config[alias]=nil
        end
    end
    self:merge_props(config,props)

    --In case of <db_alias> is defined in jdbc_url.cfg
    if url_props then props=self:merge_props(url_props,props) end

    if props.driverClassName then java.system:setProperty('jdbc.drivers',props.driverClassName) end
    return props
end

function db_core:merge_props(src,target)
    if type(src)~='table' then return target end
    for k,v in pairs(src) do
        if type(v)=="string" and (v:lower()=="nil" or v:lower()=="null") then v=nil end
        target[k]=v
    end
    return target
end

function db_core:disconnect(feed)
    if self:is_connect() then
        loader:closeWithoutWait(self.conn)
        event("ON_DB_DISCONNECTED",self)
        self.conn=nil
        if feed~=false then print("Database disconnected.") end
    end
end


function db_core:__onload()
    self.root_dir=(self.__class.__className):gsub('[^\\/]+$','')
    local jars
    if type(self.get_library)=="function" then
        libdir=self:get_library()
        if type(libdir)=="string" and os.exists(libdir) then
            jars=os.list_dir(libdir,"jar")
        elseif type(libdir)=="table" then
            jars=libdir
            for i=#jars,-1 do
                if not os.exists(jars[i]) then
                    table.remove(jars,i)
                end
            end
        end
    end

    if jars==nil or #jars==0 then
        jars=os.list_dir(self.root_dir,"jar")
    end
    for _,file in pairs(jars) do
        java.loader:addPath(type(file)=="string" and file or file.fullname)
    end

    if #jars==0 then 
        env.warn("Cannot find JDBC library in '%s', you will not be able to connect to any database.",self.root_dir)
        if self.JDBC_ADDRESS then
            env.warn("Please download and copy it from %s which should be compatible with JRE %s",self.JDBC_ADDRESS,java.system:getProperty('java.vm.specification.version'))
        end
    end

    local txt="\n   Refer to 'set expPrefetch' to define the fetch size of the statement which impacts the export performance."
    txt=txt..'\n   -e: format is "-e<column1>[,...]"'
    txt=txt..'\n   -r: format is "-r<column1=<expression>>[,...]"'
    txt=txt..'\n    Other examples:'
    txt=txt..'\n        1. sql2csv  user_objects.zip select * from user_objects;'
    txt=txt..'\n        2. sql2file user_objects.zip select * from user_objects;'
    txt=txt..'\n        3. csv2sql  user_objects.zip c:\\user_objects.csv'
    txt=txt..'\n        4. sql2csv  user_objects -e"object_id,object_type" select * from user_objects where rownum<10'
    txt=txt..'\n        5. sql2file user_objects -r"object_id=seq_obj.nextval,timestamp=sysdate" select * from user_objects where rownum<10'
    txt=txt..'\n        6. set verify off;'
    txt=txt..'\n           var x refcursor;'
    txt=txt..'\n           exec open :x for select * from user_objects where rownum<10;'
    txt=txt..'\n           sql2csv user_objects x;'
    cfg.init("PRINTSIZE",1000,set_param,"db.query","Max rows to be printed for a select statement",'1-10000')
    cfg.init("FETCHSIZE",3000,set_param,"db.query","Rows to be prefetched from the resultset, 0 means auto.",'0-32767')
    cfg.init("COLSIZE",32767,set_param,"db.query","Max column size of a result set",'5-1073741824')
    cfg.init("SQLTIMEOUT",1200,set_param,"db.core","The max wait time(in second) for a single db execution",'10-86400')
    cfg.init({"FEED","FEEDBACK"},'on',set_param,"db.core","Detemine if need to print the feedback after db execution",'on,off')
    cfg.init("AUTOCOMMIT",'off',set_param,"db.core","Detemine if auto-commit every db execution",'on,off')
    cfg.init("SQLCACHESIZE",30,set_param,"db.core","Number of cached statements in JDBC",'5-500')
    cfg.init("ASYNCEXP",true,set_param,"db.export","Detemine if use parallel process for the export(SQL2CSV and SQL2FILE)",'true,false')
    cfg.init("SQLERRLINE",'off',nil,"db.core","Also print the line number when error SQL is printed",'on,off')
    cfg.init("NULL","",nil,"db.core","Define the display value for NULL value")
    cfg.init("CSVSEP",",",set_param,"db.core","Define the default separator between CSV fields.")
    cfg.init("READONLY",'off',set_param,"db.core","When set to on, makes the database connection read-only.",'on,off')
    env.event.snoop('ON_COMMAND_ABORT',self.abort_statement,self)
    env.event.snoop('TRIGGER_LOGIN',self.login,self)
    env.set_command(self,{"reconnect","reconn"}, "Re-connect to database with the last login account.",self.reconnnect,false,2)
    env.set_command(self,{"disconnect","disc"},"Disconnect current login.",self.disconnect,false,2)
    env.set_command(self,"sql2file",'Export Query Result into SQL file. Usage: @@NAME <file_name>[.sql|gz|zip] ["-r<remap_columns>"] ["-e<exclude_columns>"] <sql|cursor>'..txt ,self.sql2sql,'__SMART_PARSE__',3)
    env.set_command(self,"sql2csv",'Export Query Result into CSV file. Usage: @@NAME <file_name>[.csv|gz|zip] ["-r<remap_columns>"] ["-e<exclude_columns>"] <sql|cursor>'..txt ,self.sql2csv,'__SMART_PARSE__',3)
    env.set_command(self,"csv2sql",'Convert CSV file into SQL file. Usage: @@NAME <sql_file>[.sql|gz|zip] ["-r<remap_columns>"] ["-e<exclude_columns>"] <csv_file>'..txt ,self.csv2sql,false,3)
    local grid_desc=[[
        Print merge grid based on inputed queries: Usage: @@NAME {"<SQL1>",<sep>,["<SQL2>"| {...} ]}
        The input parameter must start with '{' and end with '}', as a LUA or JSON table format, support nested LUA/JSON tables
        
        Elements:
            sep     : Can be 3 values:
                        '+': merge query1 and query2 as single grid
                        '-': query1 above query2
                        '|': query1 left of query2
            sql text: Must be a string which enclosed by '',"", or [[ ]']
                      The comment inside the SQL supports defining the grid style, format:
                          grid={height=<rows>,width=<columns>,topic='<grid topic>',max_rows=<records>}

        Examples:
        1.  grid {
                   'select name,value from v$sysstat where rownum<=5',
               '-','select class,count from v$waitstat where rownum<=10',
               '+','select event,total_Waits from v$system_event where rownum<20',
               '|','select stat_id,value from v$sys_time_model where rownum<20',
            }
        
        2.  Lua style:
            ==========
            grid {[[select rownum "#",event,total_Waits from v$system_event where rownum<56]'], --Query#1 left to next merged grid(query#2/query#3/query#4)
                  '|',{'select * from v$sysstat where rownum<=20',                              --Query#2 left to next merged grid(query#3/query#4))
                       '-', {'select rownum "#",name,hash from v$latch where rownum<=30',       --Query#3 above to query#4
                             '+',"select /*grid={topic='Wait State'}*/ * from v$waitstat"
                            }
                       },
                  '-','select /*grid={topic="Metrix"}*/ * from v$sysmetric where rownum<=10'    --Query#5 under merged grid(query#1-#4)
                  }

            JSON style:
            ===========
             grid ['select rownum "#",event,total_Waits from v$system_event where rownum<56', 
                   '|',['select * from v$sysstat where rownum<=20',                            
                        '-', ['select rownum "#",name,hash from v$latch where rownum<=30',     
                              '+',"select /*grid={'topic':'Wait State'}*/ * from v$waitstat"]
                       ],
                    '-','select /*grid={"topic":"Metrix"}*/ * from v$sysmetric where rownum<=10']

        Refer to 'system.snap' for more example
    ]]
    grid_desc=grid_desc:gsub("%]'%]",']]')

    env.set_command{obj=self,cmd="grid", 
                    help_func=grid_desc,
                    call_func=self.grid_print,
                    is_multiline=function(cmd,rest)
                        if not rest:find('^%s*{') and not rest:find('^%s*%[') then return true,rest end
                        local part=rest:match('^%s*(%b{})') or rest:match('^%s*(%b[])')
                        if part then
                            return true,part
                        else
                            return false,rest
                        end
                    end,
                    parameters=2,
                    is_dbcmd=true}
end

function db_core:__onunload()
    self:disconnect()
end

return db_core

