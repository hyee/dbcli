local env=env
local grid=env.getdb(),env.grid
local cfg=env.set

local snap=env.class(env.snapper)
function snap:ctor()
    self.db=env.getdb()
    self.command="snap"
    self.help_title='Calculate a period of db/session performance/waits. '
    self.script_dir=self.db.ROOT_PATH.."snap"
end

function snap:get_db_time()
    return self.db:get_value("select /*INTERNAL_DBCLI_CMD*/ CURRENT_TIMESTAMP")
end

function snap:onload()
    self.validate_accessable=self.db.C.sql.validate_accessable
end

return snap.new()
