local env,select,table,pcall=env,select,table,pcall
local writer,reader=writer,reader
local out=writer
local event
local printer={rawprint=print}
local io=io
local NOR,BOLD="",""
local strip_ansi=function(x) return x end

function printer.load_text(text)
    printer.print(event.callback("BEFORE_PRINT_TEXT",{text or ""})[1])
end

local more_text
function printer.set_more(stmt)
    env.checkerr(stmt,"Usage: more <select statement>|<other command>")
    printer.is_more=true
    more_text={}
    local res,err=pcall(env.eval_line,stmt,true,true)
    printer.is_more=false
    printer.more(table.concat(more_text,'\n'))
    more_text={}
end

function printer.more(output)
    local width=(terminal:getWidth()/2+5)
    local list = java.new("java.util.ArrayList")
    for v in output:gsplit('\r?\n') do
        if v:len()<width then v=v..string.rep(" ",width-v:len()) end
        list:add(v)
    end
    reader:setPaginationEnabled(true)
    reader:printColumns(list)
    reader:setPaginationEnabled(false)
end

function printer.print(...)
    local output,found,ignore={NOR,env.space:sub(1,#env.space-2)}
    local fmt=(env.ansi and env.ansi.get_color("GREPCOLOR") or '')..'%1'..NOR
    for i=1,select('#',...) do
        local v=select(i,...)
        if v~='__BYPASS_GREP__' then 
            output[i+2]=v==nil and "nil" or tostring(v)
        else
            ignore=true
        end
    end
    output=table.concat(output,' '):gsub("(\r?\n\r?)","%1"..env.space)--:gsub('`([^\n\r]+)`',env.ansi.get_color("PROMPTCOLOR")..'%1'..NOR)
    if printer.grep_text and not ignore then
        local stack=output:split('[\n\r]+')
        output={}
        for k,v in ipairs(stack) do
            v,found=v:gsub(printer.grep_text,fmt)
            if found>0 and not printer.grep_dir or printer.grep_dir and found==0 then
                output[#output+1]=v
            end
        end
        output=table.concat(output,'\n')
    end
    if env.ansi then output=env.ansi.convert_ansi(output) end
    if printer.is_more then more_text[#more_text+1]=output;return end
    if ignore or output~="" or not printer.grep_text then
        out:println(output)
        out:flush()
        if printer.hdl then
            pcall(printer.hdl.write,printer.hdl,strip_ansi(output).."\n")
        end
    end
end

function printer.write(output)
    --if env.ansi then output=env.ansi.convert_ansi(output) end
    out:write(output)
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

function printer.set_grep(keyword)
    printer.grep_text,printer.grep_dir=nil,nil
    if keyword:len()>1 and keyword:sub(1,1)=="-" then
        keyword,printer.grep_dir=keyword:sub(2),true
    end
    --printer.grep_text=keyword:escape():case_insensitive_pattern()
    printer.grep_text='('..keyword:escape():case_insensitive_pattern()..')'
end

function printer.grep(keyword,stmt)
    env.checkhelp(stmt)
    printer.set_grep(keyword)
    env.eval_line(stmt,true,true)
end

function printer.grep_after()
    printer.grep_text,printer.grep_dir=nil,nil
end

function printer.before_command(command)
    if not printer.hdl or #env.RUNNING_THREADS>1 then return end
    local cmd,params,is_internal=table.unpack(command)
    if is_internal then return end
    local line= (env._CMDS[cmd] and env._CMDS[cmd].ARGS>1 and cmd.." ") or ""
    line=line..table.concat(params," "):gsub('\n','\n'..env.MTL_PROMPT)
    line=env.PRI_PROMPT..line
    pcall(printer.hdl.write,printer.hdl,line.."\n")
end

function printer.after_command()
    if not printer.grep_text or #env.RUNNING_THREADS>1  then return end
    printer.grep_after()
end


_G.print=printer.print
_G.rawprint=printer.rawprint

function printer.onload()
    if env.ansi then
        NOR = env.ansi.string_color('NOR') 
        BOLD= env.ansi.string_color('UDL') 
        strip_ansi=env.ansi.strip_ansi
    end
    event=env.event
    if env.event then
        env.event.snoop('BEFORE_COMMAND',printer.before_command,nil,90)
        env.event.snoop('AFTER_COMMAND',printer.after_command,nil,90)
    end
    BOLD=BOLD..'%1'..NOR
    
    env.set_command(nil,"grep","Filter matched text from the output. Usage: grep <keyword|-keyword> <other command>, -keyword means exclude",{printer.grep,printer.grep_after},'__SMART_PARSE__',3)
    env.set_command(nil,"more","Similar to Linux 'more' command. Usage: more <other command>",printer.set_more,'__SMART_PARSE__',2)
    env.set_command(nil,{"Prompt","pro",'echo'}, "Prompt messages. Usage: PRO[MPT] <message>",printer.load_text,false,2)
    env.set_command(nil,{"SPOOL","SPO"}, "Write the screen output into a file. Usage: SPO[OL] [file_name[.ext]] [CREATE] | APP[END]] | OFF]",printer.spool,false,3)
    env.ansi.define_color("GREPCOLOR","BBLU;HIW","ansi.grid","Define highlight color for the grep command, type 'ansi' for more available options")
end
return printer
