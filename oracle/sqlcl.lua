local env,db,os,java=env,env.getdb(),os,java
local ora=db.C.ora
local sqlcl=env.class(db.C.sqlplus)

function sqlcl:ctor()
    self.db=env.getdb()
    self.command="sql"
    self.name="sqlcl"
    self.description="Switch to sqlcl with same login, the default working folder is 'oracle/sqlplus'. Usage: @@NAME [-n|-d<work_path>] [other args]"
    self.help_title='Run SQL*Plus script under the "sqlplus" directory with sqlcl. '
    self.block_input=true
    self.support_redirect=true
end

function sqlcl.start(...)
	local db=env.getdb()
	local params={...}
	table.insert(params,1,env.packer.unpack_str(db.conn_str) or "/nolog")
	table.insert(params,1,"-L")
	console:startSqlCL(params)
end

function sqlcl:get_startup_cmd(args,is_native)
	local props=self.super:get_startup_cmd(args,is_native)
	if not is_native then 
		console:startSqlCL(props)
		return nil 
	end
	self.boot_cmd=env.join_path(java.system.getProperty("java.home")..'/bin/java')
	local libs=java.system.getProperty("java.class.path");
	libs=libs:gsub(env.IS_WINDOWS and '(;)%.' or '(:)%.','%1..')
	local starts={
		"-cp",
		libs,
		"oracle.dbtools.raptor.scriptrunner.cmdline.SqlCli"
	}
	for i=#starts,1,-1 do
		table.insert(props,1,starts[i])
	end
    return props,true
end


function sqlcl:onload()
	--env.set_command{cmd="sqlcl",is_blocknewline=true,nil,nil,"Switch to SqlCl",sqlcl.start,false,10,true}
end

return sqlcl.new()