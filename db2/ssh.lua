local env=env
local db=env.getdb()
local ssh=env.class(env.ssh)
function ssh:ctor()
    self.script_dir=db.ROOT_PATH.."shell"
end

function ssh:open_ssh(db,sql,args,result)
    if env.set.get("AUTOSSH")=="off" then return end
    if self:is_link(db) and self:is_connect() then return end
    print("Trying ssh to: "..args.user.."@"..args.server)
    self:connect(args.user..'/'..env.packer.unpack_str(args.password)..'@'..args.server)
end

function ssh:set_ssh()
    if not db:is_connect() or not db.props.database then return end
    self:getresult("db2 connect to "..db.props.database,false)
end

function ssh:onload()
    env.event.snoop("AFTER_DB2_CONNECT",self.open_ssh,self)
    env.event.snoop("AFTER_SSH_CONNECT",self.set_ssh,self)
    env.set.init("AUTOSSH","on",nil,"db2","Enable/disable automatical SSH connection after db2 is connected",'on,off')
end

function ssh:onunload()
end

return ssh.new()