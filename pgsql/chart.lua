local env=env
local chart=env.class(env.graph)

function chart:ctor()
    self.db=env.getdb()
    self.command={"chart","ch"}
    self.help_title='Show graph chart. '
    self.script_dir=self.db.ROOT_PATH.."chart"
end

return chart.new()