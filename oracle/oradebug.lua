local env,printer,grid=env,env.printer,env.grid
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local sqlplus=db.C.sqlplus
local oradebug={}
local writer=writer
local datapath=env.join_path(env.WORK_DIR,'oracle/oradebug.pack')

local function get_output(cmd)
	local output,clear=printer.get_last_output,printer.clear_buffered_output
	if not sqlplus.process then
		sqlplus:call_process(nil,true)
		clear()
	end
	print('Running command: '..cmd)
	local out=sqlplus:get_lines(cmd)
	if not out then
		return get_output(cmd)
	end
	return out:gsub('%z',''):split('\n\r?')
end

local ext={
	DUMP={},
	LKDEBUG={
		hashcount={" -a hashcount","ges resource hash count"}
	}
}
function oradebug.build_dict(action)
	local libs
	if action and action:lower() == 'init' then
		db:assert_connect()
		libs={NAME={},SCOPE={},FILTER={},ACTION={},COMPONENT={},HELP={HELP={}},_keys={}}
		local lib_pattern='^%S+.- in library (.*):'
		local item_pattern
		local curr_lib,prefix,prev,prev_prefix
		local scope,sub
		local keys=libs['_keys']
		for _,n in ipairs{'NAME','SCOPE','FILTER','ACTION'} do
			sub=libs[n]
			scope=get_output("oradebug doc event "..n)
			curr_lib=nil
			item_pattern=n=='ACTION' and '^(%S+)(.*)' or '^(%S+)%s+(.*)' 
			for idx,line in ipairs(scope) do
				if n~='ACTION' then line=line:trim() end
				local p=line:match(lib_pattern)
				if p then
					p=p:trim()
					curr_lib=p
					sub[p]={}
					keys[p:upper()]='Library'
					prev=nil
				elseif curr_lib and not line:trim():find('^%-+$') then
					local item,desc=line:rtrim():match(item_pattern)
					if item then
						desc=desc:trim()
						local org=item
						item=item:gsub('[%[%] ]','')
						for i = 1,2 do
							local key=((i==1 and '' or (curr_lib..'.'))..item):upper()
							if keys[key] then
								keys[key]=keys[key]..','..'EVENT.'..n..'.'..item
							else
								keys[key]='EVENT.'..n..'.'..item
							end
						end
						local buff=get_output("oradebug doc event "..n..' '..curr_lib..'.'..item)
						while buff[1] and buff[1]:trim()=='' do table.remove(buff,1) end
						local usage=table.concat(buff,'\n')
						prefix=buff[1]:match('^%s+')
						if prefix then usage=usage:sub(#prefix+1):gsub('[\n\r]+'..prefix,'\n') end
						if usage==desc then usage=nil end
						prev={desc=desc:gsub('%s+',' '),usage=usage}
						sub[curr_lib][org]=prev
					elseif n=='ACTION' and prev and line:trim() ~= '' then
						prev.desc=prev.desc..(prev.desc=='' and '' or '\n')..line:trim()
					end
				end
			end
		end
		
		item_pattern='^(%s+%S+)%s+(.+)'
		scope=get_output("oradebug doc component")
		sub=libs['COMPONENT']
		curr_lib=nil
		for idx,line in ipairs(scope) do
			local p=line:match(lib_pattern)
			if p then
				p=p:trim()
				curr_lib=p
				sub[p]={}
				prev,prev_prefix=nil
				keys[p:upper()]='Library'
			elseif curr_lib then
				local item,desc=line:match(item_pattern)
				if item then
					prefix,item=item:match('(%s+)(%S+)')
					desc=desc:trim()
					local key=item:upper()
					for i=1,2 do
						local key=((i==1 and '' or (curr_lib..'.'))..item):upper()
						if keys[key] then
							keys[key]=keys[key]..','..'COMPONENT.'..item
						else
							keys[key]='COMPONENT.'..item
						end
					end
					
					if prev_prefix and #prefix>#prev_prefix then
						prev.is_parent=true
					end
					prev,prev_prefix={desc=desc,usage=usage},prefix

					local buff=get_output("oradebug doc component "..curr_lib..'.'..item)
					while buff[1] and buff[1]:trim()=='' do table.remove(buff,1) end
					local usage=table.concat(buff,'\n')
					prefix=buff[1]:match('^%s+')
					if prefix then usage=usage:sub(#prefix+1):gsub('[\n\r]+'..prefix,'\n') end
					if usage~=desc then prev.usage=usage end
					sub[curr_lib][item]=prev
				end
			end
		end

		sub=libs['HELP']['HELP']
		scope=get_output("oradebug help")
		item_pattern='^(%S+)%s+(.+)'
		curr_lib=nil
		
		for idx,line in ipairs(scope) do
			local item,desc=line:match(item_pattern)
			if item then
				prev=nil
				local key=item:upper()
				if keys[key] then
					keys[key]=keys[key]..','..'HELP.'..item
				else
					keys[key]='HELP.'..item
				end
				local buff=get_output("oradebug "..(item:lower()=="dumplist" and '' or 'help ')..item)
				while buff[1] and buff[1]:trim()=='' do table.remove(buff,1) end
				local usage=table.concat(buff,'\n')
				prefix=buff[1]:match('^%s+')
				if prefix then usage=usage:gsub('[\n\r]+'..prefix,'\n'):trim() end
				if usage==desc then usage=nil end
				prev={desc=desc:trim():gsub('%s+',' '),usage=usage}
				sub[item]=prev
			elseif prev and line:trim() ~= '' then
				prev.desc=prev.desc..(prev.desc=='' and '' or '\n')..line:trim()
			end
		end

		scope=get_output("oradebug doc event")
		sub['EVENT']={desc='Set trace event in process',usage=table.concat(scope,'\n')}
		keys['HELP'],keys['EVENT'],keys['DOC']='Library','DOC','DOC'

		sqlplus:terminate()
		env.save_data(datapath,libs)
	elseif not oradebug.dict then
		libs=env.load_data(datapath,true)
	else
		libs=oradebug.dict
	end
	oradebug.dict=libs

	local usage
	if action and action:lower() ~= 'init' then
		action=action:upper()
		local key=libs['_keys'][action]
		if key=='DOC' then
			return print(libs['HELP']['HELP']['EVENT'].usage)
		end
		local libs1={}
		for name,lib in pairs(libs) do
			if name~='_keys' then
				libs1[name]={}
				for k,v in pairs(lib) do
					if key=='Library' and k:upper()==action then
						libs1[name][k]=v
					elseif key~='Library' then
						libs1[name][k]={}
						for n,d in pairs(v) do
							if key and (action==n:upper() or action==(k..'.'..n):upper()) then
								libs1[name][k][n]=d
								if d.usage then
									if not usage and name~='HELP' and name~='COMPONENT' then
										print([[Formal Event Syntax: alter session set events '<event_spec>'
--------------------
    <event_spec>   ::= '<event_id> [<event_scope>]
                                   [<event_filter_list>]
                                   [<event_parameters>]
                                   [<action_list>]
                                   [off]'
	    <event_id>          ::= <event_name | number>[<target_parameters>]
        <event_scope>       ::= [<scope_name>: scope_parameters]
        <event_filter>      ::= {<filter_name>: filter_parameters}
        <action>            ::= <action_name>(action_parameters)
        <action_parameters> ::= <parameter_name> = [<value>|<action>][, ]
        <*_parameters>      ::= <parameter_name> = <value>[,] ]]..'\n\n')
									end
									usage=d.usage
									local target=(name..'.') 
									if name=='COMPONENT' then
										target=target..k..'.'
									elseif name~='HELP' then
										target='EVENT.'..target..k..'.'
									end
									target=target..n
									print('\n'..string.rep('=',#target+2)..'\n|'..target..'|\n'..string.rep('-',#target+2))
									print(usage..'\n')
								end
							elseif (n:upper():find(action,1,true) or d.desc:upper():find(action,1,true) or (d.usage or ''):upper():find(action,1,true)) then
								libs1[name][k][n]=d
							end
						end
					end
				end
			end
		end
		libs=libs1
		--if usage then return end
	end

	local rows={{'Class','Library','Item','Description'}}
	for name,lib in pairs(libs) do
		if name~='_keys' then
			for k,v in pairs(lib) do
				for n,d in pairs(v) do
					rows[#rows+1]={(name=='COMPONENT' or name=='HELP') and name or ('EVENT.'..name),k,n..(d.is_parent and '.*' or ''),d.desc}
				end
			end
		end
	end
	grid.sort(rows,"Class,Library,Item",true)
	grid.print(rows)
end

function oradebug.onload()
	env.set_command(nil,'ORADEBUG',"Show or create dictionary for available OraDebug commands. Usage: @@NAME [init|<keyword>]",oradebug.build_dict,false,2)
end
return oradebug