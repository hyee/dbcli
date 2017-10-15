local env,select,table,pcall=env,select,table,pcall
local writer,reader,console=writer,reader,console
local out=writer
local jwriter=jwriter
local event
local printer={rawprint=print}
local io=io
local NOR,BOLD="",""
local strip_ansi=function(x) return x end
local println,write=console.println,console.write

function printer.load_text(text)
    printer.print(event.callback("BEFORE_PRINT_TEXT",{text or ""})[1])
end

local more_text
function printer.set_more(stmt)
    env.checkerr(stmt,"Usage: more <select statement>|<other command>")
    printer.is_more=true
    more_text={}
    if stmt then pcall(env.eval_line,stmt,true,true) end
    printer.is_more=false
    printer.more(table.concat(more_text,'\n'))
    more_text={}
end

function printer.more(output)
    --[[
    local width=(terminal:getWidth()/2+5)
    local list = java.new("java.util.ArrayList")
    for v in output:gsplit('\r?\n') do
        if v:len()<width then v=v..string.rep(" ",width-v:len()) end
        list:add(v)
    end
    reader:setPaginationEnabled(true)
    reader:printColumns(list)
    reader:setPaginationEnabled(false)
    --]]
    local width=terminal:getWidth()
    if console:getBufferWidth() > width and env.grid then
        local tab={}
        local cut=env.grid.cut
        for v in output:gsplit('\r?\n') do
            tab[#tab+1]=cut(v,width-1-#env.space)
        end
        output=table.concat(tab,"\n")
    end
    console:less(output)
end

function printer.rawprint(...)
    local msg={}
    for i=1,select('#',...) do 
        msg[i]=tostring(select(i,...))
    end
    println(console,table.concat(msg," "))
end

function printer.print(...)
    local output,found,ignore={NOR,env.space:sub(1,#env.space-2)}
    local fmt=(env.ansi and env.ansi.get_color("GREPCOLOR") or '')..'%1'..NOR
    for i=1,select('#',...) do
        local v=select(i,...)
        if v~='__BYPASS_GREP__' then 
            output[i+2]=tostring(v)
        else
            ignore=true
        end
    end
    output=table.concat(output,' '):gsub("(\r?\n\r?)","%1"..env.space)
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
        println(console,output)
        if printer.hdl then
            pcall(printer.hdl.write,printer.hdl,strip_ansi(output).."\n")
        end

        if printer.tee_hdl and printer.tee_type~='csv' and printer.tee_type~='html' then
            pcall(printer.tee_hdl.write,printer.tee_hdl,strip_ansi(output).."\n")
        end
    end
end

function printer.write(output)
    if env.ansi then output=env.ansi.convert_ansi(output) end
    write(console,output)
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
            printer.rawprint(env.space..'Output is writting to "'..printer.file..'".')
        else
            print("SPOOL is OFF.")
        end
        return
    end
    if file:upper()=="OFF" or option=="OFF" or printer.hdl then
        if printer.hdl then pcall(printer.hdl.close,printer.hdl) end
        if env.set and env.set.get("feed")=="on" then
            printer.rawprint(env.space..'Output is written to "'..printer.file..'".')
        end
        printer.hdl=nil
        printer.file=nil
        if file:upper()=="OFF" or option=="OFF" then return end
    end
    local err
    if not file:find("[\\/]") then
        file=env._CACHE_PATH..file
    end
    printer.hdl,err=io.open(file,(option=="APPEND" or option=="APP" ) and "a+" or "w")
    env.checkerr(printer.hdl,"Failed to open the target file "..file)
    
    printer.file=file
    if env.set and env.set.get("feed")=="on" then
        printer.rawprint(env.space..'Output is writting to "'..printer.file..'".')
    end
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

function printer.tee(file,stmt)
    env.checkhelp(file)
    local mode='w'
    if not stmt then 
        file,stmt='',file 
    elseif file:sub(1,1)=='+' then
        mode,file='a+',file:sub(2)
    elseif file:sub(-1)=='+' then
        mode,file='a+',file:sub(1,#file-1)
    end
    if file=="" or file=="." then
        file='last_output.txt'
    end
    if not file:find("[\\/]") then
        file=env._CACHE_PATH..file
    end
    printer.tee_file=file
    printer.tee_hdl=io.open(file,mode)
    printer.tee_type=file:lower():match("%.([^%.]+)$")
    if printer.tee_type=='htm' then printer.tee_type='html' end
    env.checkerr(printer.tee_hdl,"Failed to open the target file "..file)
    env.eval_line(stmt,true,true)
end

function printer.tee_after()
    if not printer.tee_hdl then return end
    pcall(printer.tee_hdl.close,printer.tee_hdl)
    printer.rawprint(env.space.."Output is written to "..printer.tee_file)
    printer.tee_file,printer.tee_hdl=nil,nil
end

function printer.before_command(command)
    local cmd,params,is_internal,line,text=table.unpack(command)
    if not printer.hdl or #env.RUNNING_THREADS>1 then return end
    if is_internal then return end
    line=line:gsub('\n','\n'..env.MTL_PROMPT)
    line=env.PRI_PROMPT..line
    pcall(printer.hdl.write,printer.hdl,line.."\n")
end

function printer.after_command()
    if #env.RUNNING_THREADS>1  then return end
    if more_text and #more_text>0 then
       printer.more(table.concat(more_text,'\n')) 
    end
    if printer.grep_text then 
        printer.grep_after()
    end
    if printer.tee_hdl then 
        printer.tee_after()
    end
    printer.is_more,more_text=false,{}
end

function printer.tee_to_file(row,total_rows)
    if not printer.tee_hdl then return end
    local hdl=printer.tee_hdl
    if printer.tee_type=="html" then
        local td='td'
        if(row[0]==0) then
            hdl:write("<table>\n")
            printer.tee_colinfo=row.colinfo
            td='th'
        end
        hdl:write("  <tr>")
        for idx,cell in ipairs(row) do
            hdl:write("<"..td..(printer.tee_colinfo and printer.tee_colinfo[idx].is_number==1 and ' align="right"' or '')..">")
            if type(cell)=="string" then
                hdl:write((cell:gsub("( +)",function(s)
                        if #s==1 then return s end
                        return " "..string.rep('&nbsp;',#s-1)
                    end):gsub("\r?\n","<br/>"):gsub("<",'&lt;'):gsub(">","&gt;")))
            elseif cell~=nil then
                hdl:write(cell)
            end
            hdl:write("</"..td..">")
        end
        hdl:write("</tr>\n")
        if row[0]==total_rows-1 then 
            hdl:write("</table>\n")
            printer.tee_colinfo=nil
        end
    elseif printer.tee_type=="csv" then
        for idx,cell in ipairs(row) do
            if idx>1 then hdl:write(",") end
            if type(cell)=="string" then
                cell=cell:gsub('"','""')
                if cell:find('[",\n\r]') then cell='"'..cell..'"' end
                hdl:write(cell)
            elseif cell~=nil then
                hdl:write(cell)    
            end
        end
        hdl:write("\n")
    end
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
        env.event.snoop('ON_PRINT_GRID_ROW',printer.tee_to_file,nil,90)
    end
    BOLD=BOLD..'%1'..NOR
    local tee_help=[[
    Write command output to target file,'+' means append mode. Usage: @@NAME {+|.|[+]<file>|<file>+} <other command>
        or <other command>|@@NAME {+|.|[+]<file>|<file>+}
    When <other command> is a query, then the output can be same to the screen output/csv file/html file which depends on the file extension. ]]

    local grep_help=[[
    Filter matched text from the output. Usage: @@NAME <keyword|-keyword> <other command>, -keyword means exclude.
        or <other command>|@@NAME <keyword|-keyword>
    ]]
    env.set_command(nil,"grep",grep_help,{printer.grep,printer.grep_after},'__SMART_PARSE__',3,false,false,true)
    env.set_command(nil,"tee",tee_help,{printer.tee,printer.tee_after},'__SMART_PARSE__',3,false,false,true)
    env.set_command(nil,{"more","less"},"Similar to Linux 'more' command. Usage: @@NAME <other command>",printer.set_more,'__SMART_PARSE__',2,false,false,true)
    env.set_command(nil,{"Prompt","pro",'echo'}, "Prompt messages. Usage: @@NAME <message>",printer.load_text,false,2)
    env.set_command(nil,{"SPOOL","SPO"}, "Write the screen output into a file. Usage: @@NAME [file_name[.ext]] [CREATE] | APP[END]] | OFF]",printer.spool,false,3)
    env.ansi.define_color("GREPCOLOR","BBLU;HIW","ansi.grid","Define highlight color for the grep command, type 'ansi' for more available options")
end
return printer
