local env=env
local ssh=env.class()
local cfg=env.set
local instance
local _term=env.ansi and env.ansi.ansi_mode=="ansicon" and "xterm" or "none"

function ssh:ctor()
    self.forwards={}
    self.name="SSH"
    self.type="ssh"
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."ora",{}
end

function ssh:load_config(ssh_alias)
    local file=env.WORK_DIR..'data'..env.PATH_DEL..'jdbc_url.cfg'
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
    local usr,pwd,host,port,url
    if type(conn_str)=="table" then --from 'login' command
        args=conn_str
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
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)/(.*)@(.+)")
        if conn_desc == nil then
            local props=self:load_config(conn_str)
            if props then return self:connect(props) end
            return print("Usage: ssh conn <user>/<passowrd>@host[:port]") 
        end
        host,port=conn_desc:match('^([^:/]+)(:?%d*)$')
        if port=="" then 
            port=22 
        else
            port=tonumber(port:sub(2))
        end
        conn_str={}
    end

    url='SSH:'..usr..'@'..host..':'..port
    conn_str.user,conn_str.password,conn_str.url,conn_str.account_type=usr,pwd,url,"ssh"

    if self.conn then self:disconnect() end
    self.ssh_host=host
    self.ssh_port=port
    self.conn=java.new("org.dbcli.SSHExecutor")
    instance=self
    self.set_config("term",env.set.get("term"))
    local done,err=pcall(self.conn.connect,self.conn,host,port,usr,pwd,"")
    env.checkerr(done,tostring(err))
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

function ssh:helper(_,cmd)
    if cmd==nil or cmd=="" then return "Operations over SSH server, type 'ssh' for more detail" end
end

function ssh:check_connection()
    env.checkerr(self:is_connect(),"SSH server is not connected!")
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
    local prompt=self.conn and self.conn.prompt or "SSH> "
    env.PRI_PROMPT,env.CURRENT_PROMPT=prompt,prompt
    if not self.conn or not self.conn.prompt then env.set_title("") end
end

function ssh:enter_i()
    self.help:print(true)
    print(env.ansi.mask(env.set.get("PROMPTCOLOR"),"Entering interactive mode, execute 'bye' to exit.\n"..
        "Command in '.<command>' format would be treated as DBCLI command.\n"..
        "Command in '$<command>' format to force execute in remote SSH server.\n"..
        "Command without any prefix would be automatically determined."))
    env.set_subsystem(self.name)
end

function ssh:exit_i()
    env.set_subsystem(nil)
end

function ssh:exec(cmd,args)
    if not cmd or cmd=="" or cmd:lower()=="help" then
        self.help:print(true)
        return
    end
    cmd=cmd:lower()
    if not self.cmds[cmd] then
        self:run_command(cmd:gsub("^%$","",1)..(args and ' '..args or ""))
    else
        self.cmds[cmd](self,args)
    end
    self:sync_prompt()
end

function ssh:do_forward(port_info)
    if not port_info or port_info=="" then
        return print("Usage: ssh forward <local_port> [<remote_port>] [remote_host]")
    end
    self:check_connection()
    local args=env.parse_args(3,port_info)
    local_port,remote_port,remote_host=tonumber(args[1]),tonumber(args[2]),args[3]
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
    local file=io.open(filename,'r')
    env.checkerr(file,'Cannot open file '..filename)
    local txt=file:read('*a')
    file:close()
    txt=txt:gsub("\r",""):gsub("^[\n%s\t\v]+","")
    local intepreter=txt:match("^#!([^\n])+")
    if not intepreter then intepreter="/bin/bash" end
    self:getresult(alias.."='"..txt.."'\n")
    self.script_stack[alias]={intepreter,'-c' ,'$'..alias}
    return self.script_stack[alias]
end

function ssh:execute_script(filename,...)
    local alias=filename:match("([^\\/]+)$")
    env.checkerr(alias,'Invalid file '..filename)
    if alias:find('.',1,true) then alias=alias:match("^(.*)%.[^%.]+$") end
    local stack=self:load_script(alias,filename)
    for i=1,#select(...) do
        local param=select(i,...)
        if param then
            if param:match("[\t ]") then param='"'..param..'"' end
            stack[#stack+1]=param
        end
    end
    self:run_command(table.concat(stack," "))
end

function ssh:upload_script(alias,filename,...)
    if not filename or filename=="" then
        return print("Run local script over remote SSH sever. Usage: shell <filename> [parameters].")
    end
    self:check_connection()
    local file=io.open(filename,'r')
    env.checkerr(file,'Cannot open file '..filename)
    local txt=file:read('*a')
    file:close()
    txt=txt:gsub("\r",""):gsub("^[\n%s\t\v]+","")
    local intepreter=txt:match("^#!([^\n])+")
    if not intepreter then intepreter="/bin/bash" end
    filename='/tmp/'..alias
    self:getresult('cat >'..filename..'<<"DBCLI"\n'..txt..'\nDBCLI\n')
    self:getresult('chmod +x '..filename)
    if env.set.get("feed")=="on" then
        print("File uploaded into "..filename)
    end
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
    local term,cols,rows=value:match("(.*),(%d+),(%d+)")
    if not term then
        term=value:match('^[^, ]+')
        _term,cols,rows=cfg.get("term"):match("(.*),(%d+),(%d+)")
    end
    term=_term=="none" and _term or term
    _term=term
    local termtype = term..','..cols..','..rows
    if instance then
        instance.conn:setTermType(term,tonumber(cols),tonumber(rows))
        if instance:is_connect() and termtype~=cfg.get("term") then
            print(("Term Type: %s    Columns: %d    Rows: %d"):format(term,tonumber(cols),tonumber(rows)))
            cfg.temp(termtype)
            instance:reconnect()
        end
    end
    return termtype
end

function ssh:__onload()
    instance=self
    local helper=env.grid.new()
    helper:add{"Command",'*',"Description"}
    helper:add{"ssh conn",'',"Connect to SSH server. Usage: ssh conn <user>/<passowrd>@host[:port]"}
    helper:add{"ssh reconn",'',"Re-connect to last connection"}
    helper:add{"ssh close",'',"Disconnect current SSH connection."}
    helper:add{"ssh forward",'',"Forward/un-forward a remote port. Usage: ssh forward <local_port> [<remote_port>] [remote_host]"}
    helper:add{"ssh link",'',"Link/un-link current SSH connection to an existing database connection(see 'login' command). Usage: ssh link <login_id|login_alias>"}
    helper:add{"ssh <cmd>",'',"Run command in remote SSH server. DOES NOT SUPPORT the edit-mode commands(vi,base,top,etc)."}
    helper:add{"ssh login",'',"Login to a saved SSH account."}
    helper:add{"ssh -i",'',"Enter into SSH interactive mode to omit the 'ssh ' prefix."}
    helper:add{"ssh load_shell",'',"Load local script into remote variable."}
    helper:add{"ssh push_shell",'',"Upload local script into remote /tmp directory."}
    helper:sort(1,true)
    self.help=helper
    self.cmds={
        conn=self.connect,
        reconn=self.reconnect,
        close=self.disconnect,
        link=self.link,
        forward=self.do_forward,
        bye=self.exit_i,
        login=self.login,
        ['-i']=self.enter_i,
        --load_shell=self.load_script,
        --push_shell=self.upload_script,
    }
    env.set_command(self,self.name,self.helper,self.exec,false,3)
    env.set_command(self,{'shell','sh'},"Run local shell script in remote SSH server. Usage: shell <script> [parameters]",self.run_local_script,false,20)
    env.event.snoop("BEFORE_DB_CONNECT",self.trigger_login,self)
    env.event.snoop("TRIGGER_LOGIN",self.login,self)
    cfg.init("term",_term..","..cfg.get("linesize")..",60",self.set_config,"ssh","Define term type in remote SSH server, the supported type depends on remote server",'*')
end

function ssh:__onunload()
    self:disconnect()
end

return ssh