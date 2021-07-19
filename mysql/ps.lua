local db=env.getdb()

local ps=env.class(db.C.sql)
function ps:ctor()
    self.db=env.getdb()
    self.command="ps"
    self.help_pstle='Run SQL script on under the "ps" directory depending on the `sys` and `performance_schema`.'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."ps",{}
end

local server,user,id
function ps:run_sql(sql,args,cmds,files)
    local props=db.props
    if props.db_server~=server or props.db_user~=user or props.db_conn_id~=id then
        local done,val=pcall(db.get_value,db,"SELECT COUNT(1) FROM information_schema.schemata WHERE lower(schema_name) in('performance_schema','sys')")
        env.checkerr(done and val==2,"You have no access rights on `performance_schema`, or `performance_schema` is not setup.")
        server,user,id=props.db_server,props.db_user,props.db_conn_id
    end
    return self.super.run_sql(self,sql,args,cmds,files)
end

return ps.new()