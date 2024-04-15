local db=env.getdb()

local tdsql=env.class(db.C.sql)
function tdsql:ctor()
    self.db=env.getdb()
    self.command="gs"
    self.help_title='Run SQL script on GaussDB under the "gs" directory.'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."gs",{}
end

function tdsql:run_sql(sql,args,cmds,files)
    env.checkerr(db.props.gaussdb,"Command 'gs' is used on GaussDB only!")
    return self.super.run_sql(self,sql,args,cmds,files)
end



function tdsql:finalize()
end

return tdsql.new()