local env=env
local system=env.class(env.scripter)
local winapi=require("winapi")


function system:ctor(name,cmd)
    self.shell=name
    self.handle=nil
    self.process=nil
end

function system:fetch_msg(is_print)

end

function system:open(...)
    if not self.handle then
        env.find_extension(self.shell)
        local cmd=table.concat({self.shell,...}," ")
        self.process,self.handle=winapi.spawn_process(cmd)
        env.checkerr(self.process,self.handle)
        self.handle:read()
    end
end

function system:__onload()

end

return system