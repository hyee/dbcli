local env,os,console=env,os,console
local event,cfg,grid=env.event,env.set,env.grid
local history={}
local keys={}
history.keys=keys
local lastcommand

function history:show(key)
    local index=tonumber(key)
    if not index then
        if key and key:lower()=="last" then
            print(lastcommand.text)
            return
        end
        local hdl,counter=grid.new(),0
        grid.add(hdl,{"#","Secs","Command"})
        for i=#self,1,-1 do
            counter=counter+1
            grid.add(hdl,{counter,self[i].clock,self[i].desc})
        end
        grid.print(hdl)
    else
        local cmd=self[#self-index+1]
        if cmd then
            env.exec_command(cmd.cmd,cmd.args)
        end
    end
end

local is_changed,current_line,current_index

local cmds={HIS=1,HISTORY=1,["/"]=1,R=1,EDIT=1,ED=1,L=1,LIST=1,CHANGE=1,C=1,HELP=1,SET=1,KEYMAP=1,
            OUT=1,OUTPUT=1,['/*']=1,['--']=1,COL=1,COLUMN=1,PRO=1,PROMPT=1}

function history:capture(cmd,args,res,is_internal,command_text,clock)
    if #env.RUNNING_THREADS>1 or not args then return end
    --if(cmd==nil) then print(debug.traceback()) end
    cmd=cmd:upper()
    if cmds[cmd] then return end
    console:setLastHistory();
    local maxsiz=cfg.get("HISSIZE")
    local text=table.concat(args," ")
    if text:find(cmd,1,true)~=1 then text=cmd..' '..text end
    local key=text:gsub("[%s%z\128\192]+"," "):sub(1,300)
    local k1=key:upper()
    if keys[k1] then
        table.remove(self,keys[k1])
        for k,v in pairs(keys) do if v>keys[k1] then keys[k]=v-1 end end
    end
    lastcommand={cmd=cmd,desc=key,args=args,tim=os.timer(),clock=clock,key=k1,text=text}
    is_changed,current_line,current_index=false
    if maxsiz < 1 then return end
    table.insert(self,lastcommand)
    while #self>maxsiz do
        local k=self[1].key
        table.remove(self,1)
        for o,v in pairs(keys) do if v>1 then keys[o]=v-1 end end
        keys[k]=nil
    end
    keys[k1]=#self
end

local function load_file()
    if lastcommand then
        if is_changed then
            local file=env.join_path(env._CACHE_PATH,'afiedt.buf')
            local f,err=io.open(file,'r')
            env.checkerr(f,err)
            local text=f:read('*a')
            f:close()
            is_changed=false;
        else
            return lastcommand.text;
        end
        return text;
    end
end;

function history.rerun()
    local file=load_file()
    if file then env.eval_line(file,true,true) end
end

function history.edit_buffer(file)
    if not lastcommand then return end
    is_changed=true;
    env.printer.edit_buffer(file,'afiedt.buf',lastcommand.text)
end

local fmt='%s%-3s$PROMPTCOLOR$|$NOR$ %s'
function history.show_command(m,n)
    local file=load_file()
    if not file or file=='' then return end
   
    local lines=file:split('\r?\n')
    local function get_index(target)
        local idx
        if target=='last' then
            idx=#lines
        elseif target=='*' then
            idx=current_index or #lines 
        elseif tonumber(target) then
            idx=tonumber(target)
            if idx<0 then
                idx=#lines+1+idx
            end
        end
        return idx
    end

    local m1=get_index(m) or current_index or #lines
    local n1=get_index(n) or m1
    local line=lines[m1]

    env.checkerr(line and lines[n1],'Lines not found[#'..m1..'-'..n1..'].')
    if m and (m~='*' and n~='*') or not current_index then current_index=n1 end;

    if m and m1 == n1 then
        return print(fmt:format('*',''..m1,line))
    end

    local output={}
    local b,e=1,#lines

    if m then
        b,e=math.min(m1,n1),math.max(m1,n1)
    end

    for k,v in ipairs(lines) do
        if k>=b and k<=e then
            output[#output+1]=fmt:format(k==current_index and '*' or ' ',k,v)
        end
    end
    print(table.concat(output,'\n'))
end

function history.change_command(m)
    env.checkerr(m,'Nothing to change.')
    if m:sub(1,1)=='/' then m=m:sub(2) end
    local file=load_file()
    if not file then return end
    local o,n=table.unpack(m:split('/',true))
    if o=='' then return end
    o,n=o:lower(),n or ''
    local lines=file:split('\n',true)
    if not current_index then current_index=#lines end
    local line=lines[current_index]
    env.checkerr(line and line:lower():find(o,1,true),'String not found.')
    local b,e=line:lower():find(o,1,true)
    line=line:replace(o,n,true,nil,true)
    lines[current_index]=line
    lastcommand.text=table.concat(lines,'\n')
    console:updateLastHistory(lastcommand.text)
    
    print(fmt:format('*',current_index,line))
end

function history.set_editor(name,editor)
    editor=os.find_extension(editor)
    return editor
end

function history.onload()
    cfg.init("HISSIZE",50,history.set_editor,"core","Max size of historical commands",'0 - 999')
    event.snoop("AFTER_SUCCESS_COMMAND",history.capture,history)
    env.set_command(history,{'history','his'},"Show/run historical commands. Usage: @@NAME [index|last]",history.show,false,2)
    env.set_command(nil,{'r','/'},"Rerun the previous command.",history.rerun,false,2)
    env.set_command(nil,{'l'},"Show the previous command. Usage: @@NAME [last|*|<num>] [last|*|<num>]",history.show_command,false,3)
    env.set_command(nil,{'change','c'},"Edit the previous command. Usage: @@NAME [<text>|<old>/<new>] ",history.change_command,false,2)
    env.set_command({nil,{'EDIT','ED'},"Use the program that defined in 'set editor' to edit the buffer in order to run with '/'.",history.edit_buffer,false,2,is_blocknewline=true})
end

return history
