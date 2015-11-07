
local db=env.oracle

local sys=env.class(db.C.ora)
function sys:ctor()
    self.db=env.oracle
    self.command="show"
    self.help_title='Run SQL script without parameters under the "show" directory. '
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."show",{}
end

function sys:run_sql(sql,args,print_args)
    env.checkerr((args['V1'] or "")=="","Command 'Show' doesn't accept any parameters!")
    return self.super.run_sql(self,sql,args,print_args)
end

return sys.new()