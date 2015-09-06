local env=env
local event
local writer,reader=writer,reader
local out=writer
local printer={rawprint=print}
local io=io
local NOR=""
local strip_ansi
local space=env.space

function printer.load_text(text)
    printer.print(event.callback("BEFORE_PRINT_TEXT",{text or ""})[1])
end

function printer.set_more(stmt)
    env.checkerr(stmt,"Usage: more <select statement>")
    printer.is_more=true
    local res,err=pcall(env.internal_eval,stmt)    
    printer.is_more=false
    if not res then
        result=tostring(result):gsub(".*000%-00000%:","")
        if result~="" then print(result) end
    end
end

function printer.more(output)
    local list = java.new("java.util.ArrayList")
    for v in output:gsplit('\n') do
        list:add(v)
    end
    reader:setPaginationEnabled(true)
    reader:printColumns(list)
end

function printer.print(...)    
    local output=""
    table.foreach({...},function(k,v) output=output..tostring(v)..' ' end)
    output=NOR..space..output:gsub("(\r?\n\r?)","%1"..space)
    if printer.is_more then return printer.more(output) end
    out:println(output)
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
    if env.ansi and env.ansi.ansi_mode=="ansicon" then out=java.system.out end
    event=env.event
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
        file=env._CACHE_PATH..file
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
env.set_command(nil,"more","Similar to Linux 'more' command. Usage: more <other command>",printer.set_more,'__SMART_PARSE__',2)
env.set_command(nil,{"Prompt","pro"}, "Prompt messages. Usage: PRO[MPT] <message>",printer.load_text,false,2)
env.set_command(nil,{"SPOOL","SPO"}, "Write the screen output into a file. Usage: SPO[OL] [file_name[.ext]] [CREATE] | APP[END]] | OFF]",printer.spool,false,3)
return printer
