local env=env
local ssh=env.class()

function ssh:ctor()
    local helper=env.grid.new()
    helper:add{"Command",'*',"Description"}
    helper:add{"ssh conn",'',"Connect to SSH server. Usage: ssh conn <user>/<passowrd>@host[:port]"}
    helper:add{"ssh close",'',"Disconnect current SSH connection."}
    helper:add{"ssh forward",'',"Forward/un-forward a remote port. Usage: ssh forward <local_port> [<remote_port>] [remote_host]"}
    helper:add{"ssh link",'',"Link/un-link current SSH connection to an existing database connection(see 'login' command). Usage: ssh link <login_id|login_alias>"}
    helper:add{"ssh <cmd>",'',"Run command in remote SSH server."}
    --helper:add{"ssh @<script>",'',"Run local shell script in remote SSH server. Usage: ssh @<script> [parameters]"}
    --helper:add{"ssh -i",'',"Enter interactive mode."}
    helper:sort(1,true)
    self.help=helper
    self.forwards={}
    self.cmds={
        conn=self.connect,
        close=self.disconnect,
        link=self.link,
        forward=self.do_forward
    }
end

function ssh:connect(conn_str)
    local usr,pwd,host,port,url
    if type(conn_str)=="table" then --from 'login' command
        args=conn_str
        usr,pwd,url=conn_str.user,packer.unpack_str(conn_str.password),conn_str.url
        host,port=url:match("^SSH@(.+):(%d+)$")
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
    self.conn:connect(host,port,usr,pwd,env.space)
    env.event.callback("TRIGGER_CONNECT","env.ssh",url,conn_str)
    self.login_alias=env.login.generate_name(url,conn_str)
    print("SSH connected.")
    self.forwards=env.login.list[env.set.get("database")][self.login_alias].port_forwards or {}
    for k,v in pairs(self.forwards) do
        self:do_forward(k..' '..v[2]..' '..(v[3] or ""))
    end
end

function ssh:is_connect()
    return self.conn and self.conn:isConnect() or false
end

function ssh:disconnect()
    if self.conn and self.conn.close then pcall(self.conn.close,self.conn) end
    self.conn=nil
    self.login_alias=nil
    print("SSH disconnected.")
end

function ssh:run_command(command)
    env.checkerr(self.conn,"SSH connection has not been created, use 'ssh conn' firstly.")
    self.conn:exec(command)
end

function ssh:helper(_,cmd)
    if cmd==nil or cmd=="" then return "Operations over SSH server, type 'ssh' for more detail" end
end

function ssh:link(ac)
    env.checkerr(self:is_connect(),"Please connect to an SSH server fistly!")
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

function ssh:exec(cmd,args)
    if not cmd or cmd=="" then
        self.help:print(true)
        return
    end

    cmd=cmd:lower()
   
    if not self.cmds[cmd] then
        return self:run_command(cmd..(args and ' '..args or ""))
    end

    self.cmds[cmd](self,args)
end

function ssh:do_forward(port_info)
    if not port_info or port_info=="" then
        return print("Usage: ssh forward <local_port> [<remote_port>] [remote_host]")
    end
    env.checkerr(self:is_connect(),"Please connect to an SSH server fistly!")
    local args=env.parse_args(3,port_info)
    local_port,remote_port,remote_host=tonumber(args[1]),tonumber(args[2]),args[3]
    env.checkerr(local_port,"Local port should be a number!")
    env.checkerr(remote_port or not args[2],"Remote port should be a number!")
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
    local list=env.login.list[env.set.get("database")]
    if list[url] and list[url].ssh_link then
        if list[list[url].ssh_link] then
            self:connect(list[list[url].ssh_link])
        end
    end 
end

function ssh:onload()
    env.set_command(self,"ssh",self.helper,self.exec,false,3)
    env.event.snoop("BEFORE_DB_CONNECT",self.trigger_login,self)
end

function ssh:onunload()
    self:disconnect()
end

return ssh.new()