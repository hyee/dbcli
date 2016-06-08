local string,io,table=string,io,table
package.path=debug.getinfo(1, "S").source:sub(2):gsub('[%w%.]+$','?.lua')
io.stdout:write("    --------------------------------------------------------------------------------------------------------------------------------------\n")
io.stdout:write("    | DBCLI, type 'conn' to connect to db, or 'help' for more information. (c)2014-2016 hyee, MIT license (https://github.com/hyee/dbcli)|\n")
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

local stack=nil

function env.reset_input(line)
    if not stack or not line then return nil end
    if not line:find('^[ \t]*$') then stack[#stack+1]=line end
    if env.CURRENT_PROMPT~=env.MTL_PROMPT then
        if line:find('^[ \t]*'..env.END_MARKS[1]..'[ \t]*$') then
            stack[#stack-1]=stack[#stack-1]..line
            table.remove(stack)
        end
        line=table.concat(stack,'\n'..env.MTL_PROMPT)
        reader:setMultiplePrompt(#stack==1 and line or "")
        stack=nil
    end
end

while true do
    if env.REOAD_SIGNAL then return end
    line = reader:readLine(prompt_color:format(env._SUBSYSTEM and color("PROMPTSUBCOLOR") or color("PROMPTCOLOR"),env.CURRENT_PROMPT,color("COMMANDCOLOR")))
    if not line then
        print("Exited.")
        env.unload()
        os.exit(0,true)
    end

    eval(line)

    if env.CURRENT_PROMPT==env.MTL_PROMPT and not stack then
        stack={line}
        reader:setMultiplePrompt(nil)
    elseif stack then
        env.reset_input(line)
    end

end