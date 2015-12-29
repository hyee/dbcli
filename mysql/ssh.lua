local env=env
local db=env.getdb()
local ssh=env.class(env.ssh)
function ssh:ctor()
    self.script_dir=db.ROOT_PATH.."shell"
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