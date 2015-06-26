
local db=env.oracle

local sys=env.class(db.C.ora)
function sys:ctor()
    self.db=env.oracle
    self.command="sys"
    self.help_title='Run SQL script under the "sys" directory that needs SYSDBA login. '
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."sys",{}
end

function sys:run_sql(sql,args,print_args)
    env.checkerr(self.db.props.isdba,"You don't have the SYSDBA privilege!")
    self.super:run_sql(sql,args,print_args)
end

return sys.new()