local string=string
local dir=debug.getinfo(1).short_src:gsub('%w+%.lua','?.lua')
package.path=dir

local env=require("env")
env.onload(...)  

--start the CLI interpretor

local reader,writer,write=reader,writer
local line,eval,prompt = "",env.eval_line

--If jline compnent is exists
if reader then
	local prompt_color="\27[33m%s\27[0m"
	reader:setExpandEvents(false)
	write=function(str)
		if prompt~=str then
			prompt=str
			reader:setPrompt(prompt_color:format(str))
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
    	env.unload()
    	os.exit(1) 
    end
    eval(line) 
end
