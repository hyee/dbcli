local db,cfg=env.getdb(),env.set
local autoplan,autoplan_format='off','oracle'
local auto_generic=nil
local xplan={}
local config={
    root='Plan',
    child='Plans',
    indent_width=2,
    processor=function(name,value,row,node)
        
    end,
    columns={
            },
    excludes={},
    percents={},
    title='Plan Tree',
    others={}
}

function xplan.explain(fmt,sql)
    env.checkhelp(fmt)
    local options,is_oracle={},true
    if sql then
        fmt=fmt:upper()
        if fmt:upper()=='ANALYZE' or fmt=='EXEC' or fmt=='-EXEC' then
            fmt='ANALYZE'
        else
            fmt='FORMAT='..fmt:gsub('.*=','')
        end
        is_oracle=false
    elseif db.props and db.props.tidb then
        fmt=''
    else
        sql=fmt
        fmt="FORMAT=JSON"
    end
    
    env.set.set('feed','off')
    local json,file,typ
    if #sql<256 and not sql:find('\n',1,true) then 
        typ,file=env.os.exists(sql)
    end
    if file then
        env.checkerr(typ=='file','Target locate is not a file: '..file)
        local succ,data=pcall(loader.readFile,loader,file,10485760)
        env.checkerr(succ,tostring(data))
        local json1=data:match('%b{}')
        local json2=data:match('%b[]')
        if not json1 or not json2 then
            json=json1 or json2
        else
            json=#json1>#json2 and json1 or json2
        end
        json=xplan.parse_plan_tree(data) or json
        env.checkerr(json,"Cannot find valid JSON data from file "..file)
        env.checkerr(json:find(config.root,1,true) and json:find(config.root,1,true),"Invalid execution plan in JSON format.")
    else
        if tonumber(sql) then
            sql='FOR CONNECTION '..sql
        elseif sql:match('^%w+$') then
            db:check_obj('performance_schema.events_statements_summary_by_digest',nil,true)
            local rs=db:get_rows("select digest_text from performance_schema.events_statements_summary_by_digest where digest like '"..sql.."%'")
            env.checkerr(#rs>1,"No SQL find in performance_schema.events_statements_summary_by_digest: "..sql)
            sql=rs[2][1]
        end
        local c=0
        sql,_=(sql..' '):gsub("([^%?a-zA-Z0-9])%?([^%?a-zA-Z0-9])",function(prefix,suffix)
            c=c+1
            return prefix..'?'..suffix
        end)
        env.checkerr(c==0,"Explaining SQL with bind varaibles is unsupported.")
        sql='EXPLAIN '..fmt..'\n'..sql
        
        if not is_oracle then
            return db:query(sql)
        else
            local res=db:exec(sql)
            if type(res)=='table' then
                for _,row in ipairs(res) do
                    if type(row)=='userdata' then
                        res=row
                        break
                    end
                end
            end
            local rows=db.resultset:rows(res,-1)
            json=rows[2][1]
            print(json)
            return;
        end
    end
    
    env.json_plan.parse_json_plan(json,config)
end

function xplan.autoplan(name,value)
    if name=='AUTOPLANFORMAT' then
        autoplan_format=value
    elseif name=='AUTOPLAN' then 
        autoplan=value
    end
    return value
end

local tracable={SELECT=1,WITH=1,INSERT=1,UPDATE=1,DELETE=1,MERGE=1,CREATE=1}
function xplan.before_db_exec(obj)
    local db,sql,args,params,is_internal=table.unpack(obj)
    if autoplan=='off' or is_internal or not sql then return end
    local action,_=env.db_core.get_command_type(sql)
    
    if not tracable[action] then return end
    local args1,params1=table.clone(args),table.clone(params)
    local version=tonumber(db.props.db_version:match("^%d+%.%d"))
    local is_analyze=autoplan~='xplan' and (version>=8 or db.props.tidb)
    local stmt=string.format('EXPLAIN %s %s \n%s',
        is_analyze and 'ANALYZE' or '',
        (is_analyze or db.props.tidb) and '' or 
        ((autoplan_format=='oracle' or autoplan_format=='json') and 'FORMAT=JSON' or
        (autoplan_format=='table' or version<8) and 'FORMAT=TRADITIONAL') or 'FORMAT=TREE',
        sql)
    if is_analyze and autoplan=='analyze' then
        if #env.RUNNING_THREADS>2 then
            print('----------------------------------SQL Statement-------------------------------------')
            print(sql)
        end
        obj[2]=nil
    end
    
    return db:query(stmt,args1,params1)
--[[--
    if autoplan_format~='oracle' then
        return db:query(stmt,args1,params1)
    end

    local rows=db.resultset:rows(db:exec(stmt,args1,params1),-1)
    env.json_plan.parse_json_plan(rows[2][1],config)
--]]--
end

function xplan.parse_plan_tree(text)
    
end

function xplan.onload()
    local help=[[
    Explain SQL execution plan, type 'help @@NAME' for more details. Usage: @@NAME [<format>] [<Id>|<SQL Id>|<SQL Text>|<File>]

    Options:
        <format>   : TRADITIONAL / JSON / TREE
        ANALYZE    : analyze the execution plan
    Parameters:
        <id>       : connection id from `performance_schema`.`processlist`
        <SQL Text> : SELECT/DELETE/UPDATE/MERGE/etc that can produce the execution plan
        <SQL ID>   : The SQL ID from pg_stat_statements
        <File>     : The file path that is the execution plan in JSON format
    ]]
    env.set_command(nil,{"XPLAIN","XPLAN"},help,xplan.explain,'__SMART_PARSE__',3,true)
    env.set.init("AUTOPLAN","off",xplan.autoplan,"explain","Controls generating execution plan of the input SQLs",'xplan,analyze,exec,off')
    env.set.init("AUTOPLANFORMAT","tree",xplan.autoplan,"explain","Controls the output execution plan type when autoplan=on",'oracle,tree,table,json')
    env.event.snoop('BEFORE_DB_EXEC',xplan.before_db_exec)
    env.event.snoop('BEFORE_DB_CONNECT',function() auto_generic=nil;env.set.force_set("autoplan",'off') end)
end

return xplan