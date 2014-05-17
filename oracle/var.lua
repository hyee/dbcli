local env=env
local grid,snoop=env.grid,env.event.snoop
local var={inputs={},outputs={}}

var.types={
	REFCURSOR =  'CURSOR',
	CURSOR    =  'CURSOR',
	VARCHAR2  =  'VARCHAR',
	VARCHAR   =  'VARCHAR',
	NUMBER    =  'NUMBER',
	CLOB      =  'CLOB',
	CHAR      =  'VARCHAR',
	NCHAR     =  'VARCHAR',
	NVARCHAR2 =  'VARCHAR',
	BOOLEAN   =  'BOOLEAN'
}
function var.helper()
	local help=[[
		Define output variables for db execution. Usage: "var <name> <data type>", or "var <name>" to remove
		    Define variable: var <name> <data_type>
		    Remove variable: var <name>
		Available Data types:
		====================
		REFCURSOR CURSOR CLOB NUMBER CHAR VARCHAR VARCHAR2 NCHAR NVARCHAR2 BOOLEAN]]
	return help
end


function var.setOutput(name,datatype)
	if not name then 
		return env.helper.helper("VAR")
	end
	
	name=name:upper()
	if not datatype then
		if var.outputs[name] then var.outputs[name]=nil end
	end

	datatype=datatype:upper():match("(%w+)")	
	assert(var.types[datatype],'ORA-20011: Expected data type['..datatype..']!')
	assert(name:match("^[%w%$_]+$"),'ORA-20011: Expected variable name['..name..']!')
	if var.inputs[name] then  return print("The name["..name.."] has ben defined as input parameter!") end
	var.outputs[name]='#'..var.types[datatype]
end

function var.setInput(name)
	if not name or name=="" then
		print("Current defined variables:\n====================")
		for k,v in pairs(var.inputs) do
			if type(v)~="table" then
				print("    ",k,'=',v)
			end
		end
		return
	end
	if name:find('=') then 
		name,value=name:match("^([^=%s]+)%s*=%s*(.*)")
		if not value then return end
	elseif name:find(' ') then 	
		name,value=name:match("^([^=%s]+)%s+(.*)")
		if not value then return end
	end
	name=name:upper()
	if not name:match("^([%w_$]+)$") then return print("The name["..name.."] is not a valid syntax!") end
	if var.outputs[name] then  return print("The name["..name.."] has ben defined as  output parameter!") end
	var.setInputs(name,value)	
end

function var.setInputs(name,args)
	if not args then
		if var.inputs[name] then var.inputs[name]=nil end
		return
	end
	var.inputs[name]=args
end

function var.before_db_exec(db,sql,args)
	for k,v in pairs(var.outputs) do
		if not args[k] then
			args[k]=v
		end
	end

	for name,v in pairs(var.inputs) do
		if type(v)=="table" then
			for i,j in pairs(v) do
				if not args[i] then args[i]=j end
			end
		elseif not args[name] then
			args[name]=v
		end
	end
end

function var.after_db_exec(db,sql,args)
	if db:is_internal_call(sql) then return end
	local result={{'Argument','Value'}}
	for k,v in pairs(var.outputs) do
		if v and k:upper()==k and args[k] and args[k]~=v then
			if v=="#CURSOR" then
				db.resultset:print(args[k],db.conn)
			else
				result[#result+1]={k,args[k]}
			end
			args[k]=v
		end
	end

	if #result>1 then
		grid.print(result)
	end
end

snoop('BEFORE_ORACLE_EXEC',var.before_db_exec)
snoop('AFTER_ORACLE_EXEC' ,var.after_db_exec)

env.set_command(nil,{"variable","VAR"},var.helper,var.setOutput,false,3)
env.set_command(nil,{"Define","DEF"},"Define input variables, Usage: def <name>=<value>, or def <name> to remove definition",var.setInput,false,2)
return var