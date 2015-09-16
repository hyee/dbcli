local env=env
local chart=env.class(env.graph)

function chart:ctor()
    self.db=env.oracle
    self.command={"chart","ch"}
    self.help_title='Show graph chart. '
    self.script_dir=env.WORK_DIR.."oracle"..env.PATH_DEL.."chart"
end

function chart:onload()
    self.validate_accessable=self.db.C.ora.validate_accessable
end


return chart.new()