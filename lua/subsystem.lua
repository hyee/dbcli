local env=env
local system=env.class(env.scripter)
local winapi=require("winapi")


function system:ctor(name,cmd)
    self.shell=name
    self.handle=nil
    self.process=nil
end

function system:run_command(cmd,is_print)
    self.handle:write(cmd.."\n")
    local txt,prompt
    while true do
        txt=file:read()
        prompt=txt:match("([^\n\r])+[>$#]%s+$")
        if prompt then break end
    end
    env.set_subsystem(self.shell,prompt)
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