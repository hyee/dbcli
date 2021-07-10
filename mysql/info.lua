local env,db=env,env.getdb()
local info={}

local header="| %s `%s`.`%s`%s |"
function info.desc(name,option)
	env.checkhelp(name)
    local rs,success,err
    local obj=db:check_obj(name,nil,true)
    local file=env.join_path(db.ROOT_PATH,'cmd','info.'..obj.object_type:lower()..'.sql')
    env.checkerr(os.exists(file),"Describing "..obj.object_type:lower()..' is unsupported.')
    env.set.doset("feed","off","autohide","all","HEADSTYLE","initcap")
    local name=header:format(obj.object_type,obj.object_owner,obj.object_name,#(obj.object_subname or '')>0 and ('['..obj.object_subname..']') or '')
    print(table.concat({string.rep("=",#name),name,string.rep("=",#name),''},'\n'))
    db.C.sql:run_script('@'..file)
end

function info:onload()
	env.set_command(nil,'info','Describe database object. Usage: @@NAME [owner.]<object>[.<partition>] [all]',info.desc,false,3)
end
return info