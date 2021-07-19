local env,db=env,env.getdb()
local info={}

local header="| %s `%s`.`%s`%s |"
function info.desc(name,option)
    env.checkhelp(name)
    env.checkerr((option or 'ddl'):lower()=='ddl','Unsupported parameter: '..(option or 'ddl'))
    local rs,success,err
    local obj=db:check_obj(name,nil,true)
    option=(option or 'info'):lower()
    local file=env.join_path(db.ROOT_PATH,'cmd',option..'.'..obj.object_type:lower()..'.sql')
    env.checkerr(os.exists(file),"Extracting the "..option.." of `"..obj.object_type..'` is unsupported.')
    env.set.doset("feed","off","autohide","all","headstyle","initcap","internal","on","verify","off")
    local name=header:format(obj.object_type,obj.object_owner,obj.object_name,#(obj.object_subname or '')>0 and ('['..obj.object_subname..']') or '')
    print(table.concat({string.rep("=",#name),name,string.rep("=",#name),''},'\n'))
    db.C.sql:run_script('@'..file)
end

function info:onload()
    env.set_command(nil,'info','Describe database object. Usage: @@NAME [owner.]<object>[.<partition>] [ddl]',info.desc,false,3)
end
return info