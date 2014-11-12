local env,java=env,java
local event,packer,cfg,init=env.event.callback,env.packer,env.set,env.init
local set_command,exec_command=env.set_command,env.exec_command

local module_list={}


local mssql=env.class(env.db_core)

function mssql:ctor(isdefault)
    self.type="mssql"
    if isdefault~=false then
        --load command list here
        local md=1
    end
    self.C,self.props={},{}
end

function mssql:onload()
    self.C={}
    init.load_modules(module_list,self.C)
end

return mssql.new()