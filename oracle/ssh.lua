local env=env
local ssh=env.class(env.ssh)
function ssh:ctor()
    self.script_dir=env.WORK_DIR.."oracle"..env.PATH_DEL.."shell"
end

function ssh:onload()
end


function ssh:onunload()
end


return ssh.new()