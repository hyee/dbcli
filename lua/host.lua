local env,os=env,os
local host={}
function host.run_command(cmd)
    env.checkhelp(cmd)
    io.flush()
    os.execute(cmd)
end

function host.mkdir(path)
    loader:mkdir(path)
end

env.set_command(nil,{'HOST','HOS','!'},"Run OS command. Usage: @@NAME <command>",host.run_command,false,2)
return host