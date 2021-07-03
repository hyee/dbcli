local dicts={}
local env=env
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local datapath=env.join_path(env.WORK_DIR,'mysql/dict.pack')
local current_dict=nil

function dicts.reorg_dict(dict,rows,prefix,val)
	db:assert_connect()
	local cnt=#rows-1
	local branch=db.props.branch or 'mysql'
	if not dict.mysql then dict.mysql={} end
	if not dict[branch] then dict[branch]={} end
    local source=dict[branch]
    local mysql=dict["mysql"]
    local counter=0
    val=val or 1
    for _,row in ipairs(rows) do
    	local row=prefix..(type(row)=='table' and row[1] or row):lower()
    	if source~=mysql and not mysql[row] then
			source[row]=val
			counter=counter+1
		elseif source==mysql then
			source[row]=val
			counter=counter+1
			for n,d in pairs(dict) do
				if type(d)=='table' and d~=mysql then d[row]=nil end
			end
		end
    end
    return counter
end

function dicts.build_dict(typ,scope)
	env.checkhelp(typ)
	typ=typ:lower()
	local sqls={
		[[show global variables]],
		[[SELECT concat_ws('.',lower(TABLE_SCHEMA),lower(TABLE_NAME)) fname FROM INFORMATION_SCHEMA.TABLES
		  WHERE  lower(table_schema) in('information_schema','sys','mysql','performance_schema','metrics_schema')
		]],
		[[select lower(a.name) 
		  from mysql.help_topic as a join mysql.help_category as b using(help_category_id) 
		  where lower(b.name) like '%functions%' and length(a.name)>3 and instr(a.name,' ')=0
		]],
	}
	local dict,path
	if typ=='public' then
		path=datapath
		if os.exists(path) then
			dict=dicts.load_dict(path,false)
		end
	else
		db:assert_connect()
		path=current_dict
		if path==nil then return end
	end
	if dict==nil then dict={keywords={},commands={}} end
	local count,done,rows=0
	for i,sql in ipairs(sqls) do
		done,rows=pcall(db.get_rows,db,sql)
		if done then
    		table.remove(rows,1)
    		count=count+dicts.reorg_dict(dict.keywords,rows,i==1 and '@@' or '')
    	end
    end
    done,rows=pcall(db.get_rows,db,[[select upper(name) from help_topic where length(name)>=3]])
    if done and #rows>1 then
    	table.remove(rows,1)
    	local help=dict.commands.HELP or {}
    	for i,row in ipairs(rows) do
    		help[row[1]]=1
    		count=count+1
    	end
    	dict.commands.HELP=help
        rows=db:get_rows([[select name,substr(description,1,256) from help_topic where length(name)>2]])
        table.remove(rows,1)
        local len=#rows
    	for i=len,1,-1 do
    		local row=rows[i]
        	local flag=0
    		local op=row[1]:match('%S+')
    		if row[1]~='SHOW' and op~='HELP' and env._CMDS[op] then
	    		local desc=(row[2]..'\n'):match('Syntax:%s*\n%s*('..row[1]:trim():gsub('%s+','[^\n]+')..'.-)\n%s*\n')
	    		if not desc then 
	    			desc,flag=row[1],1
	    		else
	    			desc=desc:trim():gsub('%s+',' '):gsub([[[%['"{ ]*%l.*]],''):gsub('%[[^%]]*$',''):gsub('{[^}]*$',''):trim()
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

    	local rs=db:get_rows([[select name,description from help_topic where name='SHOW']])
    	for n in rs[2][2]:gmatch('\n%s*(SHOW%s+[%[%{%u][^\r\n]+)') do
    		rows[#rows+1]={'SHOW',n:gsub([[[%['"{ ]*%l.*]],''):gsub('%[[^%]]*$',''):gsub('{[^}]*$',''):trim()}
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
		    	local parents={words}
		    	re.gsub(rest:gsub('[%[%]]','~'),p,function(s)
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
	    	if type(stack)~='table' then
	    		print(root,word,stack)
	    	end
	    	for n,v in pairs(stack) do
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
    dicts.load_dict(dict,"all")
    print(count..' records saved into '..path)
end

local function set_keywords(dict,category)
	dict=dict[category]
	if not dict then return end
	local keys={}
	for key,_ in pairs(dict) do
		keys[key]=category
	end
	console:setKeywords(keys)
	table.clear(dict)
end

function dicts.load_dict(path,category)
	local data
	if type(path)=='table' then
		data=path
	else
		if not os.exists(path) then return end
		data=env.load_data(path,true)
	end
	if category~=false then
		local keywords=data.keywords
		set_keywords(keywords,category or 'mysql')
		if category=='all' then
			for branch,_ in pairs(keywords) do
				if db.props[branch] and branch~='mysql' then
					set_keywords(keywords,branch)
				end
			end
		end
		console:setSubCommands(data.commands)
	end
    return data
end

local current_branch
function dicts.on_after_db_conn()
	if current_branch then return end
	for _,branch in ipairs{'tidb','ob','maria'} do
		if db.props[branch] then
			current_branch=branch
			dicts.load_dict(datapath,branch)
			break
		end
	end
end

function dicts.on_after_db_disc()
	
end

function dicts.onload()
	env.set_command(nil,'DICT',[[
        Show or create dictionary for auto completion. Usage: @@NAME {<init|public [all|dict|param]>} | {<obj|param> <keyword>}
        init  : Create a separate offline dictionary that only used for current database
        public: Create a public offline dictionary(file oracle/dict.pack), which accepts following options
            * dict  : Only build the Oracle maintained object dictionary
            * param : Only build the Oracle parameter dictionary
            * all   : Build either dict and param
        param : Fuzzy search the parameters that stored in offline dictionary]],dicts.build_dict,false,3)
	event.snoop('AFTER_MYSQL_CONNECT',dicts.on_after_db_conn)
    event.snoop('ON_DB_DISCONNECTED',dicts.on_after_db_disc)
    dicts.load_dict(datapath)
end

return dicts