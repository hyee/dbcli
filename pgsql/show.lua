local env=env
local db=env.getdb()

local show={name="SHOW"}

function show.run(arg)
    env.checkhelp(arg)
    db:assert_connect()
    local cmd="SHOW ALL"
    local flag=arg:lower()=="all" and true or false
    env.set.set("printsize",10000)
    env.set.set("feed","off")
    if not flag then env.printer.set_grep(arg) end
    db:query(cmd)
    if not flag then env.printer.grep_after() end
end


function show.onload()
    env.set_command(nil,show.name, "show the value of a run-time parameter. Usage: @@NAME [<keyword>|all]",show.run,false,2)
end

return show