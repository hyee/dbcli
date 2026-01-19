local dicts={}
local env=env
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local datapath=env.join_path(env.WORK_DIR,'pgsql/dict.pack')
local current_dict,current_dict_exists=nil
local function reorg_dict(dict,rows,version)
    db:assert_connect()
    local version=tonumber((tostring(db.props.db_version):gsub("^(%d+%.%d+).-$","%1")))
    local branch=db.props.branch or 'pgsql'
    if not dict.pgsql then dict.pgsql={} end
    if not dict[branch] then dict[branch]={} end
    local source=dict[branch]
    local pgsql=dict["pgsql"]
    local counter=0
    for _,row in ipairs(rows) do
        local name=(type(row)=='table' and row[1] or row):lower()
        ::Processor::
        local val=type(row)=='table' and tonumber(row[2]) or version
        if source~=pgsql and not pgsql[name] then
            source[name]=math.min(val,source[name] or 999)
            counter=counter+1
        elseif source==pgsql then
            source[name]=math.min(val,source[name] or 999)
            counter=counter+1
            for n,d in pairs(dict) do
                if type(d)=='table' and d~=pgsql then d[name]=nil end
            end
        end
        name=name:match('^pg_catalog%.(.+)')
        if name then goto Processor end
    end
    return counter
end

function dicts.build_dict(typ,scope)
    env.checkhelp(typ)
    typ=typ:lower()
    local sqls={
        [[select name from pg_settings]],
        [[SELECT concat(lower(table_schema), '.', lower(table_name))
          FROM   INFORMATION_SCHEMA.TABLES
          @FILTER@
          UNION ALL
          SELECT concat(lower(routine_schema), '.', lower(routine_name))
          FROM   (SELECT A.*,routine_schema table_schema FROM INFORMATION_SCHEMA.ROUTINES A) A
          @FILTER@
          UNION ALL
          SELECT routine_name 
          FROM INFORMATION_SCHEMA.routines 
          WHERE routine_schema='pg_catalog' 
          AND   length(routine_name)>5]],
    }
    local dict,path,doc,helppath,_categories,filter
    if typ=='param' then
        path=current_dict_exists and current_dict or datapath
        scope=(scope or ''):lower():gsub('%%','.-')
        env.checkhelp(scope~='')
        env.checkerr(os.exists(path),'Offline dictionary is unavailable.')
        local dict=dicts.load_dict(path,false).keywords
        local rows={}
        local matches={}
        for cate,sub in pairs(dict) do
            if type(sub)=='table' then
                for var,val in pairs(sub) do
                    if var:find(scope) then
                        local name=var
                        rows[#rows+1]={nil,cate,name,'N/A',val,''}
                        matches[#matches+1],matches[name]=name,rows[#rows]
                    end
                end
            end
        end
        if #matches>0 and db:is_connect() and #matches<=500 then
            local in_="('"..table.concat(matches,"','").."')"
            local values=db:get_rows("select name,setting,short_desc from pg_settings where name IN "..in_,{},-1,env.set.get('NULL'))
            table.remove(values,1)
            for _,row in ipairs(values) do
                matches[row[1]][4],matches[row[1]][6]=row[2],row[3]
            end
        end
        table.sort(rows,function(a,b) return a[3]<b[3] end)
        for i,row in ipairs(rows) do row[1]=i end
        table.insert(rows,1,{'#','Category','Variable','Current Value','Version','Description'})
        env.grid.print(rows)
        return
    elseif typ=='public' then
        filter=[[WHERE lower(table_schema) IN ('information_schema', 'pg_catalog')]]
        path=datapath
        if os.exists(path) then
            dict=dicts.load_dict(path,false)
        end
        helppath=env.help.helpdict
        if os.exists(helppath) then
            doc=dicts.load_dict(helppath,false)
        else
            doc={}
        end
        _categories=doc._categories or {}
        doc._categories=_categories
    elseif typ=='init' then
        filter=''
        db:assert_connect()
        path=current_dict
        if path==nil then return end
        current_dict_exists=true
    else
        env.checkhelp(nil)
        return
    end
    if dict==nil then dict={keywords={},commands={}} end
    local count,done,rows=0
    for i,sql in ipairs(sqls) do
        done,rows=pcall(db.get_rows,db,sql:gsub('@FILTER@',filter))
        if done then
            table.remove(rows,1)
            count=count+reorg_dict(dict.keywords,rows,'')
        end
    end
    env.save_data(path,dict,31*1024*1024)
    dicts.load_dict(dict,"all")
    print(count..' records saved into '..path)
end

local function set_keywords(dict,category)
    dict=dict[category]
    if not dict then return end
    local val=dict['bind_info']
    if val then
        print(type(val)=='table' and table.dump(val) or val)
    end
    console:setKeywords(dict)
end

function dicts.load_dict(path,category)
    local data
    if type(path)=='table' then
        data=path
    else
        if not os.exists(path) then return end
        data=env.load_data(path,true)
    end
    dicts.data=data
    if category~=false then
        local keywords=data.keywords
        if category=='all' then
            console.completer:resetKeywords();
            for branch,keys in pairs(keywords) do
                if db.props[branch] or branch=='pgsql' then
                    set_keywords(keywords,branch)
                end
            end
        else
            set_keywords(keywords,category or 'pgsql')
        end
        console:setSubCommands(data.commands)
        console:setSubCommands({
            ['?']=data.commands.HELP,
            ['\\?']=data.commands.HELP})
    end
    return data
end

local current_branch,url,usr
function dicts.on_after_db_conn(instance,sql,props)
    current_dict_exists=false
    if props then
        current_dict=env.join_path(env._CACHE_BASE,props.database..'.dict')
        current_dict_exists=os.exists(current_dict)
        if props.url~=url or props.user~=usr then
            console.completer:resetKeywords()
            dicts.load_dict(current_dict_exists and current_dict or datapath,'all')
            dicts.cache_obj=nil
            url,usr=props.url,props.user
        end
    end
end

function dicts.onload()
    env.set_command(nil,'DICT',[[
        Show or create dictionary for auto completion. Usage: @@NAME {<init|public [all|dict|param]>} | {<obj|param> <keyword>}
        init  : Create a separate offline dictionary that only used for current server
        public: Create a public offline dictionary(file pgsql/dict.pack)
        param : Fuzzy search the parameters that stored in offline dictionary]],dicts.build_dict,false,3)
    event.snoop('AFTER_PGSQL_CONNECT',dicts.on_after_db_conn)
    dicts.load_dict(datapath)
end

return dicts