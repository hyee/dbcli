local env,os=env,os
function run_command(...)
	io.flush()
	os.execute(...)
end

env.set_command(nil,'HOST',"Run OS command. Usage: HOST <command>",run_command,false,2)
return run_command