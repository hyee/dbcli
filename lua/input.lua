local string,io=string,io
local dir=debug.getinfo(1).short_src:gsub('%w+%.lua','?.lua')
package.path=dir

local env=require("env")
env.onload(...)  

--start the CLI interpretor

local reader,writer,write=reader,writer
local line,eval,prompt = "",env.eval_line

--If jline compnent is exists
if reader then
	local jline=env.jline
	local color=jline.get_color	
	reader:setExpandEvents(false)
	local prompt_color="%s%s"..color("NOR").."%s"
	write=function(str)
		str=prompt_color:format(color("PROMPT_COLOR"),str,color("COMMAND_COLOR"))
		if prompt~=str then
			prompt=str
			reader:setPrompt(str)
		end
	end
else
	reader=java.system['in']
	local r=java.require("java.io.InputStreamReader"):new(reader,"UTF-8")
	reader=java.require('java.io.BufferedReader'):new(r)
	write=function(str)
		io.stdout:write(str)
	end
end

while true do
    write(env.CURRENT_PROMPT)
    line = reader:readLine()  
    if not line or line:lower() == 'quit' or line:lower() == 'exit' then
    	print("Exited.")
    	env.unload()    	
    	os.exit(1) 
    end
    eval(line) 
end
