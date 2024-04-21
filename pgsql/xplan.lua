local db,cfg=env.getdb(),env.set
local autoplan,autoplan_format='off','oracle'
local auto_generic=nil
local xplan={}
local config={
    root='Plan',
    child='Plans',
    indent_width=2,
    processor=function(name,value,row,node)
        if not name and node then
            if node["Actual Startup Time"] then
                node["Actual Time"]=node["Actual Total Time"]-node["Actual Startup Time"]
            end
            if node["Startup Cost"] then
                node["Costs"]=node["Total Cost"]-node["Startup Cost"]
                if node["Actual Startup Time"] then
                    node["Startup Cost"]=nil
                    if name=='Startup Cost' then
                        return nil
                    end
                end
            end
            if node["Sort Space Used"] and node["Sort Space Type"]=='Memory' and not node["Peak Memory Usage"] then
                node["Peak Memory Usage"]=node["Sort Space Used"]
            end

            local removed=0
            for n,v in pairs(node) do
                if n:find("Rows Removed",1,true) then
                    removed=removed+v
                end
            end
            if removed>0 then node["Rows Removed"]=removed end

            local base,schema="Index Name",node["Schema"]
            if node['Relation Name'] and schema then
                node['Relation Name'],node["Schema"]=schema..'.'..node['Relation Name'],nil
            end
            for _,n in ipairs{'Relation Name','Function Name','CTE Name','Subplan Name'} do
                local name=node[n]
                if name then
                    if not node[base] then
                        if n=="Relation Name" then
                            node[base]=name
                        elseif n=='Function Name' then
                            node[base]=name..'()'
                        elseif n=='CTE Name' then
                            node[base]='['..name..']'
                        else
                            node[base]='<'..name..'>'
                        end
                        node[n]=''
                        break
                    end
                end
            end
        end
        if name=='Parent Relationship' then
            return value=='Outer'   and '<'  or 
                   value=='Inner'   and '>' or 
                   value=='SubPlan' and '*' or 
                   value:sub(1,1);
        elseif name=='Join Type' then
            if value=='Inner' then return '' end
            local childs=node and node['Plans']
            if childs and #childs>1 then
                if value=='Left' or value=='Full' then
                    childs[2]["Node Type"]=(childs[2]["Node Type"] or "")..' (+)'
                end
                if value=='Right' or value=='Full' then
                    childs[1]["Node Type"]=(childs[1]["Node Type"] or "")..' (+)'
                end
            end
        elseif name=='Peak Memory Usage' then
            return (tonumber(value) or 0)*1024
        elseif name=='Execution Time' or name=='Planning Time' or name=='Total Runtime' then
            return env.var.format_function("usmhd2")(value*1000)
        elseif name and name:find(' Time',1,true) then
            return value*1000
        end
        return value
    end,
    columns={{{"Parent Relationship","Parallel Aware","Join Type","Sort Space Type","Strategy","Node Type"},"Plan|Operation"},'|',
              {"Index Name","Object|Name"},'|',
              {"Alias","Obj|Alias"},'|',
              {"Plan Rows","Est|Rows",format='TMB1'},{"Actual Rows","Act|Rows",format='TMB1'},
              {"Rows Removed","Removed|Rows",format='TMB1'}, '|',
              {"Actual Loops","Act|Loops",format='TMB1'},'|',
              {"Actual Time","Leaf|Time",format='usmhd1'} ,'|',
              {"Actual Startup Time","Start|Time",format='usmhd1'},{"Actual Total Time","Total|Time",format='usmhd1'},'|',
              {"IO Read Time","I/O|Read",format='usmhd1'},{"IO Write Time","I/O|Write",format='usmhd1'},'|',
              {"Temp IO Read Time","Temp|Read",format='usmhd1'},{"Temp IO Write Time","Temp|Write",format='usmhd1'},'|',
              {"Plan Width","Est|Width"},'|',
              {"Costs","Leaf|Cost",format='TMB2'},{"Startup Cost","Start|Cost",format='TMB2'},{"Total Cost","Total|Cost",format='TMB2'},'|',
              {"Peak Memory Usage","Memory|Usages",format='KMG1'},'|',
              {"Shared Hit Blocks","Shared|Hits",format='TMB1'},{"Local Hit Blocks","Local|Hits",format='TMB1'}, '|',
              {"Shared Read Blocks","Shared|Reads",format='TMB1'},{"Local Read Blocks","Local|Reads",format='TMB1'}, '|',
              {"Shared Dirtied Blocks","Shared|Dirty",format='TMB1'},{"Local Dirtied Blocks","Local|Dirty",format='TMB1'}, '|',
              {"Shared Written Blocks","Shared|Writes",format='TMB1'},{"Local Written Blocks","Local|Writes",format='TMB1'}, '|',
              {"Temp Read Blocks","Temp|Reads",format='TMB1'},{"Temp Written Blocks","Temp|Writes",format='TMB1'}, '|',
              {"Original Hash Buckets","Origin|Buckets",format='TMB1'},{"Hash Buckets","Hash|Buckets",format='TMB1'}, '|',
              {"Original Hash Batches","Origin|Batches",format='TMB1'},{"Hash Batches","Hash|Batches",format='TMB1'}, '|'
            },
    --sorts={"Actual Startup Time","Actual Total Time"},
    excludes={"Parent Relationship"},
    percents={"Actual Time"},
    title='Plan Tree | (+): Outer-Joined   >: Data-In   <: Data-Out   *: Sub-Plan   S: Sub-Query   I: Int-Plan   M: Member',
    projection="Output"
}
function xplan.explain(fmt,sql)
    env.checkhelp(fmt)
    local options,is_oracle={},true
    if sql then
        fmt=fmt:lower()
        local c,_,fmts=fmt:find('^%((.*)%)$')
        if not fmts then fmts=fmd end
        fmts,c=fmts:gsub('%-?pgsql,?','')
        if c==0 then fmts,c=fmts:gsub('%-?pg,?','') end
        if c and c>0 then
            is_oracle=false
        elseif fmt=='-pg' or fmt=='-pgsql'  then
            is_oracle=false
        elseif fmt=='-exec' or fmt=='-analyze' then
            fmts='analyze'
        end
        if not fmts:find('costs') then
            options[#options+1]='costs'
        end
        if fmts~='' then
            options[#options+1]=fmts
            if fmts:find('analy') then
                if not fmts:find('timing') then
                    options[#options+1]='timing'
                end
                if not fmts:find('buffers') then
                    options[#options+1]='buffers'
                end
            end
        end
        if not fmts:find('format') then
            options[#options+1]=is_oracle and 'format json' or 'format text'
        else
            is_oracle=false
        end
    else
        sql=fmt
    end
    if #options==0 then
        options={'costs,format json'}
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
        fmt='('..table.concat(options,',')..')'
        if tonumber(sql) then
            db:check_obj('pg_stat_statements',nil,true)
            local rs=db:get_rows("select query from pg_stat_statements where queryid="..sql)
            env.checkerr(#rs>1,"No SQL find in pg_stat_statements: "..sql)
            sql=rs[2][1]
        end
        local params,c,_={},0
        sql,_=(sql..' '):gsub("([^$a-zA-Z0-9])($%d+)([^$a-zA-Z0-9])",function(prefix,var,suffix)
            if not params[var] then
                c=c+1
                params[c],params[var]='unknown',1;
            end
            return prefix..var..suffix
        end)
        if c==0 then
            sql,_=sql:gsub("([^%?a-zA-Z0-9])%?([^%?a-zA-Z0-9])",function(prefix,suffix)
                c=c+1
                params[c]='unknown';
                return prefix..'$'..c..suffix
            end)
        end
        if c>0 then
            env.checkerr(db.props.plan_cache_mode,"plan_cache_mode is unsupported!")
            if auto_generic==nil then
                auto_generic=pcall(db.internal_call,db,'explain (generic_plan) select 1')
            end
            if auto_generic then
                options[#options+1] = 'generic_plan'
                fmt='('..table.concat(options,',')..')'
            end
            pcall(db.internal_call,db,'DEALLOCATE dbcli_pgsql_xplan')
            --execute statements sperately to make sure the errorstacks can identify the exact error position
            db:exec(("prepare dbcli_pgsql_xplan(%s) as\n%s"):format(table.concat(params,','),sql));
            sql=("%sexplain %s\nexecute dbcli_pgsql_xplan(%s)%s"):format(
                auto_generic and '' or 'set plan_cache_mode=force_generic_plan;\n',
                fmt,
                string.rep('null,',c):rtrim(','),
                auto_generic and '' or ';\nset plan_cache_mode=auto')
        else
            sql='explain '..fmt..'\n'..sql
        end
        
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
        end
    end
    
    env.json_plan.parse_json_plan(json,config)
end

function  xplan.autoplan(name,value)
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
    local stmt=string.format('EXPLAIN (%sCOSTS,FORMAT %s)\n%s',
        autoplan=='xplan' and '' or 'ANALYZE,TIMING,BUFFERS,',
        (autoplan_format=='oracle' or autoplan_format=='json') and 'JSON' or 'TEXT',
        sql)
    if autoplan_format=='perf' then
        stmt='EXPLAIN PERFORMANCE\n'..sql
    end
    if autoplan=='analyze' then
        if #env.RUNNING_THREADS>2 then
            print('----------------------------------SQL Statement-------------------------------------')
            print(sql)
        end
        obj[2]=nil
    end

    if autoplan_format~='oracle' then
        return db:query(stmt,args1,params1)
    end

    local rows=db.resultset:rows(db:exec(stmt,args1,params1),-1)
    env.json_plan.parse_json_plan(rows[2][1],config)
end

function xplan.parse_plan_tree(text)
    local pos=text:find('[^\n\r]+%(cost=[^\n\r]+ rows=[^\n\r]+ width=')
    if not pos then return nil end
    text=text:sub(pos)
    local tree={[config.root]={[config.child]={}}}
    local maps={tree[config.root]}
    local seq,indent,node=0,0,maps[1]
    local init_space=nil
    local func=xplan.tree_maps
    local function apply(node,parent,line)
        for n,v in line:gmatch("(%w[^=]+)%s*=%s*(%S+)") do
            func.apply(node,((parent and (parent..'/') or '')..n):trim(),v:rtrim(','))
        end
    end
    for line,_,num in text:gsplit("[\n\r]+") do
        if line:trim()=='' then break end
        local space,suffix=line:match('^(%s+)%->%s*(.-)%s*$')
        if space then
            line=suffix
            seq=0
            if init_space==nil then
                init_space=#space
                indent=2
            else
                indent=math.max(2,math.floor((#space-init_space)/6)+2)
            end
            for i=#maps,indent+1,-1 do
                maps[i]=nil
            end
            node={[config.child]={}}
            maps[indent]=node
            if maps[indent-1] then
                table.insert(maps[indent-1][config.child],node)
            else
                print("Missing parent node at line #"..num..": ",indent,#space,line)
            end
        end
        
        line=line:trim()

        seq=seq+1
        if seq==1 then
            local node_type,costs=line:match('^(.-)%s+(%(.-)%)$')
            if not node_type then
                seq=seq-1
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
                    tab,name=schema:match('^(%S+)%s+(%S-)$')
                    if tab and not schema:find('^".*"$') then
                        node["Relation Name"],node["Alias"]=tab,name
                    else
                        node["Relation Name"]=schema
                    end
                    name,tab=node_type:match("^(.*)%s+using%s+(.-)$")
                    if name then
                        node_type=name
                        node["Index Name"]=tab
                    end
                end             
                node["Node Type"]=node_type

                local rows,width
                local cost,actual_cost=costs:match('^(.+)(%([aA]ctual time.*)$')
                if actual_cost then
                    costs=cost
                    cost,rows,width=actual_cost:match("[aA]ctual time=(%S+)%s+rows=(%S+)%s+loops=(%S+)")
                    if cost then
                        node["Actual Startup Time"],node["Actual Total Time"]=cost:match("^(.*)%.%.(.*)$")
                        node["Actual Rows"],node["Actual Loops"]=rows,width
                    end
                end
                costs=costs:gsub('%b[]',function(s)
                    return s:gsub('%s+','') end)
                apply(node,nil,costs:trim():sub(2,-2))
            end
        else
            local item,value
            local _,c=line:gsub('%S%s*:[^:]%S','')
            if not line:find('[%{%(%[]') and c>1 then
                apply(node,nil,line:gsub(':','='))
            else 
                item,value=line:match("^(%w[^%):]+):%s*(.-)$")
                if item=="Buffers" then
                    apply(node,item,value)
                elseif item then
                    func.apply(node,item,value)
                elseif line:find('^%(CPU') then
                    --exclude text: (CPU: ex c/r=158, ex row=4628, ex cyc=733184, inc cyc=5814538937151361024)
                else
                    item,value=line:sub(2,-2):match("^(%w[^%):]+):%s*(.-)$")
                    if item then
                        apply(node,item,value)
                    else
                        func.apply(node,'Subplan Name',line)
                    end
                end
            end
        end
    end
    --print(table.dump(tree))
    return env.json.encode(tree)
end

xplan.tree_maps={
    convert_size=function(s)
        local v,unit=s:trim():match('^([0-9%-%.]+)%s*(%S+)$')
        if not v then return s end
        unit=unit:lower():sub(1,1)
        return tonumber(v)*(unit=='k' and 1024 or unit=='m' and 1024^2 or unit=='g' and 1024^3 or unit=='t' and 1024^4 or 1)
    end,
    cost=function(node,s)
        node["Startup Cost"],node["Total Cost"]=s:match("^(.*)%.%.(.*)$")
    end,
    ['rows']="Plan Rows",
    ['width']="Plan Width",
    ['Buffers/shared hit']='Shared Hit Blocks',
    ['Buffers/shared read']='Shared Read Blocks',
    ['Buckets']='Hash Buckets',
    ['Batches']='Hash Batches',
    ['Memory']=function(node,s) node['Sort Space Used']=xplan.tree_maps.convert_size(s) end,
    ['Memory Usage']=function(node,s) node['Peak Memory Usage']=xplan.tree_maps.convert_size(s) end,
    apply=function(node,name,value)
        local func=xplan.tree_maps[name]
        if type(func) =='function' then
            func(node,value,name)
        elseif func then
            node[func]=value
        else
            node[name]=value
        end
    end
}

function xplan.onload()
    local help=[[
    Explain SQL execution plan, type 'help @@NAME' for more details. Usage: @@NAME [<options>] [<SQL Id>|<SQL Text>|<File>]

    Options:
        "([anaylze,][vebose,]...)": same to PostgreSQL documentations on different db versions, should be enclosed with " in case of containing white space.
        "[anaylze,][vebose,]..."  : same to above options
        -pg[sql]                  : display the PostgreSQL style execution plan in instead of Oracle
        -exec|-analyze            : enable the ANALYZE option         
    Parameters:
        <SQL Text> : SELECT/DELETE/UPDATE/MERGE/etc that can produce the execution plan
        <SQL ID>   : The SQL ID from pg_stat_statements
        <File>     : The file path that is the execution plan in JSON format or tree format
    ]]
    env.set_command(nil,{"XPLAIN","XPLAN"},help,xplan.explain,'__SMART_PARSE__',3,true)
    env.set.init("AUTOPLAN","off", xplan.autoplan,"explain","Controls generating execution plan of the input SQLs",'xplan,analyze,exec,off')
    env.set.init("AUTOPLANFORMAT","xplan", xplan.autoplan,"explain","Controls the output execution plan type when autoplan=on",'oracle,pgsql,json')
    env.event.snoop('BEFORE_DB_EXEC',xplan.before_db_exec)
    env.event.snoop('BEFORE_DB_CONNECT',function() auto_generic=nil;env.set.force_set("autoplan",'off') end)
end

return xplan