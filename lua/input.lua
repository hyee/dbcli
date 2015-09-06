local string,io,table=string,io,table
package.path=debug.getinfo(1).short_src:gsub('[%w%.]+$','?.lua')
io.stdout:write("    --------------------------------------------------------------------------------------------------------------------------------------\n")
io.stdout:write("    | DBCLI, type 'conn' to connect to db, or 'help' for more information. (c)2014-2015 hyee, MIT license (https://github.com/hyee/dbcli)|\n")
io.stdout:write("    ======================================================================================================================================\n\n")

local env=require("env")
env.onload(...)  

--start the CLI interpretor

local line,eval,prompt = "",env.eval_line
local reader=reader
local history=reader:getHistory()
local ansi,event=env.ansi,env.event
local color=ansi and ansi.get_color or function() return "";end
local prompt_color="%s%s"..color("NOR").."%s"

local os,clock=os
local stack=nil
function env.reset_input(line)
    if not stack or not line then return nil end
    if not line:find('^[%s\t]*$') then stack[#stack+1]=line end
    if env.CURRENT_PROMPT==env.PRI_PROMPT then
        if line:find('^[%s\t]*'..env.END_MARKS[1]..'[%s\t]*$') then
            stack[#stack-1]=stack[#stack-1]..line
            table.remove(stack)
        end
        line=table.concat(stack,'\n'..env.MTL_PROMPT)
        reader:setMultiplePrompt(#stack==1 and line or "")
        stack=nil
    end
end

while true do  
    if env.CURRENT_PROMPT=="_____EXIT_____" then break end
    line = reader:readLine(prompt_color:format(env._SUBSYSTEM and color("PROMPTSUBCOLOR") or color("PROMPTCOLOR"),env.CURRENT_PROMPT,color("COMMANDCOLOR")))
    if not line or (line:lower() == 'quit' or line:lower() == 'exit') and not env._SUBSYSTEM then
        print("Exited.")
        env.unload()        
        os.exit(0,true) 
    end

    clock=os.clock(),eval(line)
    
    if env.CURRENT_PROMPT==env.MTL_PROMPT and not stack then
        stack={line}
        reader:setMultiplePrompt(nil)
    elseif stack then
        env.reset_input(line)
    end
  
    if env.PRI_PROMPT=="TIMING> " and env.CURRENT_PROMPT~=env.MTL_PROMPT then
        env.CURRENT_PROMPT=string.format('%06.2f',os.clock()-clock)..'> '
        env.MTL_PROMPT=string.rep(' ',#env.CURRENT_PROMPT)    
    end
end