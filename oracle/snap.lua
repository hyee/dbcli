local env=env
local grid=env.oracle,env.grid
local cfg=env.set

local snap=env.class(env.snapper)
function snap:ctor()
    self.db=env.oracle
    self.command="snap"
    self.help_title='Calculate a period of db/session performance/waits. '
    self.script_dir=env.WORK_DIR.."oracle"..env.PATH_DEL.."snap"
end

function snap:before_exec_action()
    if self.db:is_connect() then self.db:internal_call("ALTER SESSION SET ISOLATION_LEVEL=SERIALIZABLE") end
end

function snap:after_exec_action()
    if self.db:is_connect() then self.db:internal_call("ALTER SESSION SET ISOLATION_LEVEL=READ COMMITTED") end
end

function snap:get_db_time()
    return self.db:get_value("select /*INTERNAL_DBCLI_CMD*/ to_char(sysdate,'yyyy-mm-dd hh24:mi:ss') from dual")
end

function snap:onload()
    self.validate_accessable=self.db.C.ora.validate_accessable
end

return snap.new()
