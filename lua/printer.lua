local env=env

local writer=writer
local out=writer
local printer={rawprint=print}
local io=io
if not out then out=java.system.out end
local NOR=""
local strip_ansi
local space=env.space

function printer.print(...)    
    local output=""
    table.foreach({...},function(k,v) output=output..tostring(v)..' ' end)
    output=space..output:gsub("(\r?\n\r?)","%1"..space)    
    out:println(NOR..output)
    out:flush()
    if printer.hdl then
        pcall(printer.hdl.write,printer.hdl,strip_ansi(output).."\n")
    end
end

function printer.write(output)
    out:write(space..output)
    out:flush()
end

function printer.onunload()
    printer.print=printer.rawprint
    _G.print=printer.print
    if printer.hdl then
        pcall(printer.hdl.close,printer.hdl)
        printer.hdl=nil
        printer.file=file
    end
end

function printer.onload()    
    NOR=env.ansi and env.ansi.color['NOR'] or ''
    strip_ansi=env.ansi and env.ansi.strip_ansi or function(x) return x end 
end    

function printer.spool(file,option)
    option=option and option:upper() or "CREATE"
    if not file then
        if printer.hdl then 
            printer.rawprint(space..'Output is writing to "'..printer.file..'".') 
        else
            print("SPOOL is OFF.")
        end
        return
    end
    if file:upper()=="OFF" or option=="OFF" or printer.hdl then
        if printer.hdl then pcall(printer.hdl.close,printer.hdl) end
        printer.hdl=nil
        printer.file=nil
        if file:upper()=="OFF" or option=="OFF" then return end
    end
    local err
    if not file:find("[\\/]") then
        file=env.WORK_DIR..'cache'..env.PATH_DEL..file
    end
    printer.hdl,err=io.open(file,(option=="APPEND" or option=="APP" ) and "a+" or "w")
    if not printer.hdl then
        print("Failed to open the target file :"..file)
        return
    end
    printer.file=file
end

_G.print=printer.print
_G.rawprint=printer.rawprint
env.set_command(nil,{"Prompt","pro"}, "Prompt messages. Usage: PRO[MPT] <message>",printer.print,false,2)
env.set_command(nil,{"SPOOL","SPO"}, "Stores query results in a file. Usage: SPO[OL] [file_name[.ext]] [CREATE] | APP[END]] | OFF]",printer.spool,false,3)
return printer
