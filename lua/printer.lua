local env,select,table,pcall,cfg=env,select,table,pcall,env.set
local writer,reader,console=writer,reader,console
local out=writer
local jwriter=jwriter
local event
local printer={rawprint=print}
local io=io
local NOR,BOLD="",""
local strip_ansi=function(x) return x end
local println,write=console.println,console.write
local buff={ }
local grep_fmt="%1"
local more_text={lines=0}
local termout='on'

local function set_termout(name,value)
    termout=value
    return value
end

function printer.load_text(text)
    printer.print(event.callback("BEFORE_PRINT_TEXT",{text or ""})[1])
end

local function read_output_from_java()
    local lines=writer:lines()
    local space=env.space
    for i=1,#lines do
        more_text[#more_text+1]=space..lines[i]
    end
    more_text.lines=more_text.lines+#lines
end

function printer.set_more(stmt)
    env.checkerr(stmt,"Usage: more <select statement>|<other command>")
    printer.is_more=true
    out.isMore=true
    if stmt:upper()~='LAST' then
        more_text={lines=0}
        out:clear()
        printer.grid_title_lines=0
        pcall(env.eval_line,stmt,true,true)
    end
    read_output_from_java()
    printer.more()
end

function printer.more(output)
    if printer.grid_title_lines < -10 then printer.grid_title_lines=0 end
    local done,err=pcall(console.less,console,table.concat(more_text,'\n'),math.abs(printer.grid_title_lines),#(env.space),more_text.lines)
end

function printer.rawprint(...)
    local msg={}
    for i=1,select('#',...) do 
        msg[i]=tostring(select(i,...))
    end
    println(console,table.concat(msg," "))
end

local function flush_buff(text,lines)
    while #buff > 32766-(lines or 1) do table.remove(buff,1) end
    buff[#buff+1]=strip_ansi(text)
end

function printer.print(...)
    local output,found,ignore,rows={}
    --if not env.set then return end
    for i=1,select('#',...) do
        local v=select(i,...)
        if type(v)~="string" or not v:find('__BYPASS_',1,true) then 
            output[i]=tostring(v)
        else
            ignore=v
        end
    end

    output,rows=table.concat(output,' '):gsub("\r?\n\r?","%0"..env.space)
    output=NOR..env.space..output
     
    if printer.grep_text and not ignore then
        local stack=output:split('[\n\r]+')
        output={}
        for k,v in ipairs(stack) do
            v,found=v:gsub(printer.grep_text,grep_fmt)
            if found>0 and not printer.grep_dir or printer.grep_dir and found==0 then
                output[#output+1]=v
            end
        end
        output=table.concat(output,'\n')
    end

    if env.ansi then output=env.ansi.convert_ansi(output) end
    if ignore or output~="" or not printer.grep_text then
        if termout=='on' and not printer.is_more then println(console,output) end
        if printer.hdl then
            pcall(printer.hdl.write,printer.hdl,strip_ansi(output).."\n")
        end
        if printer.tee_hdl and printer.tee_type~='csv' and printer.tee_type~='html' then
            pcall(printer.tee_hdl.write,printer.tee_hdl,strip_ansi(output).."\n")
        end
    end

    if ignore~='__BYPASS_GREP__' then
        more_text[#more_text+1]=output
        more_text.lines=more_text.lines+rows+1
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
    printer.grep_text='('..keyword:case_insensitive_pattern()..')'
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
    local cmd,params,is_internal,line,text,lines=table.unpack(command)
    if is_internal or #env.RUNNING_THREADS>1 then return end
    if cmd and cmd~='MORE' and cmd~='LESS' and cmd~='OUT' and cmd~='OUTPUT' then
        more_text={lines=0}
        out:clear()
        printer.grid_title_lines=0
    end
    line,lines=line:gsub('\n','\n'..env.MTL_PROMPT)
    line=env.PRI_PROMPT..line
    if printer.hdl then pcall(printer.hdl.write,printer.hdl,line.."\n") end
    flush_buff(line,lines+1)
end

function printer.after_command()
    if #env.RUNNING_THREADS>1  then return end
    if printer.grep_text then 
        printer.grep_after()
    end
    if printer.tee_hdl then 
        printer.tee_after()
    end

    if more_text.lines==0 and not printer.is_more then
        read_output_from_java()
    end

    if more_text.lines>0 then
        flush_buff(table.concat(more_text,'\n'), more_text.lines)
    end
    printer.is_more=false
end

function printer.tee_to_file(row,total_rows, format_func, format_str,include_head)
    local str=type(row)~="table" and row or format_func(format_str, table.unpack(row))
    more_text[#more_text+1]=env.space..str
    more_text.lines=more_text.lines+1
    if more_text.lines<=10 then
        if printer.grid_title_lines <0 and tonumber(row[0]) and tonumber(row[0])==0 then
            printer.grid_title_lines=-99
        elseif printer.grid_title_lines>0 and tonumber(row[0]) and tonumber(row[0])>0 then
            printer.grid_title_lines=-(printer.grid_title_lines)
        elseif printer.grid_title_lines>=0 and include_head and (not row[0] or row[0]==0) then 
            printer.grid_title_lines=more_text.lines
        end
    end

    if type(row)~="table" or not not printer.tee_hdl then return end

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

function printer.view_buff(file)
    if file and file:lower()=='clear' then
        buff={}
        return
    end
    printer.edit_buffer(file,'output.log',table.concat(buff,'\n'))
end

function printer.set_editor(name,editor)
    local ed=os.find_extension(editor)
    return editor
end

function printer.edit_buffer(file,default_file,text)
    local ed=env.set.get("editor")
    local editor='"'..os.find_extension(ed)..'"'
    local f
    if text then
        f=env.write_cache(file or default_file,text)
        if default_file and file and file~=default_file then
            print('Result written to '..file)
        end
    else
        f=env.join_path(env._CACHE_PATH,file or default_file)
    end

    if env.IS_WINDOWS then
        os.shell(editor,f)
    else
        if ed=='vi' or ed=='vim' then 
            editor=ed..' -c ":set nowrap" -n +' 
        elseif ed=='less' then
            editor='less -I -S -Q'
        end
        os.execute(editor..' "'..f..'"')
    end 
end

_G.print=printer.print
_G.rawprint=printer.rawprint

function printer.onload()
    if env.ansi then
        NOR = env.ansi.string_color('NOR') 
        BOLD= env.ansi.string_color('UDL') 
        strip_ansi=env.ansi.strip_ansi
        grep_text=env.ansi.convert_ansi("$GREPCOLOR$%1$NOR$")
    end
    event=env.event
    if env.event then
        env.event.snoop('BEFORE_COMMAND',printer.before_command,nil,90)
        env.event.snoop('AFTER_COMMAND',printer.after_command,nil,90)
        env.event.snoop('ON_PRINT_GRID_ROW',printer.tee_to_file,nil,90)
    end
    BOLD=BOLD..'%1'..NOR
    local tee_help=[[
    Write command output to target file,'+' means append mode. Usage: @@NAME {+|.|[+]<file>|<file>+} <other command> (support pipe(|) operation)
        or <other command>|@@NAME {+|.|[+]<file>|<file>+}
    When <other command> is a query, then the output can be same to the screen output/csv file/html file which depends on the file extension. ]]

    local grep_help=[[
    Filter matched text from the output. Usage: @@NAME <keyword|-keyword> <other command>  (support pipe(|) operation), -keyword means exclude.
    Example: select * from dba_objects|@@NAME sys
    Example: select * from dba_objects|@@NAME -name
    ]]

    local more_help=[[
    Similar to Linux 'less' command. Usage: @@NAME <other command>|last  (support pipe(|) operation)
    Example: select * from dba_objects|@@NAME
    Key Maps:
        exit       :  q or :q or ZZ
        down  page :  <space> or f or ctrl+f or ctrl+v
        up    page :  b or ctrl+b or alt+v
        first page :  < or alt+< or g
        last  page :  > or alt+> or G
        left  page :  [ or home
        right page :  ] or end 
        right half page:  ) or right
        left  half page:  ( or left
        down  half page:  d or ctrl+d
        up    half page:  u or ctrl+u
        /<keyword> :  search
        enable/disable line number: l or L
    ]]
    env.set_command(nil,"grep",grep_help,{printer.grep,printer.grep_after},'__SMART_PARSE__',3,false,false,true)
    env.set_command(nil,"tee",tee_help,{printer.tee,printer.tee_after},'__SMART_PARSE__',3,false,false,true)
    env.set_command({nil,{"output","out"},"Use default editor to view the recent output. Usage: @@NAME [<file>|clear]",printer.view_buff,false,2,false,false,false,is_blocknewline=true})
    env.set_command(nil,{"less","more"},more_help,printer.set_more,'__SMART_PARSE__',2,false,false,true)
    env.set_command(nil,{"Prompt","pro",'echo'}, "Prompt messages. Usage: @@NAME <message>",printer.load_text,false,2)
    env.set_command(nil,{"SPOOL","SPO"}, "Write the screen output into a file. Usage: @@NAME [file_name[.ext]] [CREATE] | APP[END]] | OFF]",printer.spool,false,3)
    env.ansi.define_color("GREPCOLOR","BBLU;HIW","ansi.grid","Define highlight color for the grep command, type 'ansi' for more available options")
    env.set.init("TERMOUT",termout,set_termout,"core","Controls the display of output generated by commands executed from a script","on,off")
    env.set.init({"EDITOR",'_EDITOR'},env.IS_WINDOWS and 'notepad' or 'vi',printer.set_editor,"core","The editor to edit the buffer")
end
return printer
