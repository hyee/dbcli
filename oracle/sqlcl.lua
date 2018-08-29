local env,db,os,java=env,env.getdb(),os,java
local ora=db.C.ora
local sqlcl=env.class(db.C.sqlplus)

function sqlcl:ctor()
    self.db=env.getdb()
    self.executable="sql"
    self.command="sql"
    self.name="sqlcl"
    self.description="Switch to sqlcl with same login, the default working folder is 'oracle/sqlplus'. Usage: @@NAME [-n|-d<work_path>] [other args]"
    self.help_title='Run SQL*Plus script under the "sqlplus" directory with sqlcl. '
    self.block_input=true
    self.support_redirect=false
end

function sqlcl:onload()
end
return sqlcl.new()