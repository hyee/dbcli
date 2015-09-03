local env=env
local ssh=env.class()

function ssh:ctor()
    self.forwards={}
    self.name="SSH"
end

function ssh:connect(conn_str)
    local usr,pwd,host,port,url
    if type(conn_str)=="table" then --from 'login' command
        args=conn_str
        usr,pwd,url=conn_str.user,packer.unpack_str(conn_str.password),conn_str.url
        host,port=url:match("^SSH@(.+):(%d+)$")
        env.checkerr(port,"Unsupported URL: "..url)
        port=port+0;
        conn_str.password=pwd
    else
        usr,pwd,conn_desc = string.match(conn_str or "","(.*)/(.*)@(.+)")
        if conn_desc == nil then return print("Usage: ssh conn <user>/<passowrd>@host[:port]") end
        host,port=conn_desc:match('^([^:/]+)(:?%d*)$')
        if port=="" then 
            port=22 
        else
            port=tonumber(port:sub(2))
        end
        url='SSH@'..host..':'..port
        conn_str={user=usr,password=pwd,url=url}
    end
    if self.conn then self:disconnect() end
    self.ssh_host=host
    self.ssh_port=port
    self.conn=java.new("org.dbcli.SSHExecutor")
    local ansi_mode=env.ansi and env.ansi.ansi_mode=="ansicon" and "vt100" or "ansi"
    self.conn:connect(host,port,usr,pwd,"",ansi_mode)
    env.event.callback("TRIGGER_CONNECT","env.ssh",url,conn_str)
    self.login_alias=env.login.generate_name(url,conn_str)
    env.set_title("SSH: "..usr..'@'..host)
    print("SSH connected.")
    self.forwards=env.login.list[env.set.get("database")][self.login_alias].port_forwards or {}
    for k,v in pairs(self.forwards) do
        self:do_forward(k..' '..v[2]..' '..(v[3] or ""))
    end
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
    self.login_alias=nil
end

function ssh:getresult(command)
    self:check_connection()
    local line=self.conn:getLastLine(command.."\n",true)
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
end

function ssh:enter_i()
    self.help:print(true)
    print(env.ansi.mask(env.set.get("PROMPTCOLOR"),"Entering interactive mode, execute 'quit' to exit. Command in upper-case would be treated as DBCLI command."))
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
        self:run_command(cmd..(args and ' '..args or ""))
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

function ssh:trigger_login(db,url,props)
    local url=env.login.generate_name(url,props)
    local list=env.login.list[env.set.get("database")] or {}
    if list[url] then
        local ssh_link=list[url].ssh_link
        if ssh_link and list[ssh_link] and (self.login_alias~=ssh_link or not self:is_connect()) then
            self:connect(list[ssh_link])
        end
    end 
end

function ssh:run_local_script(filename,...)
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
    self:getresult('cat >/tmp/dbcli_shell<<"EOF"\n'..txt..'\nEOF\n')
    local commands={intepreter,'/tmp/dbcli_shell'}
    local args={...}
    for k,v in ipairs(args) do
        if v:find("[ \t]") then v='"'..v..'"' end
        commands[#commands+1]=v;
    end
    commands[#commands+1]=";rm -f /tmp/dbcli_shell"
    local command=table.concat(commands,' ')
    self:run_command(command)
end

function ssh:onload()
    local helper=env.grid.new()
    helper:add{"Command",'*',"Description"}
    helper:add{"ssh conn",'',"Connect to SSH server. Usage: ssh conn <user>/<passowrd>@host[:port]"}
    helper:add{"ssh reconn",'',"Re-connect to last connection"}
    helper:add{"ssh close",'',"Disconnect current SSH connection."}
    helper:add{"ssh forward",'',"Forward/un-forward a remote port. Usage: ssh forward <local_port> [<remote_port>] [remote_host]"}
    helper:add{"ssh link",'',"Link/un-link current SSH connection to an existing database connection(see 'login' command). Usage: ssh link <login_id|login_alias>"}
    helper:add{"ssh <cmd>",'',"Run command in remote SSH server. DOES NOT SUPPORT the edit-mode commands(vi,base,top,etc)."}
    --helper:add{"ssh shell <script>",'',"Run local shell script in remote SSH server. Usage: ssh shell <script> [parameters]"}
    helper:add{"ssh -i",'',"Enter into SSH interactive mode to omit the 'ssh ' prefix."}
    helper:sort(1,true)
    self.help=helper
    self.cmds={
        conn=self.connect,
        reconn=self.reconnect,
        close=self.disconnect,
        link=self.link,
        forward=self.do_forward,
        quit=self.exit_i,
        login=env.login.login,
        ['-i']=self.enter_i
    }
    env.set_command(self,self.name,self.helper,self.exec,false,3)
    env.set_command(self,{'shell','sh'},"Run local shell script in remote SSH server. Usage: shell <script> [parameters]",self.run_local_script,false,20)
    env.event.snoop("BEFORE_DB_CONNECT",self.trigger_login,self)
end

function ssh:onunload()
    self:disconnect()
end

return ssh.new()