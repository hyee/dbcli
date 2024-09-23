local db,cfg=env.getdb(),env.set
local autoplan,autoplan_format='off','oracle'
local event=env.event.callback
local xplan={}
local parser=env.json_plan
local config={
    root='Plan',
    child='Plans',
    indent_width=2,
    processor=function(name,value,row,node)
        if not name and node then
            local removed=0
            for n,v in pairs(node) do
                if n:find(" Removed ",1,true) then
                    removed=removed+v
                end
            end
            if removed>0 then node["Rows Removed"]=removed end

            local base,schema="Index Name",node["Schema"]
            if node['Relation Name'] and schema then
                if node['Alias']==node['Relation Name'] then node['Alias']=nil end
                node['Relation Name'],node["Schema"]=schema..'.'..node['Relation Name'],nil
            end
            for _,n in ipairs{'Relation Name','Function Name','CTE Name','Subplan Name','Alias'} do
                local name=node[n]
                if name then
                    if not node[base] then
                        if n=="Relation Name" then
                            node[base]=name
                        elseif n=='Function Name' then
                            node[base]=name..'()'
                        elseif n=='CTE Name' then
                            node[base]='['..name..']'
                        elseif n=='Alias' then
                            node[base]='> '..name
                        else
                            node[base]='<'..name..'>'
                        end
                        if node['Alias']==name then node['Alias']=nil end
                        node[n]=''
                        break
                    end
                end
            end
        end
        return value
    end,
    columns={
        {"Node Type","Plan|Operation"},'|',
        {"Index Name","Object|Name"},'|',
        {"Alias","Obj|Alias"},'|',
        {"Plan Rows","Est|Rows",format='TMB1'},{"Actual Rows","Act|Rows",format='TMB1'},
        {"Rows Removed","Removed|Rows",format='TMB1'}, '|',
        {"Actual Loops","Act|Loops",format='TMB1'},'|',
        {parser.leaf,"Leaf|Time",format='usmhd1'} ,'|',
        {"Actual Startup Time","Start|Time",format='usmhd1'},{"Actual Total Time","Total|Time",format='usmhd1'},'|',
        {"Costs","Leaf|Cost",format='TMB2'},{"Startup Cost","Start|Cost",format='TMB2'},{"Total Cost","Total|Cost",format='TMB2'},'|',
    },
    leaf_time_based={"Actual Startup Time","Actual Total Time"},
    excludes={},
    percents={parser.leaf},
    title='Plan Tree',
    others={}
}

function xplan.explain(...)
    local args={}
    for i=1,select('#',...) do
        local v=select(i,...)
        if v then
            args[#args+1]=v=='.' and '' or v
        end
    end
    local sql=args[#args]
    local fmt=#args>1 and args[1] or ''
    local schema=#args>2  and args[2] or ''
    local tidb=db.props.tidb and db.C.tidb
    local version=tonumber((db.props.db_version or '5.0'):match("^%d+%.%d"))
    env.checkhelp(sql)

    fmt=fmt:upper()
    if tidb then
        fmt=tidb.parse_explain_option(fmt,nil,schema)
    else
        fmt=fmt:gsub('.*=','')
        if fmt:upper()=='ANALYZE' or fmt=='EXEC' or fmt=='-EXEC' then
            fmt='ANALYZE'
            if schema:upper()=='JSON' or schema:upper()=='ROW' or schema:upper()=='TREE' then
                fmt=fmt..' FORMAT='..(schema:upper()=='ROW' and 'TRADITIONAL' or schema)
                schema=''
            end
        else
            fmt='FORMAT='..((fmt:upper()=='ROW' or version<8) and 'TRADITIONAL' or (fmt=='' and 'TREE') or fmt)
        end

        if schema~='' then
            fmt=fmt..' FOR SCHEMA '..schema
        end
    end
    
    
    env.set.set('feed','off')
    local json,file,typ
    if #sql<256 and not sql:find('\n',1,true) then 
        typ,file=env.os.exists(sql)
    end
    if file then
        env.checkerr(typ=='file','Target location is not a file: '..file)
        local succ,data=pcall(loader.readFile,loader,file,10485760)
        env.checkerr(succ,tostring(data))

        data=event("ON_PARSE_PLAN",{data}) [1]
        if not data then return end

        json=xplan.parse_plan_tree(data) or json
        env.checkerr(json,"Cannot find valid plan data from file "..file)
        env.checkerr(json:find(config.root,1,true) and json:find(config.child,1,true),"Invalid execution plan.")
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
        return xplan.print_stmt(sql,rows)
    end
    
    parser.parse_json_plan(json,config)
end

function xplan.print_stmt(stmt,rows)
    rows=event("ON_PARSE_PLAN",{rows,stmt}) [1]
    if not rows then return end
    if not stmt:find('FORMAT=TREE',1,true) then
        return env.grid.print(rows)
    end
    rows=rows[2][#rows[2]]
    local json=xplan.parse_plan_tree(rows)
    if not json or
       not json:find(config.root,1,true) or 
       not json:find(config.child,1,true)
    then return print(rows) end
    parser.parse_json_plan(json,config)
end


function xplan.autoplan(name,value)
    if name=='AUTOPLANFORMAT' then
        autoplan_format=value
    elseif name=='AUTOPLAN' then 
        autoplan=value
    end
    return value
end

local tracable={SELECT=1,WITH=1,INSERT=1,UPDATE=1,DELETE=1,MERGE=1,CREATE={TABLE=1,INDEX=1}}
function xplan.before_db_exec(obj)
    local db,sql,args,params,is_internal=table.unpack(obj)
    local tidb=db.props.tidb and db.C.tidb or nil
    if autoplan=='off' or is_internal or not sql then return end
    local action,item=env.db_core.get_command_type(sql)
    local found=tracable[action]
    if not found or type(found)=='table' and item and not found[item] then return end
    local args1,params1=table.clone(args),table.clone(params)
    local version=tonumber(db.props.db_version:match("^%d+%.%d"))
    local is_analyze=autoplan~='xplan' and 'ANALYZE' or ''
    local stmt=string.format('EXPLAIN %s %s \n%s',
        tidb and tidb.parse_explain_option(is_analyze) or version>=8 and is_analyze  or '',
        tidb and tidb.parse_explain_option(nil,autoplan_format) or
       --((autoplan_format=='oracle' or autoplan_format=='json') and 'FORMAT=JSON' or
        ((autoplan_format=='table' or version<8) and 'FORMAT=TRADITIONAL') or
        'FORMAT=TREE',
        sql)
    if is_analyze and autoplan=='analyze' then
        if not env.is_main_thread() then
            print('----------------------------------SQL Statement-------------------------------------')
            print(sql)
        end
        obj[2]=nil
    end
    
    local res=db:exec(stmt,args1,params1)
    local rows=db.resultset:rows(res,-1)
    if autoplan_format~='oracle' then
        return env.grid.print(rows)
    end
    xplan.print_stmt(stmt,rows)
end


function xplan.parse_plan_tree(text)
    local pos=text:find('[^\n\r]+%=%d+[^\n\r]+ rows=%d+')
    if not pos then return nil end
    text=text:sub(pos)
    local tree={[config.root]={[config.child]={},__indent__=0}}
    local maps={tree[config.root]}
    local indent,node=0,maps[1]
    local init_space=nil
    for line,_,num in text:gsplit("[\n\r]+") do
        if line:trim()=='' then break end
        local space,suffix=line:match('^(%s*)%->%s*(.-)%s*$')
        if not space then 
            print('Unexpected line #'..num..': '..line) 
            return
        end
        indent=nil
        line=suffix
        if init_space==nil then
            init_space=#space
            indent=2
        end
        space=#space-init_space
        for i=#maps,2,-1 do
            if maps[i].__indent__>=space then
                maps[i]=nil
            else
                indent=i+1
                break
            end
        end
        if not indent then
            indent=#maps+1
        end
        node={[config.child]={},__indent__=space}
        maps[indent]=node
        if maps[indent-1] then
            table.insert(maps[indent-1][config.child],node)
        else
            print("Missing parent node at line #"..num..": ",indent,space,line)
        end
        
        local node_type,costs=line:match('^(.-)%s+(%(.-)%)$')
        if not node_type then 
            node_type=line:match('^(%S+)%s*$')
        end
        if not node_type then
            print("Cannot find cost info in line #"..num..': '..line)
        else
            local name,schema,tab=node_type:match('^(.*)%s+on%s+(.-)$')
            if name then
                node_type=name
                name,tab=schema:match('^(%S+)%.(.+)$')
                if tab then
                    schema=tab
                    node["Schema"]=name
                end
                name,tab=schema:match("^(.*)%s+using%s+(.-)$")
                if name then
                    if tab=='PRIMARY' then
                        schema=name..'(PK)'
                    elseif tab~=name then
                        schema=name..'('..tab..')'
                    else
                        schema=name
                    end
                end

                tab,name=schema:match('^(%S+)%s+(%S-)$')
                if tab and not schema:find('^%W.*%W$') then
                    node["Relation Name"],node["Alias"]=tab,name
                else
                    node["Relation Name"]=schema
                end
                
            end
            local comma
            node["Node Type"],comma,suffix=node_type:match('^(.-)%s*(:)(.*)$')
            if not comma then
                node["Node Type"],comma=node_type,''
            elseif suffix~='' then 
                node['['..node["Node Type"]..']']=suffix:trim()
            end
            if costs then
                local rows,width
                costs=costs:gsub('%(never executed.*','')
                local cost,actual_cost=costs:match('^(.*)(%([aA]ctual time.*)$')
                if actual_cost then
                    costs=cost
                    cost,rows,width=actual_cost:match("[aA]ctual time=(%S+)%s+rows=(%S+)%s+loops=(%S+)")
                    if cost then
                        local start_,end_=cost:match("^(.*)%.%.(.*)$")
                        node["Actual Startup Time"],node["Actual Total Time"]=tonumber(start_)*1000,tonumber(end_)*1000
                        
                        node["Actual Rows"],node["Actual Loops"]=rows,width
                    end
                end
                
                width,actual_cost=costs:match("^(.*)(%s*%(.-)$")
                if actual_cost then
                    cost,rows=actual_cost:match("%(cost=(%S+).*%s+rows=(%d+)")
                    if cost then
                        costs=width
                        if cost:find('..',1,true) then
                            node["Startup Cost"],node["Total Cost"]=cost:match("^(.*)%.%.(.*)$")
                        else
                            node["Total Cost"]=cost
                        end
                        node["Plan Rows"]=rows
                    else
                        costs=width..actual_cost
                    end
                end
                if costs:trim()~='' and costs:trim()~='(no condition)' then
                    node[comma~=':' and '[Access]' or ('['..node["Node Type"]..']')]=costs
                end
            end
        end
    end

    local replace_list={["Node Type"]=1,[config.child]=1,['Actual Startup Time']=1,['Startup Cost']=1}
    local replace_nodes={Filter=1,Hash=1}
    local remove_filter=function(node,func)
        local childs=node[config.child]
        if replace_nodes[node["Node Type"]] and #childs==1 then
            for k,v in pairs(childs[1]) do
                if not node[k] or replace_list[k] then
                    node[k]=v
                elseif k=="Actual Rows" then
                    node['[Filter Removed Rows]']=tonumber(v)-tonumber(node[k])
                end
            end
        end
        for _,child in ipairs(childs) do
            func(child,func)
        end
    end
    remove_filter(maps[1],remove_filter)
    return env.json.encode(tree)
end

function xplan.onload()
    local help=[[
    Explain SQL execution plan, type 'help @@NAME' for more details. Usage: @@NAME [<options>] [<schema>] [<Id>|<SQL Id>|<SQL Text>|<File>]

    Options:
        <format>   : TRADITIONAL/ ROW / JSON / TREE
        ANALYZE    : analyze the execution plan
    Parameters:
        <id>       : connection id from `performance_schema`.`processlist`
        <SQL Text> : SELECT/DELETE/UPDATE/MERGE/etc that can produce the execution plan
        <SQL ID>   : The SQL ID from pg_stat_statements
        <File>     : The file path that is the execution plan in JSON format
    ]]
    env.set_command(nil,{"XPLAIN","XPLAN"},help,xplan.explain,'__SMART_PARSE__',6,true)
    env.set.init("AUTOPLAN","off",xplan.autoplan,"explain","Controls generating execution plan of the input SQLs",'xplan,analyze,exec,off')
    env.set.init("AUTOPLANFORMAT","tree",xplan.autoplan,"explain","Controls the output execution plan type when autoplan=on",'oracle,tree,row,json')
    env.event.snoop('BEFORE_DB_EXEC',xplan.before_db_exec)
    env.event.snoop('BEFORE_DB_CONNECT',function() auto_generic=nil;env.set.force_set("autoplan",'off') end)
end

return xplan