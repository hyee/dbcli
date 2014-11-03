local env=env
local db,grid=env.oracle,env.grid
local cfg=env.set
local ora={script_dir=env.WORK_DIR.."oracle"..env.PATH_DEL.."ora"}
ora.comment="/%*[\t\n\r%s]*%[%[(.*)%]%][\t\n\r%s]*%*/"
local ARGS_COUNT=20
function ora.rehash(script_dir,ext_name)
	local keylist=env.list_dir(script_dir,ext_name or "sql",ora.comment)
	local cmdlist={}
	for k,v in ipairs(keylist) do
		local desc=v[3] and v[3]:gsub("^[\n\r%s\t]*[\n\r]+","") or ""
		desc=desc:gsub("%--%[%[(.*)%]%]%--","")
		cmdlist[v[1]:upper()]={path=v[2],desc=desc,short_desc=desc:match("([^\n\r]+)") or ""}
	end

	local additions={
		{'-R','Reflash the help file and available commands'},
		{'-P','Verify the paramters/templates of the target script, instead of running it. Usage:  -p <cmd> [<args>]'},
		{'-H','Show the help detail of the target command. Usage:  -h <command>'},
		{'-S','Search available command with inputed keyword. Usage:  -s <keyword>'},
	}

	for k,v in ipairs(additions) do
		cmdlist[v[1]]={desc=v[2],short_desc=v[2]}
	end	

	return cmdlist
end

--[[
Available parameters:
   Input bindings:  from :V1 to :V9
   Replacement:     from &V1 to &V9, used to replace the wildchars inside the SQL stmts
   Out   bindings:  :<alphanumeric>, the data type of output parameters should be defined in th comment scope
--]]-- 
function ora.parse_args(sql,args,print_args)
	local desc=sql:match(ora.comment)
	local outputlist={}
	local outputcount=0
	local arg1={}
	args=args or {}
	for i=1,ARGS_COUNT do
		arg1["V"..i]=args["V"..i] or args[i]  or ""
		--print(i,args[i])
	end
	args,arg1=arg1,{}
	local function setvalue(name,value,source)
		if not arg1[name] then arg1[name]={args[name]} end
		arg1[name][2],args[name]=source and (name..'.'..source),value
	end
	--parse template
	local patterns,templates,ids={"(%b{})","([^\n\r]-)%s*[\n\r]"},{},{}
	if desc then		
		sql=sql:gsub(ora.comment,"")		
		--Parse the  &<V1-V30> and :<V1-V30> grammar, refer to ashtop.sql
		for _,p in ipairs(patterns) do
			for k,v in desc:gmatch('[&:](V[%d+])%s*:%s*'..p) do
				if not templates[k] then
					local forms={}
					local default
					if v:sub(-1)=="}" then						
						for id,template in v:gmatch("([%w_-]+)%s*=%s*(%b{})") do
							id,template=id:upper(),template:sub(2,-2)							
							forms[id],ids[id]=template,{template,k.."."..id}
							default=default and default or id
						end
					else
						default,forms[1]=1,v
					end					
					forms.__df=default or 0
					templates[k]=forms
				end
			end
		end

		--Parse the @paramters that related to database version
		local db_version=(db.props.db_version or "8.0.0.0"):split("%.")

		for _,p in ipairs(patterns) do
			for k,v in desc:gmatch('@([%w_]+)%s*:%s*'..p) do
				k=k:upper()
				if not args[k] then
					local forms={}
					local default
					if v:sub(-1)=="}" then						
						for id,template in v:gmatch("([%d%.]+)%s*=%s*(%b{})") do
							id,template=id,template:sub(2,-2)											
							forms[id],ids[id]=template,{template,k.."."..id}
							local vers=id:split("%.")
							if not default then
							    default=nil						
								for k,v in ipairs(vers) do
									local i1,i2=tonumber(db_version[k]) or 0,tonumber(v)
									if i1>i2 then
										break
									elseif i1<i2 then
										default=false
										break
									end
								end
								if default~=false then default=id end
							end
						end
						if not default then 
							return print("This command doesn't support current db version["..db.props.db_version.."]!")
						end
					else
						default,forms[1]=1,v
					end					
					forms.__df=default or 0
					forms.__sel=default or 0
					templates[k]=forms
					args[k]=""
					setvalue(k,forms[forms.__df] or "",default)					
				end
			end
		end
	end
	
	

	--Start to assign template value to args
	local i=1
	while true do
		if i>ARGS_COUNT then break end		
		local k,v="V"..i,args["V"..i]
		if templates[k] then --Replace value with template values
			local forms=templates[k]
			if v=="" then --in case of org value is null, replaced with template default value
				setvalue(k,forms[forms.__df] or "",forms.__df)
				forms.__sel=forms.__df
			elseif forms[v:upper()] then
				setvalue(k,forms[v:upper()],v:upper())
				forms.__sel=v:upper()
			end
		end

		if v:sub(1,1)=="-"  then--support "-<template id>" syntax in random places
			local idx,rest=v:sub(2):match("^([%w_-]+)(.*)$")
			idx=(idx or ""):upper()
			if ids[idx] then
				local k1,i1,tmp=ids[idx][2]:match("^(V(%d+))")
				i1=tonumber(i1)
				if i1>=i then
					setvalue(k,"",nil)
					if rest:sub(1,1)=='"' and rest:sub(-1)=='"' then rest=rest:sub(2,-2) end
					setvalue(k1,ids[idx][1]..rest,idx)	
					templates[k1].__sel=idx
					if i1 > i then
						local pre_idx='V'..i
						for j=i+1,ARGS_COUNT do
							local new_idx='V'..j
							if not arg1[new_idx] then
								args[pre_idx],args[new_idx]=args[new_idx],""
								pre_idx=new_idx
							end
						end
					end
					i=i-1
				end
			end
		end
		i=i+1
	end


	if print_args then
		local rows={{"Variable","Id","Default?","Selected?","Value"}}
		local rows1={{"Variable","Mapping","Origin","Final"}}
		local keys={}
		for k,v in pairs(args) do
			keys[#keys+1]=k
		end

		table.sort(keys,function(a,b)
			local a1,b1=tostring(a):match("^V(%d+)$"),tostring(b):match("^V(%d+)$")
			if a1 and b1 then return tonumber(a1)<tonumber(b1) end
			if a1 then return true end
			if b1 then return false end
			if type(a)==type(b) then return a<b end
			return tostring(a)<tostring(b)
		end)

		for _,k in ipairs(keys) do
			local ind=0
			local v1,v,src=args[k],templates[k],arg1[k] or {}
			if type(v)=="table" then
				local default,select=v.__df,v.__sel
				for id,template in pairs(v) do					
					if id~="__df" and id~="__sel" then
						ind=ind+1
						rows[#rows+1]={ind==1 and k or "",
						               id,
						               default==id and "Y" or "N",
						               select==id and "Y" or "N",
						               (template:gsub("[\t%s]+"," "))}
					end				
				end
				if #rows>1 then rows[#rows+1]={""} end
			end
			rows1[#rows1+1]={k,src[2] or "",((src[1] or v1):gsub("[\t%s]+"," ")),(v1:gsub("[\t%s]+"," "))}
		end

		for k,v in pairs(db.C.var.inputs) do
			if type(k)=="string" and k:upper()==k and type(v)=="string" then
				rows1[#rows1+1]={k,"cmd 'def'",v,v}
			end
		end

		print("Templates:\n================")
		--grid.sort(rows,1,true)
		grid.print(rows)

		print("\nInputs:\n================")
		grid.print(rows1)
	end
	return args
end

function ora.run_sql(sql,args,print_args)
	if not db:is_connect() then
		env.raise("database is not connected !")
	end
	args=ora.parse_args(sql,args,print_args)
	if print_args or not args then return end
	--remove comment
	sql=sql:gsub(ora.comment,"",1)
	sql=('\n'..sql):gsub("\n[\t%s]*%-%-[^\n]*","")
	sql=('\n'..sql):gsub("\n%s*/%*.-%*/",""):gsub("/[\n\r\t%s]*$","")
	local sq="",cmd,params,pre_cmd,pre_params
	local cmds=env._CMDS
	
	cfg.backup()
	cfg.set("HISSIZE",0)
	db.C.var.setInputs("oracle.ora",args)
	local eval=env.eval_line
	for line in sql:gsplit("[\n\r]+") do
		eval(line)
	end
	if env.pending_command() then
		eval("/")
	end
	cfg.restore()
	db.C.var.setInputs("oracle.ora")
end

function ora.run_script(cmd,...)
	if not ora.cmdlist or cmd=="-r" or cmd=="-R" then
		ora.cmdlist=ora.rehash(ora.script_dir)
		local keys={}
		for k,_ in pairs(ora.cmdlist) do
			keys[#keys+1]=k
		end 
		env.ansi.addCompleter("ORA",keys)
	end

	if not cmd then
		return env.helper.helper("ORA")
	end

	cmd=cmd:upper()	
	local args,print_args={...},false
	if cmd=="-R" then
		return
	elseif cmd=="-H" then
		return  env.helper.helper("ORA",args[1])
	elseif cmd=="-P" then
		cmd,print_args=args[1] and args[1]:upper() or "/",true
		table.remove(args,1)
	elseif cmd=="-S" then
		return env.helper.helper("ORA","-S",...)
	end

	env.checkerr(ora.cmdlist[cmd],"Cannot find this script!")	
	local f=io.open(ora.cmdlist[cmd].path)
	env.checkerr(f,"Script file is missing during runtime!")
	local sql=f:read('*a')
	f:close()
	ora.run_sql(sql,args,print_args)
end

local help_ind=0
function ora.helper(_,cmd,search_key)	
	local help='Run SQL script under the "ora" directory. Usage: ora [<script_name>|-r|-p|-h|-s] [parameters]\nAvailable commands:\n=================\n'
	help_ind=help_ind+1
	if help_ind==2 and not ora.cmdlist then
		ora.run_script('-r')
	end
	return env.helper.get_sub_help(cmd,ora.cmdlist,help,search_key)	
end

env.set_command(nil,"ora", ora.helper,ora.run_script,false,ARGS_COUNT)

return ora