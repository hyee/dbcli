local db=env.getdb()

local show=env.class(db.C.ora)
function show:ctor()
    self.db=env.getdb()
    self.command="show"
    self.help_title='Run SQL script without parameters under the "show" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."show",{}
end

function show:run_sql(sql,args,cmds,files)
    env.checkerr((args[1]['V1'] or db.NOT_ASSIGNED)==db.NOT_ASSIGNED,"Command 'Show' doesn't accept any parameters!")
    return self.super.run_sql(self,sql,args,cmds,files)
end

return show.new()