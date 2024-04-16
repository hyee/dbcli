local env=env
local db=env.getdb()

local show={name="SHOW"}

function show.run(arg)
    db:assert_connect()
    env.set.set("printsize",10000)
    env.set.set("feed","off")
    env.set.set("AUTOHIDE","col")
    env.var.define_column("category","noprint")
    if not arg then
        return db:query("select * from pg_settings where source!='default'")
    end;
    local cmd="SHOW ALL"
    local flag=arg:lower()=="all" and true or false
    
    if not flag then 
        cmd="select * from pg_settings where name!='logging_module' and lower(concat('|',name,'|',setting,'|',short_desc,'|',extra_desc)) like lower('%"..arg.."%')"
    end
    db:query(cmd)
end


function show.onload()
    env.set_command(nil,show.name, "show the value of a run-time parameter. Usage: @@NAME [<keyword>|all]",show.run,false,2)
end

return show