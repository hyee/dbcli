local string,io,table=string,io,table
package.path=debug.getinfo(1, "S").source:sub(2):gsub('[%w%.]+$','?.lua')
io.stdout:write("    --------------------------------------------------------------------------------------------------------------------------------------\n")
io.stdout:write("    | DBCLI, type 'conn' to connect to db, or 'help' for more information. (c)2014-2016 hyee, MIT license (https://github.com/hyee/dbcli)|\n")
io.stdout:write("    ======================================================================================================================================\n\n")
local console=console
local readLine=console.readLine
local env=require("env")
env.onload(...)

--start the CLI interpretor

local line,eval = "",env.execute_line
local ansi,event=env.ansi,env.event
local color=ansi and ansi.get_color or function() return "";end
local prompt_color="%s%s%s%s"
local ncolor=color("NOR")

while true do
    local subcolor,pcolor,ccolor=color("PROMPTSUBCOLOR"),color("PROMPTCOLOR"),color("COMMANDCOLOR")
    local prompt,empty=env.CURRENT_PROMPT:match("^(.-)(%s*)$")
    if env.REOAD_SIGNAL then break end
    if ccolor=="" then ccolor="\27[0m" end
    readLine(console,prompt_color:format(env._SUBSYSTEM and subcolor or pcolor,prompt,ncolor,empty),ccolor)
    if not line then
        env.eval_line('exit')
    end
    eval()
end