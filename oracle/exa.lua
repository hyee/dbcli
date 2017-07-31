local db=env.getdb()

local exa=env.class(db.C.ora)
function exa:ctor()
    self.db=env.getdb()
    self.command="exa"
    self.help_title='Run SQL script relative to Exadata/SuportCluster. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."exa",{}
end

return exa.new()