local env=env

local ssh=env.class(env.subprocess)

function ssh:ctor()
    --self:start("c:\\soft\\putty\\plink",{"-pw","gbalmus1","gbalmus@almuatc1.uk"},false)
end

 
function ssh:onload()
    --env.set_command(self,'cmd',"run command",self.exec,false,2)
end

return ssh.new()