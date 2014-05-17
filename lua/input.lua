
local dir=debug.getinfo(1).short_src:gsub('%w+%.lua','?.lua')
package.path=dir

local env=require("env")
env.onload(...)  

--start the CLI interpretor


--[[
local reader=java.system['in']
local r=java.require("java.io.InputStreamReader"):new(reader,"UTF-8")
reader=java.require('java.io.BufferedReader'):new(r)
]]--
local line,eval = "",env.eval_line
while true do
    io.write(env.CURRENT_PROMPT) 
    line = io.stdin:read()  --reader:readLine()  
    if not line or line:lower() == 'quit' or line:lower() == 'exit' then
    	env.unload()
    	os.exit(1) 
    end
    eval(line) 
end
