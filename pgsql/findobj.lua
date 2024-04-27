local env=env
local db=env.getdb()
local findobj,cache_obj,loaded={},{}
local json = require("json")
local sys_schemas="('information_schema','pg_catalog')"
local default_args={target='v1',object_owner="#VARCHAR",object_type="#VARCHAR",object_name="#VARCHAR",granted="#VARCHAR",object_fullname='#VARCHAR',object_id='INTEGER',object_class='#VARCHAR'}

local stmt=[[
    SELECT * FROM (
        SELECT nspname "SCHEMA",
               relname "NAME",
               CASE TRIM(tbl.relkind)
                   WHEN 'r' THEN
                    'TABLE'
                   WHEN 'p' THEN
                    'PARTITIONED TABLE'
                   WHEN 'c' THEN
                    'TYPE'  
                   WHEN 'f' THEN
                    'FOREIGN TABLE'
                   WHEN 't' THEN
                    'TOAST TABLE'
                   WHEN 'm' THEN
                    'MATERIALZED VIEW'
                   WHEN 'v' THEN
                    'VIEW'
                   WHEN 'i' THEN
                    'INDEX'
                   WHEN 'I' THEN
                    'PARTITIONED INDEX'
                    WHEN 'L' THEN
                    'SEQUENCE' 
                   WHEN 'S' THEN
                    'SEQUENCE'
               END "TYPE",
               pg_has_role(tbl.relowner, 'USAGE'::text) OR has_table_privilege(tbl.oid, 'SELECT'::text) "GRANTED",
               tbl.oid,'pg_class' clz,
               CASE WHEN tbl.relkind in ('m') THEN 0
                    WHEN tbl.relkind in ('r','p') THEN 1
                    WHEN tbl.relkind in ('v','c') THEN 2
                    WHEN tbl.relkind in ('i','I','f') THEN 9
                    ELSE 6 
                END seq_
        FROM   pg_class tbl
        JOIN   pg_namespace nsp ON nsp.oid = tbl.relnamespace
        WHERE  lower(concat(nspname, '.', relname)) LIKE :obj
        UNION ALL
        SELECT nspname,conname,'CONSTRAINT',false,con.oid,'pg_constraint',3
        FROM   pg_constraint con
        JOIN   pg_namespace nsp ON nsp.oid = con.connamespace
        WHERE  lower(concat(nspname, '.', conname)) LIKE :obj
        UNION ALL
        SELECT nspname,proname,'FUNCTION',
               pg_has_role(p.proowner, 'USAGE'::text) OR has_function_privilege(p.oid, 'EXECUTE'::text),
               p.oid,'pg_proc',
               4
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  lower(concat(nspname, '.', proname)) LIKE :obj
        UNION ALL
        SELECT nspname,t.tgname,'TRIGGER',
               pg_has_role(c.relowner, 'USAGE'::text) OR 
               has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'::text) OR 
               has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'::text),
               t.oid,'pg_trigger',
               7
        FROM   pg_namespace n,
               pg_class c,
               pg_trigger t
        WHERE  n.oid = c.relnamespace 
        AND    c.oid = t.tgrelid
        AND    not t.tgisinternal
        AND    lower(concat(nspname, '.', tgname)) LIKE :obj
        UNION ALL
        SELECT n.nspname, rulename, 'RULE',
               false,
               r.oid,'pg_rewrite',
               6
        FROM  pg_rewrite r
        JOIN  pg_class c ON c.oid = r.ev_class
        LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE  r.rulename <> '_RETURN'::name
        AND   lower(concat(n.nspname, '.', r.rulename)) LIKE :obj
    ) M
    ORDER BY "GRANTED" DESC NULLS LAST,
              CASE WHEN "SCHEMA"=CURRENT_USER THEN 0 ELSE 1 END,
              seq_
    LIMIT 1]]
function db:check_obj(obj_name,bypass_error,is_set_env)
    local name=obj_name:lower():gsub('"','')
    bypass_error=tostring(bypass_error):lower()
    env.checkerr(bypass_error=='1' or bypass_error=='true' or name~="","Please input the object name/id!")
    if cache_obj~=db.C.dict.cache_obj then cache_obj=db.C.dict.cache_obj end
    if not loaded and not cache_obj then
        cache_obj=setmetatable({},{
            __index=function(self,name)
                return rawget(self,name:lower())
            end
        })
        
        local sql=([[
            SELECT *
            FROM (
                SELECT nspname "SCHEMA",
                       relname "NAME",
                       CASE TRIM(tbl.relkind)
                           WHEN 'r' THEN
                            'TABLE'
                           WHEN 'p' THEN
                            'PARTITIONED TABLE'
                           WHEN 'f' THEN
                            'FOREIGN TABLE'
                           WHEN 't' THEN
                            'TOAST TABLE'
                           WHEN 'm' THEN
                            'MATERIALZED VIEW'
                           WHEN 'v' THEN
                            'VIEW'
                           WHEN 'c' THEN
                             'TYPE' 
                           WHEN 'i' THEN
                            'INDEX'
                           WHEN 'I' THEN
                            'PARTITIONED INDEX'
                           WHEN 'L' THEN
                            'SEQUENCE' 
                           WHEN 'S' THEN
                            'SEQUENCE'
                       END "TYPE",
                       pg_has_role(tbl.relowner, 'USAGE'::text) OR has_table_privilege(tbl.oid, 'SELECT'::text) "GRANTED",
                       tbl.oid,'pg_class' clz
                FROM   pg_class tbl
                JOIN   pg_namespace nsp ON nsp.oid = tbl.relnamespace
                WHERE  nspname IN @schemas@
                UNION ALL
                SELECT nspname,proname,'FUNCTION',
                       pg_has_role(p.proowner, 'USAGE'::text) OR has_function_privilege(p.oid, 'EXECUTE'::text),
                       p.oid,'pg_proc'
                FROM   pg_proc p
                JOIN   pg_namespace n ON n.oid = p.pronamespace
                WHERE  LOWER(nspname) IN @schemas@
            ) M]]):gsub('@schemas@',sys_schemas)
        local rows=db:get_rows(sql)
        for _,obj in ipairs(rows) do
            local item={object_owner=obj[1],object_name=obj[2],object_type=obj[3],granted=obj[4],object_id=obj[5],object_class=obj[6]}
            for _,n in ipairs{obj[2]:lower(),(obj[1]..'.'..obj[2]):lower()} do
                if not cache_obj[n] then cache_obj[n]=item end
            end
        end
        db.C.dict.cache_obj=cache_obj
        loaded=true
    end
    local item=cache_obj[name]
    if not item and obj~="" then
        if not name:find('.',1,true) then name='%.'..name end
        local result=self:exec_cache(stmt,{obj=name},'Internal_FindObject')
        local obj=db.resultset:rows(result,-1,'')[2]
        if obj then
            item={object_owner=obj[1],object_name=obj[2],object_type=obj[3],granted=obj[4],object_id=obj[5],object_class=obj[6]}
        end
    end

    if item then 
        item.target=obj_name
        item.full_name=table.concat({item.object_owner,item.object_name},'.')
        item.object_fullname='"'..item.object_owner..'"."'..item.object_name..'"'
        cache_obj[obj_name],cache_obj[item.full_name:lower()]=item,item 
    end

    if is_set_env then
        for k,v in pairs(default_args) do
            if k:find('^object') then env.var.setInputs(k:upper(),item and item[k] or db.NOT_ASSIGNED) end
        end
    end

    env.checkerr(bypass_error=='1' or bypass_error=='true' or item~=nil,'Cannot find target object: '..obj_name)
    return item
end

local privs={}
function db:check_access(obj_name,is_set_env,is_cache)
    local obj=cache_obj[obj_name] or privs[obj_name]
    if obj~=nil then
        if type(obj)=="table" and obj.accessible then 
            return obj.accessible==1
        elseif type(obj)=="number" then
            return obj==1
        end
    end

    obj=self:check_obj(obj_name,'1',is_set_env)
    if not obj then
        if is_cache==true then privs[obj_name]=0 end
        return false 
    end
    
    return obj.granted
end

function db:check_function(func_name)
    func_name=func_name:upper()
    local func=cache_obj['#'..func_name]
    if not func then
        local err,msg=pcall(db.internal_call,db,'SELECT '..func_name..'()')
        if not err and msg:find('1305') then err=true end
        func={accessible=err and 1 or 0}
        cache_obj['#'..func_name]=func
    end
    return func.accessible==1
end

local url,usr
function findobj.onreset(instance,sql,props)
    if props and (props.url~=url or props.user~=usr)  then
        url,usr=props.url,props.user
        cache_obj,privs,loaded=nil,{}
    end
end

function findobj.onload()
    env.set_command(db,"FINDOBJ","#internal",db.check_obj,false,4)
    env.event.snoop("AFTER_PGSQL_CONNECT",findobj.onreset)
end

return findobj