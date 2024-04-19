local db,cfg=env.getdb(),env.set
local xplan={}


function xplan.explain(fmt,sql)
    env.checkhelp(fmt)
    local options,is_oracle={},true
    if sql then
        fmt=fmt:lower()
        local c,_,fmts=fmt:find('^%((.*)%)$')
        fmts,c=(fmts or ''):gsub('%-?pgsql,?','')
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
            if fmts:find('analyze') then
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
        json=data:match('%b{}')
        env.checkerr(json,"Cannot find valid JSON data from file "..file)
    else
        fmt='('..table.concat(options,',')..')'
        if tonumber(sql) then
            local rs=db:get_rows("select query from pg_stat_statements where queryid="..sql)
            env.checkerr(#rs>1,"No SQL find in pg_stat_statements: "..sql)
            sql=rs[2][1]
        end
        local params,c,_={},0
        sql,_=(sql..' '):gsub("([^$a-zA-Z0-9])($%d+)([^$a-zA-Z0-9])",function(prefix,var,suffix)
            if not params[var] then
                c=c+1
                params[c],params[var]='text',1;
            end
            return prefix..var..suffix
        end)
        if c==0 then
            sql,_=(sql..' '):gsub("([^%?a-zA-Z0-9])%?([^%?a-zA-Z0-9])",function(prefix,suffix)
                c=c+1
                params[c]='text';
                return prefix..'$'..c..suffix
            end)
        end
        if c>0 then
            env.checkerr(db.props.plan_cache_mode,"plan_cache_mode is unsupported!")
            pcall(db.internal_call,db,'DEALLOCATE dbcli_pgsql_xplan')
            sql=("set plan_cache_mode=force_generic_plan;\nprepare dbcli_pgsql_xplan(%s) as\n%s;\nexplain %s\nexecute dbcli_pgsql_xplan(%s)"):format(
                table.concat(params,','),
                sql,
                fmt,
                string.rep('null,',c):rtrim(',')
            )
        else
            sql='explain '..fmt..'\n'..sql
        end
        
        if not is_oracle then
            return db:query(sql)
        else
            local res=db:exec(sql)
            local rows=db.resultset:rows(type(res)=='table' and res[#res] or res,-1)
            json=rows[2][1]
        end
    end
    local options={
        root='Plan',
        child='Plans',
        processor=function(name,value,row,node)
            if node and node["Actual Startup Time"] and not node["Actual Time"] then
                node["Actual Time"]=(node["Actual Total Time"]-node["Actual Startup Time"])*1000
            end
            if node and node["Startup Cost"] and not node["Costs"] then
                node["Costs"]=node["Total Cost"]-node["Startup Cost"]
                if node["Actual Startup Time"] then
                    node["Startup Cost"]=nil
                    if name=='Startup Cost' then
                        return nil
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
            elseif name=='Actual Startup Time' or name=='Actual Total Time' then
                return tonumber(value)*1000
            elseif name=='Execution Time' or name=='Planning Time' then
                return env.var.format_function("usmhd2")(value*1000)
            elseif row and name=='Index Name' then
                row[("Relation Name"):upper()]=''
                return value
            elseif row and name=='Relation Name' then
                return row[("Relation Name"):upper()] or value
            end
            return value
        end,
        columns={{{"Parent Relationship","Parallel Aware","Join Type", "Node Type"},"Plan|Operation"},'|',
                  {{"Relation Name","Index Name"},"Object|Name"},'|',
                  {"Alias","Obj|Alias"},'|',
                  {"Plan Rows","Est|Rows",format='TMB1'},{"Actual Rows","Act|Rows",format='TMB1'},
                  {{"Rows Removed by Filter","Rows Removed by Index Recheck"},"Remv|Rows",format='TMB1'}, '|',
                  {"Actual Loops","Act|Loops",format='TMB1'},'|',
                  {"Actual Time","Leaf|Time",format='usmhd1'} ,'|',
                  {"Actual Startup Time","Start|Time",format='usmhd1'},{"Actual Total Time","Total|Time",format='usmhd1'},'|',
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
        others={}
    }
    env.json_plan.parse_json_plan(json,options)
end

function xplan.onload()
    local help=[[
    Explain SQL execution plan, type 'help @@NAME' for more details. Usage: @@NAME [<options>] [<SQL Id>|<SQL Text>]|<File>

    Options:
        ([anaylze][vebose,]...) : same to PostgreSQL documentations on different db versions.
        -pg[sql]                : display the PostgreSQL style execution plan in instead of Oracle
        -exec|-analyze          : enable the ANALYZE option         
    Parameters:
        <SQL Text> : SELECT/DELETE/UPDATE/MERGE/etc that can produce the execution plan
        <SQL ID>   : The SQL ID from pg_stat_statements
        <File>     : The file path that is the execution plan in JSON format
    ]]
    env.set_command(nil,{"XPLAIN","XPLAN"},help,xplan.explain,'__SMART_PARSE__',3,true)
end

return xplan