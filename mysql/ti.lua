local db=env.getdb()

local ti=env.class(db.C.sql)
function ti:ctor()
    self.db=env.getdb()
    self.command="ti"
    self.help_title='Run SQL script on TiDB under the "ti" directory.'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."ti",{}
end

function ti:run_sql(sql,args,cmds,files)
    env.checkerr(db.props.tidb,"Command 'ti' is used on TiDB only!")
    return self.super.run_sql(self,sql,args,cmds,files)
end

return ti.new()