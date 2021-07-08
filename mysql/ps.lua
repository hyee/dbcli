local db=env.getdb()

local ps=env.class(db.C.sql)
function ps:ctor()
    self.db=env.getdb()
    self.command="ps"
    self.help_pstle='Run SQL script on under the "ps" directory depending on the `sys` and `performance_schema`.'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."ps",{}
end

function ps:run_sql(sql,args,cmds,files)
    return self.super.run_sql(self,sql,args,cmds,files)
end

return ps.new()