local env=env
local ssh=env.class(env.ssh)
function ssh:ctor()
    self.script_dir=env.getdb().ROOT_PATH.."shell"
end

function ssh:onload()
end


function ssh:onunload()
end


return ssh.new()