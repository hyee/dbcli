local env=env

local cmd=env.class(env.subprocess)

function cmd:ctor()
    self:start("c:\\soft\\putty\\plink",{"-pw","gbalmus1","gbalmus@almuatc1.uk"},false)
end


function cmd:onload()
    env.set_command(self,'cmd',"run command",self.exec,false,2)
end

return cmd.new()