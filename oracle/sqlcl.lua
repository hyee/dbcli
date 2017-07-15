local env=env
local sqlcl={}

function sqlcl.start(...)
	local db=env.getdb()
	local params={...}
	table.insert(params,1,env.packer.unpack_str(db.conn_str) or "/nolog")
	table.insert(params,1,"-L")
	console:startSqlCL(params)
end

function sqlcl.onload()
	env.set_command{cmd="sqlcl",is_blocknewline=true,nil,nil,"Switch to SqlCl",sqlcl.start,false,10,true}
end

return sqlcl