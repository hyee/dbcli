local env=env
local db=env.getdb()
local findobj,cache_obj,loaded={},{}
local json = require("json")
local sys_schemas="('information_schema','sys','mysql','performance_schema','metrics_schema','sys','ndbinfo')"
local default_args={target='v1',object_owner="#VARCHAR",object_type="#VARCHAR",object_name="#VARCHAR",object_subname="#VARCHAR"}

local stmt=([[
	SELECT * FROM (
		SELECT table_schema `Schema`,
               table_name,
               ELT(matches,'TABLE','PARTITION','SUBPARTITION') object_type,
               ELT(matches,'',partition_name,subpartition_name) sub_name
        FROM   (SELECT table_schema,table_name,partition_name,subpartition_name,
                       CASE WHEN lower(concat(table_schema, '.', table_name)) LIKE :obj THEN 1
                            WHEN lower(concat_ws('.',table_schema,table_name,partition_name)) LIKE concat('%',trim('%' FROM :obj)) THEN 2
                            WHEN lower(concat_ws('.',table_schema,table_name,subpartition_name)) LIKE concat('%',trim('%' FROM :obj)) THEN 3
                            ELSE 0
                       END matches
                FROM   information_schema.partitions) A
        WHERE   matches>0
		UNION ALL
		SELECT DISTINCT 
		       index_schema, index_name COLLATE utf8_general_ci, index_type,NULL
		FROM   information_schema.statistics
		WHERE  index_name!='PRIMARY'
		AND    lower(concat(index_schema, '.', index_name)) LIKE :obj
		UNION ALL
		SELECT routine_schema, routine_name, routine_type,NULL
		FROM   information_schema.routines
		WHERE  lower(concat(routine_schema, '.', routine_name)) LIKE :obj
		UNION ALL
		SELECT trigger_schema, trigger_name COLLATE utf8_general_ci, 'TRIGGER',NULL
		FROM   information_schema.triggers
		WHERE  lower(concat(trigger_schema, '.', trigger_name)) LIKE :obj
	) M
	ORDER BY CASE WHEN `Schema`=database() THEN 0 ELSE 1 END
	LIMIT 1]]):gsub('@schemas@',sys_schemas)
function db:check_obj(obj_name,bypass_error,is_set_env)
	local name=obj_name:lower():gsub('`','')
	env.checkerr(bypass_error=='1' or name~="","Please input the object name/id!")
	if cache_obj~=db.C.dict.cache_obj then cache_obj=db.C.dict.cache_obj end
    if not cache_obj then
    	cache_obj=setmetatable({},{
    		__index=function(self,name)
    			return rawget(self,name:lower())
    		end
    	})
    	local sql=([[
			SELECT *
			FROM (
		        SELECT table_schema AS `SCHEMA`, table_name AS `NAME`, SUBSTRING_INDEX(table_type, ' ', -1) AS `TYPE`
		        FROM   information_schema.tables
		        WHERE  LOWER(table_schema) IN @schemas@
		        UNION ALL
		        SELECT DISTINCT 
		               index_schema, index_name COLLATE utf8_general_ci, index_type
		        FROM   information_schema.statistics
		        WHERE  index_name!='PRIMARY'
		        AND    LOWER(index_schema) IN @schemas@
		        UNION ALL
		        SELECT routine_schema, routine_name, routine_type
		        FROM   information_schema.routines
		        WHERE  LOWER(routine_schema) IN @schemas@
		        UNION ALL
		        SELECT trigger_schema, trigger_name COLLATE utf8_general_ci, 'TRIGGER'
		        FROM   information_schema.triggers
		        WHERE  LOWER(trigger_schema) IN @schemas@
			) M]]):gsub('@schemas@',sys_schemas)
		local rows=db:get_rows(sql)
		for _,obj in ipairs(rows) do
			local item={object_owner=obj[1],object_name=obj[2],object_type=obj[3]}
			cache_obj[obj[2]:lower()],cache_obj[(obj[1]..'.'..obj[2]):lower()]=item,item
		end
		db.C.dict.cache_obj=cache_obj
	end
	local item=cache_obj[name]
	if not item and obj~="" then
		if not name:find('.',1,true) then name='%.'..name end
		local result=self:exec_cache(stmt,{obj=name},'Internal_FindObject')
		local obj=db.resultset:rows(result,-1,'')[2]
		if obj then
			item={object_owner=obj[1],object_name=obj[2],object_type=obj[3],object_subname=obj[4]}
		end
	end

	if item then 
		item.target=obj_name
		item.full_name=table.concat({item.object_owner,item.object_name,item.object_subname~='' and item.object_subname or nil},'.')
		if item.object_subname~='' then
			cache_obj[table.concat({item.object_name,item.object_subname},'.'):lower()]=item
		end
		cache_obj[obj_name],cache_obj[item.full_name:lower()]=item,item 
	end

	if is_set_env then
    	for k,v in pairs(default_args) do
    		if k:find('^object') then env.var.setInputs(k:upper(),item and item[k] or db.NOT_ASSIGNED) end
    	end
    end

    env.checkerr(bypass_error=='1' or item~=nil,'Cannot find target object: '..obj_name)
    return item
end

local privs={}
function db:check_access(obj_name,bypass_error,is_set_env,is_cache)
	local obj=cache_obj[obj_name] or privs[obj_name]
	if obj~=nil then 
		if type(obj)=="table" and obj.accessible then 
			return obj.accessible==1
		elseif type(obj)=="number" then
			return obj==1
		end
	end

	obj=self:check_obj(obj_name,bypass_error,is_set_env)
	if not obj or not obj.object_id then
		if is_cache==true then privs[obj_name]=0 end
		return false 
	end

	local o=obj.target
    if cache_obj[o] and cache_obj[o].accessible then return cache_obj[o].accessible==1 end
    local err=pcall(db.internal_call,db,'select 1 from '..obj.full_name..' limit 1')
    cache_obj[o].accessible=err and 0 or 1
    --env.checkerr(bypass_error=='1' or not err,"You don't have access right on: "..item.full_name)
    return not err and true or false
end

function findobj.onreset()
	cache_obj,privs,loaded={},{}
end

function findobj.onload()
	env.set_command(db,"FINDOBJ","#internal",db.check_obj,false,4)
	env.event.snoop("AFTER_ORACLE_CONNECT",findobj.onreset)
end

return findobj