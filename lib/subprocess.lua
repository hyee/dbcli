local loader,env=loader,env
local subproc=env.class()

function subproc:ctor(cmd)
    self.commander=loader:newExtProcess(cmd)
end


function subproc:exec(line)
    self.commander:exec(line)
end

function subproc:close()
    self.commander:close()
end


return subproc