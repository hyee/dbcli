local db=env.getdb()

local rac=env.class(db.C.ora)
function rac:ctor()
    self.db=env.getdb()
    self.command="adb"
    self.help_title='Run SQL script relative to Oracle Autonomous Database(ADW/ATP). '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."adb",{}
end

return rac.new()