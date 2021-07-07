local db=env.getdb()

local list=env.class(db.C.sql)
function list:ctor()
    self.db=env.getdb()
    self.command="list"
    self.help_title='Run SQL script without parameters under the "list" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."list",{}
end

function list:run_sql(sql,args,cmds,files)
    env.checkerr((args[1]['V1'] or db.NOT_ASSIGNED)==db.NOT_ASSIGNED,"Command 'list' doesn't accept any parameters!")
    return self.super.run_sql(self,sql,args,cmds,files)
end

return list.new()