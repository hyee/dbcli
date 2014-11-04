local string,io=string,io
local dir=debug.getinfo(1).short_src:gsub('%w+%.lua','?.lua')
package.path=dir
io.stdout:write("    ------------------------------------------------------------------------------------------------------------------------\n")
io.stdout:write("    | RDBMS utility(DBCLI), type 'help' for more information. (c)2014-2015 hyee, MIT license(https://github.com/hyee/dbcli)|\n")
io.stdout:write("    ========================================================================================================================\n\n")

local env=require("env")
env.onload(...)  

--start the CLI interpretor

local line,eval,prompt = "",env.eval_line
local reader=reader
local ansi=env.ansi
local color=ansi.get_color	
reader:setExpandEvents(false)
local prompt_color="%s%s"..color("NOR").."%s"
local write=function(str)
	--print(ansi.cfg("PROMPTCOLOR"))
	str=prompt_color:format(color("PROMPTCOLOR"),str,color("COMMANDCOLOR"))
	if prompt~=str then
		prompt=str
		reader:setPrompt(str)
	end
end


while true do
    if env.CURRENT_PROMPT=="_____EXIT_____" then break end
    write(env.CURRENT_PROMPT)
    line = reader:readLine()  
    if not line or line:lower() == 'quit' or line:lower() == 'exit' then
    	print("Exited.")
    	env.unload()    	
    	os.exit(1) 
    end
    eval(line) 
end
