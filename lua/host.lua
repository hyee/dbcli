local env,os=env,os
function run_command(cmd)
    if not cmd then return end
    io.flush()
    os.execute(cmd)
end

env.set_command(nil,{'HOST','HOS'},"Run OS command. Usage: HOST <command>",run_command,false,2)
return run_command