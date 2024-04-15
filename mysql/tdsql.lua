local db=env.getdb()

local tdsql=env.class(db.C.sql)
function tdsql:ctor()
    self.db=env.getdb()
    self.command="td"
    self.help_title='Run SQL script on TD-SQL under the "td" directory.'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."td",{}
end

function tdsql:run_sql(sql,args,cmds,files)
    --env.checkerr(db.props.tdsql,"Command 'td' is used on TD-SQL only!")
    return self.super.run_sql(self,sql,args,cmds,files)
end



function tdsql:finalize()
end

return tdsql.new()