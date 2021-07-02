local dicts={}
local env=env
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local datapath=env.join_path(env.WORK_DIR,'mysql/dict.pack')
local current_dict=nil

function dicts.reorg_dict(dict,rows)
	db:assert_connect()
	local cnt=#rows-1
	local branch=db.props.branch or 'mysql'
    local source=dict[branch]
    local mysql=dict["mysql"]
    local counter=0
    for _,row in ipairs(rows) do
    	local row=type(row)=='table' and row[1] or row
    	if source~=mysql and not mysql[row] then
			source[row]=1
			counter=counter+1
		elseif source==mysql then
			source[row]=1
			counter=counter+1
			for n,d in pairs(dict) do
				if type(d)=='table' and d~=mysql then d[row]=nil end
			end
		end
    end
    return counter
end

function dicts.build_dict(type,scope)
	env.checkhelp(type)
	type=type:lower()
	local sql=[[
		SELECT concat_ws('.',lower(TABLE_SCHEMA),lower(TABLE_NAME)) fname FROM INFORMATION_SCHEMA.TABLES
		WHERE TABLE_TYPE IN('SYSTEM VIEW','BASE TABLE')
	]]
	local dict,path
	if type=='public' then
		path=datapath
		if os.exists(path) then
			dict=dicts.load_dict(path,false)
		end
	else
		db:assert_connect()
		path=current_dict
		if path==nil then return end
	end
	if dict==nil then dict={keywords={mysql={},tidb={},ob={},maria={}}} end
	local rs=db:internal_call(sql)
    local rows=db.resultset:rows(rs,-1)
    table.remove(rows,1)
    local count=dicts.reorg_dict(dict.keywords,rows)
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