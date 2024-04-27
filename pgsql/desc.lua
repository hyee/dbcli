local env,db=env,env.getdb()
local info={}

local header='| %s "%s"."%s"%s (oid = %s)|'
function info.desc(name,option)
    env.checkhelp(name)
    env.checkerr((option or 'ddl'):lower()=='ddl','Unsupported parameter: '..(option or 'ddl'))
    local rs,success,err
    local obj=db:check_obj(name,nil,true)
    local options={'desc','ddl'}
    if (option or 'desc'):lower()=='ddl' then
        table.remove(options,1)
    end

    env.set.doset("feed","off","autohide","all","headstyle","initcap","internal","on","verify","off")
    
    local name=header:format(obj.object_type,
                             obj.object_owner,
                             obj.object_name,
                             #(obj.object_subname or '')>0 and ('['..obj.object_subname..']') or '',
                             tostring(obj.object_id or 'unknown'))
    print(table.concat({string.rep("=",#name),name,string.rep("=",#name),''},'\n'))
    for _,option in ipairs(options) do
        local file=env.join_path(db.ROOT_PATH,'cmd',option..'.'..obj.object_type:lower():gsub(' ','_'))
        if os.exists(file..'.lua') then
            local rs,sqls=table.clone(obj)
            rs.load_sql=function(file,func)
                local res,rtn
                res,rtn=loadfile(file,'bt',{env=env,db=db,obj=rs,file=file})
                if type(res)=='function' then
                    res,rtn=env.pcall(res)
                end
                env.checkerr(res,'Error on executing '..tostring(rtn):gsub(env.WORK_DIR,""))
                return rtn or res
            end
            rs.redirect=function(target)
                local target=file:gsub(rs.object_type:lower():gsub(' ','_')..'$',target:lower())
                local _,file1
                if not os.exists(target) then
                    _,file1=os.exists(target..'.lua')
                    if not file1 then
                        _,file1=os.exists(target..'.sql')
                    end
                    if file1 then target=file1 end
                end
                env.checkerr(target,"No such file: %s[.lua|.sql]",target)
                if target:find('.lua',1,true) then
                    return rs.load_sql(target)
                else
                    db.C.sql:run_script('@'..target)
                end
            end
            sqls=rs.load_sql(file..'.lua')
            for _,sql in ipairs(type(sqls)=='string' and {sqls} or type(sqls)=='table' and sqls or {}) do
                local title=sql:match('/%*TOPIC=([^%*/]+)%*/')
                if title then
                    print(title..':')
                    print(string.rep("=",#title+1))
                end
                env.set.set("COLWRAP",120)
                env.set.set("PIVOT",sql:sub(1,256):find("/*PIVOT*/",1,true) and 1 or 0)
                db:internal_call(sql,rs,nil,nil,true)
                env.set.set("PIVOT",0)
                env.set.set("COLWRAP",'default')
            end
            return
        elseif os.exists(file..'.sql') then
            db.C.sql:run_script('@'..file..'.sql')
            return
        end
    end
    env.checkerr(os.exists(file),"Extracting the "..(option or 'description').." of `"..obj.object_type..'` is unsupported.')
end

function info:onload()
    env.set_command(nil,{'desc','describe'},'Describe database object. Usage: @@NAME [owner.]<object>[.<partition>] [ddl]',info.desc,false,3)
end
return info