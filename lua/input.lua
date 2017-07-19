local string,io,table=string,io,table

package.path=debug.getinfo(1, "S").source:sub(2):gsub('[%w%.]+$','?.lua')
local console=console


local readLine=console.readLine
local env=require("env")
env.onload(...)
print("--------------------------------------------------------------------------------------------------------------------------------------")
print("| DBCLI, type 'conn' to connect to db, or 'help' for more information. (c)2014-2016 hyee, MIT license (https://github.com/hyee/dbcli)|")
print("======================================================================================================================================")
if console:getBufferWidth()<=terminal:getWidth()+1 then
	print("* Your terminal doesn't support horizontal scroll, lines longer than screen width default to be chopped.")
	print("  Please run 'set linesize <cols>' to a larger value if preferred folding the long lines rather than chopping.")
end
print()
--start the CLI interpretor

local line,eval = "",env.execute_line
local ansi,event=env.ansi,env.event
local color=ansi and ansi.get_color or function() return "";end
local prompt_color="%s%s%s%s"
local ncolor=color("NOR")

while true do
    local subcolor,pcolor,ccolor=color("PROMPTSUBCOLOR"),color("PROMPTCOLOR"),color("COMMANDCOLOR")
    local prompt,empty=env.CURRENT_PROMPT:match("^(.-)(%s*)$")
    if env.RELOAD_SIGNAL~=nil then
        _G['REOAD_SIGNAL'],env=env.RELOAD_SIGNAL,nil
        break 
    end
    if ccolor=="" then ccolor="\27[0m" end
    line=readLine(console,prompt_color:format(env._SUBSYSTEM and subcolor or pcolor,prompt,ncolor,empty),ccolor)
    if line then
        eval()
    else
        env.eval_line('exit')
    end
end