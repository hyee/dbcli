local env=env
local ssh=env.class(env.scripter)
local cfg,terminal=env.set,env.terminal
local instance
local _term=env.ansi and env.ansi.ansi_mode=="jansi" and "none" or "vt100"

function ssh:ctor()
    self.forwards={}
    self.comment="\n%s*%:%<%<\"?DESC\"?%s*\n(.*)\nDESC%s*\n"
    self.name="SSH"
    self.type="ssh"
    self.command='shell'
    self.ext_name='*'
    self.script_dir,self.extend_dirs,self.public_dir=nil,{},env.join_path(env.WORK_DIR,"lua","shell")
end

function ssh:rehash(script_dir,ext_name,extend_dirs)
    local cmds=env.scripter.rehash(self,self.public_dir,ext_name,{script_dir,extend_dirs})
    return cmds
end

function ssh:load_config(ssh_alias)
    if not ssh_alias then return end
    local file=env.join_path(env.WORK_DIR,'data','jdbc_url.cfg')
    local f=io.open(file,"a")
    if f then f:close() end
    local config,err=env.loadfile(file)
    env.checkerr(config,err)
    config=config()
    config=config and config[self.type]
    if not config then return end
    local props={}
    for alias,url in pairs(config) do
        if type(url)=="table" then
            if alias:upper()==(props.jdbc_alias or ssh_alias:upper())  then
                props=url
                props.jdbc_alias=alias:upper()
            end
        end
    end

    return props.jdbc_alias and props
end

function ssh:connect(conn_str)
    self.script_stack={}
    local usr,pwd,host,port,url,conn_desc
    if type(conn_str)=="table" then --from 'login' commands
        usr,pwd,url,host,port=conn_str.user,packer.unpack_str(conn_str.password),conn_str.url,conn_str.host,conn_str.port
        if not host then
            usr,host,port=url:match("^SSH:(.+)@(.+):(%d+)$")
            env.checkerr(port,"Unsupported URL: "..url)
            port=port+0;
        elseif not port then
            port=22
        end
        conn_str.password=pwd
    else
        if not conn_str then
            return print("Usage: ssh conn user/password@host[:port]")
        end
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)/(.*)@(.+)")
        if conn_desc == nil then
            local props=self:load_config(conn_str)
            if props then return self:connect(props) end
            return print("Usage: ssh conn <user>/<passowrd>@host[:port]")
        end
        host,port=conn_desc:match('^([^:/]+)(:?%d*)$')
        if port=="" or not port then
            port=22
        else
            port=tonumber(port:sub(2))
        end
        conn_str={}
    end
    env.checkerr(usr and host and port,"Invalid SSH connect format!")
    url='SSH:'..usr..'@'..host..':'..port
    conn_str.user,conn_str.password,conn_str.url,conn_str.account_type=usr,pwd,url,"ssh"

    if self.conn then self:disconnect() end
    self.ssh_host=host
    self.ssh_port=port
    self.conn=java.new("org.dbcli.SSHExecutor")
    instance=self
    self.set_config("term",env.set.get("term"))
    local done,err=pcall(loader.asyncCall,loader,self.conn,'connect',host,port,usr,pwd,"")
    if not done then
        self.conn=nil
        env.raise(tostring(err))
    end
    self.login_alias=env.login.generate_name(url,conn_str)
    env.event.callback("TRIGGER_CONNECT","env.ssh",url,conn_str)
    env.set_title("SSH: "..usr..'@'..host)
    print("SSH connected.")
    self.forwards=env.login.list[env.set.get("database")][self.login_alias].port_forwards or {}
    for k,v in pairs(self.forwards) do
        self:do_forward(k..' '..v[2]..' '..(v[3] or ""))
    end
    env.event.callback("AFTER_SSH_CONNECT","env.ssh",url,conn_str)
end

function ssh:reconnect()
    env.checkerr(self.login_alias,"There is no previous connection!")
    self:connect(env.login.list[env.set.get("database")][self.login_alias])
end

function ssh:is_connect()
    return self.conn and self.conn:isConnect() or false
end

function ssh:disconnect()
    if self.conn and self.conn.close then
        pcall(self.conn.close,self.conn)
        print("SSH disconnected.")
    end
    env.set_title("")
    self.conn=nil
    self.script_stack={}
    self.login_alias=nil
end

function ssh:getresult(command,isWait)
    self:check_connection()
    local line=self.conn:getLastLine(command.."\n",isWait==nill and true or isWait)
    self.prompt=self.conn.prompt;
    return line;
end

function ssh:run_command(command)
    self:check_connection()
    self.conn:exec(command.."\n")
    self.prompt=self.conn.prompt;
end

function ssh:ssh_help(_,cmd)
    if cmd==nil or cmd=="" then return "Operations over SSH server, type 'ssh' for more detail" end
end

function ssh:check_connection()
    if not self:is_connect() then
        self:sync_prompt()
        env.raise("SSH server is not connected!")
    end
end

function ssh:link(ac)
    self:check_connection()
    local str="Link/Unlink to an existing database a/c so that the SSH connection is triggered together to create.\n"
    str=str.."Usage: ssh link <login_id>/<login_alias>, refer to command 'login' to get the related information.\n"
    if not ac then return print(str) end
    local conn,account=env.login.search(ac)
    env.checkerr(conn,"Cannot find target connection in login list!")
    local list=env.login.list[env.set.get("database")][account]
    env.checkerr(list.url:match("^jdbc"),"You can only link to a database!")
    if list.ssh_link==self.login_alias then
        list.ssh_link=nil
        login.save()
        return print("Un-linked.")
    else
        list.ssh_link=self.login_alias
        login.save()
        return print("Linked.")
    end
end

function ssh:sync_prompt()
    if env._SUBSYSTEM ~= self.name then return end
    local prompt=(self.conn and self.conn.prompt or "SSH> ")
    env.set_subsystem(self.name,prompt)
    if not self.conn or not self.conn.prompt then env.set_title("") end
end

function ssh:enter_i()
    local shell_env=""
    if self:is_connect() then shell_env="("..self:getresult("echo $SHELL")..")" end
    print("$PROMPTCOLOR$Entering SSH interactive shell environment"..shell_env..", execute 'bye' to exit. Below are the embedded commands:$NOR$")
    self.inner_help:print(true)
    self.is_enter_prompt=true
    env.set_subsystem(self.name)
    --if self:is_connect() then self.conn:enterShell(true) end
end

function ssh:exit_i()
    self.is_enter_prompt=false
    env.set_subsystem(nil)
    --if self:is_connect() then self.conn:enterShell(false) end
end

function ssh:exec(line)
    local cmd,args=table.unpack((env.parse_args(2,line)))
    if cmd and cmd:lower():match("^ssh ") then cmd=cmd:sub(5) end
    if not cmd or cmd=="" or cmd:lower()=="help" then
        if env._SUBSYSTEM~=self.name then
            self.help:print(true)
        else
            self.inner_help:print(true)
        end
        return
    end
    cmd=cmd:lower()
    local alias=env.alias.make_command(cmd,env.parse_args(99,args or ""),false)
    if self.cmds[cmd] then
        self.cmds[cmd](self,args)
    elseif alias and tostring(alias.desc):lower():match("ssh") then
        return env.exec_command(alias[1],alias[2],true,cmd.." "..args)
    else
        self:run_command((line:gsub("^%$","",1)))
    end
    self:sync_prompt()
end

function ssh:do_forward(port_info)
    if not port_info or port_info=="" then
        return print("Usage: ssh forward <local_port> [<remote_port>] [remote_host]")
    end
    self:check_connection()
    local args=env.parse_args(3,port_info)
    local local_port,remote_port,remote_host=tonumber(args[1]),tonumber(args[2]),args[3]
    env.checkerr(local_port,"Local port should be a number!")
    env.checkerr(remote_port or not args[2],"Remote port should be a number!")
    env.checkerr(local_port>0 and (not remote_port or remote_port>0),"Port number must be larger than 0!")
    local assign_port=self.conn:setForward(local_port,remote_port,remote_host)
    if assign_port==-1 then
        self.forwards[local_port]=nil
        return print("Target forward mapping is closed")
    end
    self.forwards[local_port]={assign_port,remote_port,remote_host}
    env.login.list[env.set.get("database")][self.login_alias].port_forwards=self.forwards
    env.login.save()
    print(("Port-forwarding =>   localhost:%d -- %s:%d "):format(assign_port,remote_host or self.ssh_host,remote_port))
end

function ssh:get_ssh_link(db)
    if type(db)~="table" then return end
    local alias=db.login_alias or "__unknown__"
    local list=env.login.list[env.set.get("database")] or {}
    if list[alias] and list[alias].ssh_link then
        return  list[alias].ssh_link,list[list[alias].ssh_link]
    end
end

function ssh:is_link(db)
    local link=ssh:get_ssh_link(db)
    return link and self.login_alias==ssh_link or false
end

function ssh:trigger_login(db,url,props)
    local ssh_link,ssh_account=ssh:get_ssh_link(db)
    if ssh_link and (self.login_alias~=ssh_link or not self:is_connect()) then
        self:connect(ssh_account)
    end
end

function ssh:load_script(alias,filename,...)
    if not filename or filename=="" then
        return print("Run local script over remote SSH sever. Usage: shell <filename> [parameters].")
    end
    self:check_connection()
    local txt
    if filename:sub(1,1)~="@" then
        local file=io.open(filename,'r')
        env.checkerr(file,'Cannot open file '..filename)
        txt=file:read(10485760)
        file:close()
    else
        txt=filename:sub(2)
    end
    txt=txt:gsub("\r\n","\n"):gsub("^%s+",""):gsub(self.comment,"\n",1)
    local intepreter=txt:match("^#!([^\n])+")
    if not intepreter then intepreter="/bin/bash" end
    self:getresult(alias.."='"..txt.."'\n")
    self.script_stack[alias]={intepreter,'-c' ,'"$'..alias..'"',alias}
    return self.script_stack[alias]
end

function ssh:upload_script(filename)
    if not filename or filename=="" then
        return print("Usage: ssh push_shell <file> [/tmp|.|<remote_dir>")
    end
    local file,dir=env.parse_args(2,filename)
    filename,dir=file[1],file[2]
    if filename:match("[\\/]") then filename='@'..filename end
    local txt,args,_,file,cmd=self:get_script(filename,{},false)
    if not file then return end
    self:check_connection()
    txt=txt:gsub("\r\n","\n"):gsub("^%s+","")
    local intepreter=txt:match("^#!([^\n])+")
    if not intepreter then intepreter="/bin/bash" end
    cmd=file:match("[^\\/]+$")
    if dir=='.' then dir=self:get_pwd() end
    filename=(dir and dir:gsub("[\\/]$","").."/" or ('/tmp/'))..cmd
    self:getresult('cat >'..filename..'<<"DBCLI"\n'..txt..'\nDBCLI\n')
    self:getresult('chmod +x '..filename)
    if env.set.get("feed")=="on" then
        rawprint("File uploaded into "..filename)
    end
    return filename
end

function ssh:login(account,list)
    if type(list)=="table" then
        if list.account_type and list.account_type~='ssh' then return end
        if not list.account_type and not list.url:lower():match("^ssh") then return end
        self.__instance:connect(list)
    else
        return env.login.trigger_login(account,list,"SSH:")
    end
end

function ssh.set_config(name,value)
    value = value:lower()
    local term,cols,rows=value:match("(.*),(%w+),(%w+)")
    if not term then
        term=value:match('^[^, ]+')
        _term,cols,rows=cfg.get("term"):match("(.*),(%w+),(%w+)")
    end
    term=_term=="none" and _term or term
    _term=term
    local termtype = term..','..cols..','..rows
    if instance and instance.conn then
        if cols=="auto" then cols=console:getScreenWidth() end
        if rows=="auto" then rows=console:getScreenHeight() end
        instance.conn:setTermType(term,tonumber(cols),tonumber(rows))
        if instance:is_connect() and termtype~=cfg.get("term") then
            print(("Term Type: %s    Columns: %d    Rows: %d"):format(term,tonumber(cols),tonumber(rows)))
        end
    end
    return termtype
end

function ssh:run_shell(cmd,...)
    local text,args,_,file,cmd=self:get_script(cmd,{...},false)
    if not file then return end
    local stack={self:upload_script(file)}
    for i=1,20 do
        local v=args["V"..i]
        if v=="" then break end
        if v:match("[ \t]") then v='"'..v..'"' end
        stack[#stack+1]=v
    end
    self:run_command(table.concat(stack," "))
end

function ssh:get_pwd()
    self:check_connection()
    return self:getresult("pwd")
end

local pscp_options='\n'..[[Options:
  -p        preserve file attributes
  -q        quiet, don't show statistics
  -r        copy directories recursively
  -C        enable compression(default)
  -c        disable compression
  -batch    disable all interactive prompts
  -unsafe   allow server-side wildcards (DANGEROUS)
  -sftp     force use of SFTP protocol
  -scp      force use of SCP protocol]]

local pscp='"'..env.join_path(env.WORK_DIR,"bin",'pscp.exe')..'"'
if not env.IS_WINDOWS then pscp="scp" end
local pscp_download_usage="Download file(s) from SSH server, support wildcards. Usage: ssh download [remote_path]<filename> [.|<local_path>] [options]"
local pscp_upload_usage="Upload file(s) into SSH server, support wildcards. Usage: ssh uploaded  [local_path]<filename> [.|<remote_path>] [options]"
local pscp_local_dir
function ssh:set_ftp_local_path(path)
    local current_path=(pscp_local_dir or env._CACHE_PATH)
    path=path=="." and env._CACHE_PATH or path
    if not path or current_path==path then return print("Current FTP local path is "..current_path..", to switch back to the default path, use 'ssh llcd .'") end
    local path1=env.join_path(current_path..env.PATH_DEL..path)
    if not os.exists(path1) then
        env.checkerr(os.exists(path),"Cannot find target path "..path)
    else
        path=path1
    end
    pscp_local_dir=env.join_path(path,"")
    print(table.concat({"Local FTP path changed:",current_path,'==>',pscp_local_dir},' '))
end

function ssh:ftp_file(op,info)
    if not info then
        return print((op=='download' and pscp_download_usage or pscp_upload_usage)..pscp_options)
    end
    local pwd=self:get_pwd()
    local args=env.parse_args(3,info)
    local remote_file,local_dir,options=args[1],args[2],args[3]
    if op~='download' then remote_file,local_dir=local_dir,remote_file end
    if not remote_file then
        remote_file=pwd
    else
        remote_file=self:getresult('echo "'..remote_file..'"')
        if not remote_file:match("^/") then
            remote_file=pwd.."/"..remote_file
        end
    end
    remote_file=self.conn.user.."@"..self.conn.host..":"..remote_file
    if not local_dir then
        local_dir=(pscp_local_dir or env._CACHE_PATH)
    elseif not local_dir:match("%:") then
        local_dir=(pscp_local_dir or env._CACHE_PATH)..local_dir
    end
    local local_display,remote_display=local_dir,remote_file
    if env.IS_WINDOWS then local_dir='"'..local_dir:gsub("[\\/]+","\\\\")..'"' end
    if op~='download' then
        remote_file,local_dir=local_dir,remote_file
        remote_display,local_display=local_display,remote_display
    end
    
    if not options then
        options="-C"
    elseif not options:lower():find('-c',1,true) then
        options=options..' -C'
    elseif options:find('-c',1,true) then
        options=options:gsub("%s*-c","")
    end
    if not options:lower():find('-r',1,true) then
        options=options..' -r'
    end
    rawprint(table.concat({op:initcap().."ing:    ",remote_display,"==>",local_display,"   Options:",options}," "))
    local command='"'..table.concat({pscp,options or "","-pw",self.conn.password,remote_file,local_dir}," ")..'"'
    os.execute(command)
end

function ssh:download_file(info)
    return self:ftp_file("download",info)
end

function ssh:upload_file(info)
    return self:ftp_file("upload",info)
end

function ssh:__onload()
    instance=self
    self.short_dir=self.script_dir:match('([^\\/]+[\\/][^\\/]+)$')
    if self.public_dir then
        self.short_dir=self.short_dir..'" and "lua\\shell'
    end
    self.help_title='Run script under the "'..self.short_dir..'" directory in remote SSH server. '
    local helper=env.grid.new()
    helper:add{"Command",'*',"Description"}
    helper:add{"ssh conn",'',"Connect to SSH server. Usage: ssh conn <user>/<passowrd>@host[:port]"}
    helper:add{"ssh reconn",'',"Re-connect to last connection"}
    helper:add{"ssh close",'',"Disconnect current SSH connection."}
    helper:add{"ssh forward",'',"Forward/un-forward a remote port. Usage: ssh forward <local_port> [<remote_port>] [remote_host]"}
    helper:add{"ssh link",'',"Link/un-link current SSH connection to an existing database connection(see 'login' command). Usage: ssh link <login_id|login_alias>"}
    helper:add{"ssh  $<command>",'',"Run command in remote SSH server. "}
    helper:add{"ssh   <command>",'',"Run embedded command if exist(i.e.: ssh conn), or run command in remote server."}
    helper:add{"ssh login",'',"Login to a saved SSH account."}
    helper:add{"ssh -i",'',"Enter into SSH interactive mode to omit the 'ssh ' prefix."}
    helper:add{"ssh push_shell",'',"Upload local script into remote directory and grant the execute access. Usage: ssh push_shell <file> [/tmp|.|<remote_dir>]"}
    helper:add{"ssh download",'',pscp_download_usage}
    helper:add{"ssh upload",'',pscp_upload_usage}
    helper:add{"ssh llcd",'',"View/change default downlod/upload FTP directory in local PC. Usage ssh llcd [.|<local_path>]"}
    local cmds=env.grid.new()
    for _,line in ipairs(helper.data) do
        local c={}
        for k,v in ipairs(line) do c[k]=v end
        c[1]=c[1]:lower():gsub("^ssh ","")
        cmds:add(c)
    end
    cmds:add{" .<command>",'',"Run DBCLI command out of this SSH sub-system. For alias command that related to ssh, the '.' prefix can be ignored."}
    cmds:add{"bye","","Exit SSH interactive shell environment."}
    cmds:sort(1,true)
    helper:sort(1,true)
    self.help,self.inner_help=helper,cmds
    self.cmds={
        conn=self.connect,
        reconn=self.reconnect,
        close=self.disconnect,
        link=self.link,
        forward=self.do_forward,
        bye=self.exit_i,
        login=self.login,
        ['-i']=self.enter_i,
        download=self.download_file,
        upload=self.upload_file,
        llcd=self.set_ftp_local_path,
        push_shell=self.upload_script,
    }
    env.remove_command(self.command)
    env.set_command{obj=self,cmd=self.name, 
                    help_func=self.ssh_help,call_func=self.exec,
                    is_multiline=false,parameters=2,color="PROMPTSUBCOLOR"}
    env.set_command{obj=self,cmd={'shell','sh'}, 
                    help_func=self.helper,call_func=self.run_shell,
                    is_multiline=false,parameters=20,color="HIB"}
    env.event.snoop("BEFORE_DB_CONNECT",self.trigger_login,self)
    env.event.snoop("TRIGGER_LOGIN",self.login,self)
    env.event.snoop("ON_KEY_EVENT",self.trigger_key,self)
    cfg.init("term",_term..",auto,auto",self.set_config,"ssh","Define termType/columns/rows in remote SSH server, the supported type depends on remote server",'*')
end

function ssh:trigger_key(_,key_event)
    if key_event.name=='TAB' and self.is_enter_prompt and self:is_connect() then
        key_event.isbreak=true
    end
end

function ssh:__onunload()
    self:disconnect()
end

return ssh