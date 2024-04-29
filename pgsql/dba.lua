local db=env.getdb()

local dba=env.class(db.C.sql)
function dba:ctor()
    self.db=env.getdb()
    self.command="dba"
    self.help_title='Run SQL script that is available only to superuser or sysadmin under the "dba" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."dba",{}
end

function dba:run_sql(sql,args,cmds,files)
    env.checkerr(db.props.isdba==true,"The command is only available to superuser.")
    return self.super.run_sql(self,sql,args,cmds,files)
end

return dba.new()