local env,os=env,os
local host={}
local console,suspend=console,console.suspend
function host.run_command(cmd)
    env.checkhelp(cmd)
    io.flush()
    suspend(console,true)
    local rtn,exit,signal=os.execute(cmd)
    suspend(console,false)
end

function host.mkdir(path)
    loader:mkdir(path)
end

env.set_command({nil,{'HOST','HOS','!'},"Run OS command. Usage: @@NAME <command>",host.run_command,false,2,is_blocknewline=true})
return host