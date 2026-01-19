local dicts={}
local env=env
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local datapath=env.join_path(env.WORK_DIR,'mysql/dict.pack')
local current_dict,current_dict_exists=nil
local function reorg_dict(dict,rows,prefix)
    db:assert_connect()
    local branch=db.props.branch or 'mysql'
    if not dict.mysql then dict.mysql={} end
    if not dict[branch] then dict[branch]={} end
    local source=dict[branch]
    local mysql=dict["mysql"]
    local counter=0
    for _,row in ipairs(rows) do
        local name=prefix..(type(row)=='table' and row[1] or row):lower()
        local val=type(row)=='table' and row[2] or 1
        if source~=mysql and not mysql[name] then
            source[name]=val
            counter=counter+1
        elseif source==mysql then
            source[name]=val
            counter=counter+1
            for n,d in pairs(dict) do
                if type(d)=='table' and d~=mysql then d[name]=nil end
            end
        end
    end
    return counter
end

function dicts.build_dict(typ,scope)
    env.checkhelp(typ)
    typ=typ:lower()
    local sqls={
        [[SHOW VARIABLES]],
        [[SELECT concat(lower(table_schema), '.', lower(table_name))
          FROM   INFORMATION_SCHEMA.TABLES
          @FILTER@
          UNION  ALL
          SELECT concat(lower(routine_schema), '.', lower(routine_name))
          FROM   (SELECT A.*,routine_schema table_schema FROM INFORMATION_SCHEMA.ROUTINES A) A
          @FILTER@]],
        [[SELECT lower(word) from INFORMATION_SCHEMA.KEYWORDS where length(word)>5]],
        [[SELECT lower(a.name)
          FROM   mysql.help_topic AS a
          JOIN   mysql.help_category AS b
          USING  (help_category_id)
          WHERE  parent_category_id IN (SELECT help_category_id FROM mysql.help_category WHERE NAME LIKE '%Function%')
          AND    length(a.name) > 3
          AND    instr(a.name, ' ') = 0]],
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
                for var,_ in pairs(sub) do
                    if var:sub(1,2)=='@@' and var:find(scope) then
                        local name=var:sub(3)
                        rows[#rows+1]={nil,cate,name,'N/A'}
                        matches[#matches+1],matches[name]=name,rows[#rows]
                    end
                end
            end
        end
        if #matches>0 and db:is_connect() and #matches<=500 then
            local in_="('"..table.concat(matches,"','").."')"
            local values=db:get_rows("SHOW VARIABLES WHERE Variable_Name IN "..in_,{},-1,env.set.get('NULL'))
            table.remove(values,1)
            for _,row in ipairs(values) do
                matches[row[1]][4]=row[2]
            end
        end
        table.sort(rows,function(a,b) return a[3]<b[3] end)
        for i,row in ipairs(rows) do row[1]=i end
        table.insert(rows,1,{'#','Category','Variable','Current Value'})
        env.grid.print(rows)
        return
    elseif typ=='public' then
        filter=[[WHERE lower(table_schema) IN ('information_schema', 'sys', 'mysql', 'performance_schema', 'metrics_schema', 'ndbinfo')]]
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
            if i==1 then
                for _,row in ipairs(rows) do row[2]=nil end
            end
            count=count+reorg_dict(dict.keywords,rows,i==1 and '@@' or '')
        end
    end
    done,rows=pcall(db.get_rows,db,[[select upper(name) from mysql.help_topic where length(name)>=3]])
    if done and #rows>1 then
        table.remove(rows,1)
        local help=dict.commands.HELP or {}
        for i,row in ipairs(rows) do
            help[row[1]]=1
            count=count+1
        end
        dict.commands.HELP=help
        rows=db:get_rows([[select upper(a.name),trim(a.description),example,b.name category,help_category_id,parent_category_id,a.url 
                           from mysql.help_topic as a 
                           join mysql.help_category as b using(help_category_id) 
                           where length(a.name)>2]])
        table.remove(rows,1)
        local len=#rows
        for i=len,1,-1 do
            local row=rows[i]
            row[1]=row[1]:gsub('%s+',' '):trim()
            if doc then
                row[2]=row[2]:sub(1,-256)..row[2]:sub(-255):gsub('%s*URL:[^\n]-%s*$','')
                doc[row[1]]={row[2],row[3],row[4],row[5],row[6],row[7]}
                if not _categories[row[4]] then _categories[row[4]]={} end
                _categories[row[4]][1],_categories[row[4]][2]=row[5],row[6]
                _categories[row[4]][row[1]]=1
            end
            local flag=0
            local op=row[1]:match('%S+')
            if row[1]~='SHOW' and op~='HELP' and op~='SELECT' and op~='WITH' and env._CMDS[op] then
                local desc=(row[2]:sub(1,256)..'\n'):match('\n%s*('..row[1]:trim():gsub('%s+','[^\n]+')..'.-)\n%s*\n')
                if not desc then 
                    desc,flag=row[1],1
                else
                    desc=desc:trim():gsub('%s+',' '):match('^[%u |{%[%]}=]+'):gsub('%[[^%]]*$',''):gsub('{[^}]*$',''):trim()
                    --print(op,desc)
                    if #desc<=#row[1] then desc,flag=row[1],2 end
                end
                if not desc:find(' ') then
                    table.remove(rows,i)
                else
                    row[1],row[2]=op,desc
                end
            else
                table.remove(rows,i)
            end
        end

        local rs=db:get_rows([[select name,trim(description) from mysql.help_topic where name='SHOW']])
        if rs[2] then
            for n in rs[2][2]:gmatch('\n%s*(SHOW%s+[%[%{%u][^\r\n]+)') do
                rows[#rows+1]={'SHOW',n:match('^[%u |{%[%]}=]+'):gsub('%[[^%]]*$',''):gsub('{[^}]*$',''):trim()}
            end
        end

        local p=env.re.compile([[
            pattern <- p1/p2/p3
            p1      <- '{' [^}]+ '}'
            p2      <- '~' [^~]+ '~'
            p3      <- [%w$#_]+
        ]],nil,true)
        local stacks=dict.commands
        for i,row in ipairs(rows) do
            row=row[2]
            local cmd,rest=row:match('^(%w+) +(.+)$')
            if not cmd then cmd=row:trim() end
            local words=stacks[cmd]
            if not words then
                count=count+1
                words={}
                stacks[cmd]=words
            end
            if rest then
                --print(row)
                local parents={words}
                env.re.gsub(rest:gsub('[%[%]]','~'),p,function(s)
                    local len=#parents
                    local list={}
                    local pieces=s:gsub('[{~}]',''):split(' *| *')
                    for i,n in ipairs(pieces) do
                        for j=1,len do
                            local p=parents[j]
                            if j==1 and s:find('~',1,true) then
                                parents[#parents+1]=p
                                count=count+1
                            end
                            
                            if not p[n] then
                                p[n]={}
                            end
                            if j==#pieces then
                                parents[j]=p[n]
                            else
                                parents[#parents+1]=p[n]
                                count=count+1
                            end
                        end
                    end
                end)
            end
        end
        table.clear(rows)
        local function walk(word,stack,root)
            if root=='HELP' then return end
            local cnt=0
            for n,v in pairs(stack) do
                if not root then
                    dict.keywords.mysql[n:lower()]=nil
                end
                cnt=cnt+1
                walk(root and (word..(word=='' and '' or ' ')..n) or '',v,root or n)
            end
            if cnt==0 then
                --print(root,word)
            end
        end
        walk('',stacks)
    end
    
    env.save_data(path,dict,31*1024*1024)
    if doc then env.save_data(helppath,doc,31*1024*1024) end
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
                if db.props[branch] or branch=='mysql' then
                    set_keywords(keywords,branch)
                end
            end
        else
            set_keywords(keywords,category or 'mysql')
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
        current_dict=env.join_path(env._CACHE_BASE,props.hostname..'_'..props.port..'.dict')
        current_dict_exists=os.exists(current_dict)
        if props.url~=url or props.user~=usr then
            console.completer:resetKeywords()
            dicts.load_dict(current_dict_exists and current_dict or datapath,'all')
            dicts.cache_obj=nil
            url,usr=props.url,props.user
        end
    end
end

function dicts.on_before_db_exec(item)
    for k,v in ipairs{
        {'DEFAULT_COLLATION',db.props.collation}
    } do
        if var.outputs[v[1]]==nil and v[2]~=nil then var.setInputs(v[1],''..v[2]) end
    end
end

function dicts.onload()
    env.set_command(nil,'DICT',[[
        Show or create dictionary for auto completion. Usage: @@NAME {<init|public [all|dict|param]>} | {<obj|param> <keyword>}
        init  : Create a separate offline dictionary that only used for current server
        public: Create a public offline dictionary(file mysql/dict.pack)
        param : Fuzzy search the parameters that stored in offline dictionary]],dicts.build_dict,false,3)
    event.snoop('AFTER_MYSQL_CONNECT',dicts.on_after_db_conn)
    event.snoop('BEFORE_DB_EXEC',dicts.on_before_db_exec,nil,60)
    dicts.load_dict(datapath)
end

return dicts