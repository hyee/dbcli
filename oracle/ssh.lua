local env=env
local ssh=env.class(env.ssh)
function ssh:ctor()
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."ora",{}
end

function ssh:onload()
end


function ssh:onunload()
end


return ssh.new()