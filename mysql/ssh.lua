local env=env
local db=env.mysql
local ssh=env.class(env.ssh)
function ssh:ctor()
    self.script_dir=env.WORK_DIR.."mysql"..env.PATH_DEL.."shell"
end

function ssh:open_ssh(db,sql,args,result)
    
end

function ssh:set_ssh()
    
end

function ssh:onload()
    
end

function ssh:onunload()
end

return ssh.new()