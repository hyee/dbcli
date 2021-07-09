local env,db=env,env.getdb
local info={}

function info.desc(name,option)
	env.checkhelp(name)
    set.set("autohide","on")
    local rs,success,err
    local obj=db:check_obj(name)
end
function info:onload()
	env.set_command(nil,'info','Describe database object. Usage: @@NAME [owner.]<object>[.<partition>] [all]',info.desc,false,3)
end
return info