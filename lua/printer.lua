local env,select,table,pcall=env,select,table,pcall
local event
local writer,reader=writer,reader
local out=writer
local printer={rawprint=print}
local io=io
local NOR=""
local strip_ansi

function printer.load_text(text)
    printer.print(event.callback("BEFORE_PRINT_TEXT",{text or ""})[1])
end

local more_text
function printer.set_more(stmt)
    env.checkerr(stmt,"Usage: more <select statement>|<other command>")
    printer.is_more=true
    more_text={}
    local res,err=pcall(env.internal_eval,stmt)
    printer.is_more=false
    printer.more(table.concat(more_text,'\n'))
    more_text={}
end

function printer.more(output)
    local width=(terminal:getWidth()/2+5)
    local list = java.new("java.util.ArrayList")
    for v in output:gsplit('\n') do
        if v:len()<width then v=v..string.rep(" ",width-v:len()) end
        list:add(v)
    end
    reader:setPaginationEnabled(true)
    reader:printColumns(list)
    reader:setPaginationEnabled(false)
end

function printer.print(...)
    local output={NOR,env.space:sub(1,#env.space-2)}
    for i=1,select('#',...) do
        local v=select(i,...)
        output[i+2]=v==nil and "nil" or tostring(v)
    end
    output=table.concat(output,' '):gsub("(\r?\n\r?)","%1"..env.space)
    if env.ansi then output=env.ansi.convert_ansi(output) end
    if printer.is_more then more_text[#more_text+1]=output;return end
    --printer.rawprint(output)
    out:println(output)
    out:flush()
    if printer.hdl then
        pcall(printer.hdl.write,printer.hdl,strip_ansi(output).."\n")
    end
end

function printer.write(output)
    if env.ansi then output=env.ansi.convert_ansi(output) end
    out:write(env.space..output)
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
    NOR=env.ansi and env.ansi.string_color('NOR') or ''
    event=env.event
    strip_ansi=env.ansi and env.ansi.strip_ansi or function(x) return x end
end

function printer.spool(file,option)
    option=option and option:upper() or "CREATE"
    if not file then
        if printer.hdl then
            printer.rawprint(env.space..'Output is writing to "'..printer.file..'".')
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
