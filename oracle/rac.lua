local db=env.getdb()

local rac=env.class(db.C.ora)
function rac:ctor()
    self.db=env.getdb()
    self.command="rac"
    self.help_title='Run SQL script relative to RAC. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."rac",{}
end

return rac.new()