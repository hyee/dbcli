local env,db=env,env.getdb()
local info={}

local header='| %s "%s"."%s"%s |'
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
    
    local name=header:format(obj.object_type,obj.object_owner,obj.object_name,#(obj.object_subname or '')>0 and ('['..obj.object_subname..']') or '')
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
                return rs.load_sql(file:gsub(rs.object_type:lower():gsub(' ','_')..'$',target:lower()..'.lua'))
            end
            sqls=rs.load_sql(file..'.lua')
            env.checkerr(type(sqls)=='table' or type(sqls)=='string',"Describing "..rs.object_type..' returns no result.')
            for _,sql in ipairs(type(sqls)=='string' and {sqls} or sqls) do
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
    env.checkerr(os.exists(file),"Extracting the "..option.." of `"..obj.object_type..'` is unsupported.')
end

function info:onload()
    env.set_command(nil,{'desc','describe'},'Describe database object. Usage: @@NAME [owner.]<object>[.<partition>] [ddl]',info.desc,false,3)
end
return info