local env,os=env,os
local host={}
function host.run_command(cmd)
    env.checkerr(cmd,env.helper.helper,env.CURRENT_CMD)
    io.flush()
    os.execute('"'..cmd..'"')
end

function host.mkdir(path)
    os.execute('mkdir "'..path..'" 2> '..(env.OS=="windows" and 'NUL' or "/dev/null"))
end

env.set_command(nil,{'HOST','HOS','!'},"Run OS command. Usage: HOST <command>",host.run_command,false,2)
return host