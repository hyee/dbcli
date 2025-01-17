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
local getWidth = console.getBufferWidth
local terminal=terminal

function printer.set_termout(name,value)
    termout=value
    return value
end

function printer.load_text(text)
    printer.print(event.callback("BEFORE_PRINT_TEXT",{text or ""})[1])
end

function printer.get_last_output()
    local lines=writer:lines()
    local space=env.space
    for i=1,#lines do
        more_text[#more_text+1]=space..lines[i]
    end
    more_text.lines=more_text.lines+#lines
    return more_text
end

function printer.clear_buffered_output()
    more_text={lines=0}
end

function printer.set_more(stmt)
    env.checkhelp(stmt)
    local typ,file=os.exists(stmt,'txt')
    if file then
        local text=env.load_data(file,false)
        env.checkerr(text,"Cannot read file: "..file)
        out.isMore=false
        return printer.more(text)
    end
    printer.is_more=true
    out.isMore=true
    if stmt:upper()~='LAST' and stmt:upper()~='L' then
        more_text={lines=0}
        out:clear()
        printer.grid_title_lines=0
        pcall(env.eval_line,stmt,true,true)
    end
    printer.get_last_output()
    printer.more()
end

function printer.more(output)
    if not output then
        if printer.grid_title_lines < -10 then printer.grid_title_lines=0 end
        pcall(console.less,console,table.concat(more_text,'\n'),math.abs(printer.grid_title_lines),#(env.space),more_text.lines)
    else
        local stack,lines=output:gsub('\n',"")
        if output.convert_ansi then output=output:convert_ansi() end
        pcall(console.less,console,output,0,#(env.space),lines)
    end
end

function printer.rawprint(...)
    local msg={}
    for i=1,select('#',...) do 
        msg[i]=tostring(select(i,...))
    end
    println(console,table.concat(msg," "))
end

local function flush_buff(text,lines)
    while #buff > math.max(0,32766-(lines or 1)) do table.remove(buff,1) end
    buff[#buff+1]=strip_ansi(text):rtrim()
end

function printer.print(...)
    local output,found,ignore,column,columns,rows={}
    --if not env.set then return end
    for i=1,select('#',...) do
        local v=select(i,...)
        if type(v)~="string" or not (v:find('^__BYPASS_') or v:find('^__PRINT_COLUMN_')) then 
            output[i]=tostring(v)
        elseif v:find('^__PRINT_COLUMN_') then
            columns,column={},getWidth(console)
        else
            ignore=v
        end
    end

    output=table.concat(output,' ')
    if output.convert_ansi then output=output:convert_ansi() end
    output,rows=output:gsub("([^\n\r]*)([\n\r]*)",function(s,sep)
        if printer.grep_text and not ignore then
            s,found=s:gsub(printer.grep_text,grep_fmt)
            if not (found>0 and not printer.grep_dir or printer.grep_dir and found==0) then
                return ''
            elseif s.convert_ansi then
                s=s:convert_ansi()
            end
        end
        if column then
            _,_,columns[#columns+1]=s:ulen(column)
            columns[#columns+1]=sep
        end
        return (s=='' and '' or (NOR..env.space..s:sub(1,32768)))..sep
    end)

    if ignore or output~="" or not printer.grep_text then
        if termout=='on' and not printer.is_more then 
            if not column then
                println(console,output)
            else
                println(console,table.concat(columns))
            end
        end
        if printer.hdl then
            pcall(printer.hdl.write,printer.hdl,strip_ansi(output).."\n")
        end
        if ignore~='__BYPASS_GREP__' and printer.tee_hdl then
            printer.tee_to_file(output)
        end
    end

    if ignore~='__BYPASS_GREP__' and termout=='on' and more_text.lines<=32767 then
        more_text[#more_text+1]=output
        more_text.lines=more_text.lines+rows+1
        if more_text.lines>32767 then
            table.remove(more_text,1)
        end
    end
end

function printer.print_grid(text)
    printer.print(text,'__BYPASS_GREP__')
end

function printer.write(output)
    if output.convert_ansi then output=output:convert_ansi() end
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
        if printer.hdl then 
            pcall(printer.hdl.close,printer.hdl)
            if env.set and env.set.get("feed")=="on" then
                printer.rawprint(env.space..'Output is written to "'..printer.file..'".')
            end
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
    printer.grep_text=keyword:escape('*i'):gsub('%%','.*')
end

function printer.grep(keyword,stmt)
    env.checkhelp(stmt)
    printer.set_grep(keyword)
    env.eval_line(stmt,true,true)
end

function printer.grep_after()
    printer.grep_text,printer.grep_dir=nil,nil
end

function printer.clip(stmt)
    printer.tee('>CLIP',stmt)
end 
local str_buff=buffer.new()
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
    if file~='>CLIP' and not file:find("[\\/]") then
        file=env._CACHE_PATH..file
    end
    printer.tee_file=file
    if file~='>CLIP' then 
        printer.tee_hdl=io.open(file,mode)
    else
        printer.tee_hdl={
            write=function(self,txt)
                str_buff:put(txt)
            end,
            close=function()
                local str=str_buff:get()
                str_buff:free()
                local done=loader:copyToClipboard(str)
                printer.rawprint(env.space..(done and "Output is copied to clipboard." or "Unable to copy the output to clipboard due to unsupported in current terminal."));
            end
        }
    end
    printer.tee_type=file:lower():match("%.([^%.]+)$")
    if printer.tee_type=='htm' then printer.tee_type='html' end
    env.checkerr(printer.tee_hdl,"Failed to open the target file "..file)
    if stmt~='' then env.eval_line(stmt,true,true) end
end

function printer.tee_after()
    if not printer.tee_hdl then return end
    local res,err=pcall(printer.tee_hdl.close,printer.tee_hdl)
    if not res then print(err) end
    if printer.tee_file~='>CLIP' then printer.rawprint(env.space.."Output is written to "..printer.tee_file) end
    printer.tee_file,printer.tee_hdl,printer.tee_colinfo=nil,nil
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
        printer.get_last_output()
    end

    if more_text.lines>0 then
        flush_buff(table.concat(more_text,'\n'), more_text.lines)
    end
    printer.is_more=false
end

local html_map={
    ['\n']='<br/>',
    ['\r']='',
    ['\b']='',
    ['\f']='',
    ['\0']='',
    ['\t']='    ',
    ['<']='&lt;',
    ['>']='&gt;',
    ['&']='&amp;',
    ['"']='&quot;'
}

local csv_map={
    ['"']='""',
    ['\n']='\\n',
    ['\r']='',
    ['\b']='',
    ['\f']='',
    ['\0']=''
}
local function to_html(str)
    local font_count=0
    str=str:gsub('.',function(s) return html_map[s] or s end)
    if str:find('  ') then
        str=str:gsub('( +)',function(s) return ('&nbsp;'):rep(#s) end)
    end
    return strip_ansi(str,function(s1,s2)
        s2=type(s2)=='table' and s2[3] or nil
        if s2 then
            local font=''
            if s2=='\0' then
                for i=1,font_count do font=font..'</font>' end
            else
                font='<font style="'..s2..'">'
                font_count=font_count+1
            end
            return font
        else
            return ''
        end
    end)
end

local function to_csv(str)
    local quote=''
    if str:trim()~=str or str:find(',') then
        quote='"'
    end
    str=str:gsub('.',function(s)
            local s1=csv_map[s]
            if s1 then quote='"' end
            return s1 or s
        end)
    return quote..str..quote
end

local font='font-size:8pt;font-family:Consolas,DejaVu Sans Mono,Space Mono,Courier New,Courier'
function printer.tee_to_file(row,total_rows, format_func, format_str,include_head)
    local str=type(row)~="table" and row or format_func(format_str, table.unpack(row))
    local space=env.space
    more_text[#more_text+1]=space..str:rtrim()
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

    if not printer.tee_hdl then return end

    local hdl=printer.tee_hdl

    if printer.tee_type=="html" then
        if type(row)=="table" then
            local td='td'
            if(row[0]==0) then
                if printer.tee_colinfo then
                    hdl:write('</table>\n')
                end
                hdl:write("<table style='border:1px solid #0066CC;border-collapse:seperate;"..font.."'>\n")
                printer.tee_colinfo=row.colinfo
                td='th'
            end
            hdl:write("  <tr style='white-space:nowrap;background:"..(row[0]==0 and '#0066CC' or math.fmod(row[0],2)==1 and 'white' or '#FFFFCC')..";color:"..(row[0]==0 and 'white' or 'black').."'>\n")
            for idx,cell in ipairs(row) do
                hdl:write("    <"..td
                             ..(printer.tee_colinfo and printer.tee_colinfo[idx].is_number==1 and ' align="right"' or '')
                             ..">")
                if type(cell)=="string" then
                    --cell=strip_ansi(cell)
                    hdl:write(to_html(cell))
                elseif cell~=nil then
                    hdl:write(cell)
                end
                hdl:write("</"..td..">\n")
            end
            hdl:write("  </tr>\n")
            if row[0]==total_rows-1 then 
                hdl:write('</table>\n<br/>\n')
                printer.tee_colinfo=nil
            end
        elseif (not printer.tee_colinfo or not total_rows) and type(str)=="string" then
            str=str:rtrim()
            local c=0
            local strip=strip_ansi(str)
            if strip:find('^'..space) then
                str,c=str:gsub(space,'',1)
            end
            if c==0 then
                str=str:gsub('^'..space,''):gsub('\n'..space,'\n')
            end
            hdl:write('<p style="margin:0;'..font..'">'..to_html(str)..'</p>\n')
        end
    elseif type(row)=="table" and printer.tee_type=="csv" then
        for idx,cell in ipairs(row) do
            if idx>1 then hdl:write(",") end
            if type(cell)=="string" then
                cell=strip_ansi(cell):gsub('"','""')
                if row[0]==0 then cell=cell:trim() end
                hdl:write(to_csv(cell))
            elseif cell~=nil then
                hdl:write(cell)    
            end
        end
        hdl:write("\n")
        if row[0]==total_rows-1 then
            hdl:write("\n")
        end
    elseif type(str)=="string" and printer.tee_type~="csv" then
        pcall(hdl.write,hdl,(total_rows and space or '')..(printer.tee_type=='ans' and str:convert_ansi() or strip_ansi(str)):rtrim().."\n")
    end
end

function printer.view_buff(file)
    if file and file:lower()=='clear' then
        buff={}
        printer.clear_buffered_output()
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

function printer.setTermType(name,typ)
    typ=tonumber(typ)
    terminal:switchWriter(typ-1);
    return terminal:currentWriter()+1;
end

_G.print=printer.print
_G.rawprint=printer.rawprint

function printer.onload()
    if env.ansi then
        NOR = env.ansi.string_color('NOR') 
        BOLD= env.ansi.string_color('UDL') 
        strip_ansi=env.ansi.strip_ansi
        grep_fmt=env.ansi.convert_ansi("$GREPCOLOR$%1$NOR$")
    end
    event=env.event
    if env.event then
        env.event.snoop('BEFORE_COMMAND',printer.before_command,nil,90)
        env.event.snoop('AFTER_COMMAND',printer.after_command,nil,90)
        env.event.snoop('ON_PRINT_GRID_ROW',printer.tee_to_file,nil,90)
    end
    BOLD=BOLD..'%1'..NOR
    local tee_help=[[
    Write command output to target file,'+' means append mode. Usage: @@NAME {+|.|[+]<file>} <other command> (support pipe(|) operation)
        or <other command>|@@NAME {+|.|[+]<file>}
    Target:
         <file> : write the output into <file> with override mode
        +<file> : write the output into <file> with append mode
              . : write the output into "last_output.txt" with override mode
              + : write the output into "last_output.txt" with append mode
    File extentions:
           .html: if the output is a query result, then save it as HTML format
           .csv : if the output is a query result, then save it as CSV format
           .ans : keep the output's ANSI color escapes
        <others>: remove output's ANSI color escapes
    ]]

    local grep_help=[[
    Filter matched text from the output. Usage: @@NAME <keyword|-keyword> <other command>  (support pipe(|) operation), -keyword means exclude.
    Example: select * from dba_objects|@@NAME sys
    Example: select * from dba_objects|@@NAME -name
    ]]

    local more_help=[[
    Similar to Linux 'less' command. Usage: @@NAME <other command>|<file>|last|l  (support pipe(|) operation)
        last : Display the last output on less mode
        l    : Same to 'last'
    
    Example:
        @@NAME select * from gv$session;
        select * from gv$session | @@NAME;

    [|             grid:{topic='Key Maps'}
     | Key Map              | Command                   |
     | q   :q   ZZ          | Exit                      |
     | l        L           | Display / Hide line number|
     |-                     |-                          |
     | f   ^F   Space   ^V  | Forward  window           |
     | b   ^B   Alt+V       | Backward window           |
     | g   <    Alt+<       | Top   window              |
     | G   >    Alt+>       | Last  window              |
     | d        ^D          | Forward  half window      |
     | u        ^U          | Backward half window      |
     |-                     |-                          |
     | [        Home        | Left  window              |
     | \]        End        | Right window              |
     | (        Left        | Left  half window         |
     | )        Right       | Right half window         |
     |-                     |-                          |
     | /pattern             | Search pattern            |
     | n        Alt+n       | Search Forward            |
     | N        ALT+N       | Search Backward           |]

    Example: select * from dba_objects|@@NAME
    ]]
    env.set_command(nil,"grep",grep_help,{printer.grep,printer.grep_after},'__SMART_PARSE__',3,false,false,true)
    env.set_command(nil,"tee",tee_help,{printer.tee,printer.tee_after},'__SMART_PARSE__',3,false,false,true)
    env.set_command(nil,"clip","Copy output into clipboard.",{printer.clip,printer.tee_after},'__SMART_PARSE__',2,false,false,true)
    env.set_command({nil,{"output","out"},"Use default editor to view the recent output. Usage: @@NAME [<file>|clear]",printer.view_buff,false,2,false,false,false,is_blocknewline=true})
    env.set_command(nil,{"less","more"},more_help,printer.set_more,'__SMART_PARSE__',2,false,false,true)
    env.set_command(nil,{"Prompt","pro",'echo'}, "Prompt messages. Usage: @@NAME <message>",printer.load_text,false,2)
    env.set_command(nil,{"SPOOL","SPO","\\o"}, "Write the screen output into a file. Usage: @@NAME [file_name[.ext]] [CREATE] | APP[END]] | OFF]",printer.spool,false,3)
    env.ansi.define_color("GREPCOLOR","BBLU;HIW","ansi.grid","Define highlight color for the grep command, type 'ansi' for more available options")
    env.set.init("TERMOUT",termout,printer.set_termout,"core","Controls the display of output generated by commands executed from a script","on,off")
    env.set.init({"EDITOR",'_EDITOR'},env.IS_WINDOWS and 'notepad' or 'vi',printer.set_editor,"core","The editor to edit the buffer")
    if terminal.infoComps then
       env.set.init({"TERMTYPE",'_EDITOR'},terminal:currentWriter()+1,printer.setTermType,"core","Set Terminal Type. 1-Win10 2-ConEmu","1,2")
    end;
end
return printer
