local db=env.getdb()

local pdb=env.class(db.C.ora)
function pdb:ctor()
    self.db=env.getdb()
    self.command={"pdb"}
    self.help_title='Run SQL script relative to PDB'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."pdb",{}
end

return pdb.new()