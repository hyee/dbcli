local loader,env=loader,env
local ssh=env.class()

function ssh:ctor() 
end

function ssh:start(cmd)
    if self.commander then self.commander:close() end
    self.commander=loader:newExtProcess(cmd)
end

function ssh:connect(user,pwd,host,port)
    local cmd='"%sbin%sPLink.exe" -pw %s -P %d %s@%s'
    cmd=cmd:format(env.WORK_DIR,env.PATH_DEL,pwd,tonumber(port) or 22,user,host)
    print(cmd)
    self:start(cmd)
end

function ssh:exec(line)
    self.commander:exec(line)
end

function ssh:close()
    self.commander:close()
    self.commander=nil
end

function ssh:command(cmd)
    local usr,pwd,host,port=cmd:match('^(.*)/(.*)@([^:]+):?(%d*)$')
    print(usr,pwd,host,port)
    env.checkerr(usr or self.commander,"SSH server is not connected, please login firstly.")
    if usr then return self:connect(usr,pwd,host,port) end
    self:exec(cmd)
end

function ssh:onload()
    env.set_command(self,'ssh',"SSH to remote server. Usage: ssh <user/password@host[:port] | shell command>",self.command,false,2)
end

function ssh:onunload()
    if self.commander then self.commander:close() end
end

return ssh.new()