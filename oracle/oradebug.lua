local env,printer,grid=env,env.printer,env.grid
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local sqlplus=db.C.sqlplus
local oradebug={_pid='setmypid'}
local writer=writer
local datapath=env.join_path(env.WORK_DIR,'oracle/oradebug.pack')

local function get_output(cmd,is_comment)
	local output,clear=printer.get_last_output,printer.clear_buffered_output
	db:assert_connect()
	env.checkerr(db.props and db.props.isdba,"oradebug only supports SYSDBA.")
	if not sqlplus.process then
		sqlplus:call_process(nil,true)
		sqlplus:get_lines("oradebug "..oradebug._pid)
		clear()
	end
	cmd='oradebug '..cmd
	if is_comment~=false then print('Running command: '..cmd) end
	local out=sqlplus:get_lines(cmd)
	if is_comment==false then 
		if out then 
			print(out)
			sqlplus:call_process('bye',true)
		end
	end
	if not out then return get_output(cmd) end
	return out:gsub('%z',''):split('\n\r?')
end

local no_args={
    CLOSE_TRACE=1,
    CORE=1,
    CURRENT_SQL=1,
    DUMPLIST=1,
    FFBEGIN=1,
    FFDEREGISTER=1,
    FFRESUMEINST=1,
    FFSTATUS=1,
    FFTERMINST=1,
    FLUSH=1,
    IPC=1,
    IPC_TRACE=1,
    PROCSTAT=1,
    RESUME=1,
    SETMYPID=1,
    SHORT_STACK=1,
    SUSPEND=1,
    TRACEFILE_NAME=1,
    UNLIMIT=1
}

local traces={
	SQL_TRACE={
		'Dump SQL Trace',
	   [[* oradebug event sql_trace[SQL: 32cqz71gd8wy3] {pgadep: exactdepth 0} plan_stat=all_executions,wait=true,bind=true
	     * oradebug event sql_trace[SQL: 32cqz71gd8wy3] {pgadep: exactdepth 0} {callstack: fname opiexe} plan_stat=all_executions,wait=true,bind=true
	     * oradebug event sql_trace wait=true, plan_stat=never
	     * oradebug event sql_trace [sql: g3yc1js3g2689 | 7ujay4u33g337
	     * oradebug event sql_trace [sql: sql_id=g3yc1js3g2689 | sql_id=7ujay4u33g337] ]]
	},
	TRACE={'Dump trace to disk',
		[[* oradebug event trace[RDBMS.SQL_Transform] [SQL: 32cqz71gd8wy3] disk=high RDBMS.query_block_dump(1) processstate(1) callstack(1)
		  * oradebug event trace[sql_mon.*] memory=high,get_time=highres
		]]

	},
	SQL_MONITOR={'Force SQL Monitor on specific SQL ID',
	[[* oradebug event sql_monitor [sql: 5hc07qvt8v737] force=true]]}
}

local ext={
	HANGANALYZE={
		{'HANGANALYZE <level>',
		 [[Analyze System Hangs.
			Level:
		    1-2 Only HANGANALYZE output, no process dump at all
		    3   Level 2 + Dump only processes thought to be in a hang (IN_HANG state)
		    4   Level 3 + Dump leaf nodes (blockers) in wait chains (LEAF,LEAF_NW,IGN_DMP state)
		    5   Level 4 + Dump all processes involved in wait chains (NLEAF state)
		    10  Dump all processes (IGN state)]],
		 [[oradebug setmypid
		    oradebug unlimit
		    oradebug setinst all
		    oradebug hanganalyze 5
		    oradebug -g def dump systemstate 10]]
		}
	},
	DUMP={
		{'ADJUST_SCN','',''},
		{'ALRT_TEST','',''},
		{'ARCHIVE_ERROR','',''},
		{'ASHDUMP','',''},
		{'ASHDUMPSECONDS','',''},
		{'ASMDISK_ERR_OFF','',''},
		{'ASMDISK_ERR_ON','',''},
		{'ASMDISK_READ_ERR_ON','',''},
		{'ATSK_TEST','',''},
		{'AWR_DEBUG_FLUSH_TABLE_OFF','',''},
		{'AWR_DEBUG_FLUSH_TABLE_ON','',''},
		{'AWR_FLUSH_TABLE_OFF','',''},
		{'AWR_FLUSH_TABLE_ON','',''},
		{'AWR_TEST','',''},
		{'BC_SANITY_CHECK','',''},
		{'BGINFO','',''},
		{'BG_MESSAGES','',''},
		{'BLK0_FMTCHG','',''},
		{'BUFFER','',''},
		{'BUFFERS <level>',
		[[Dump of buffer cache.
		Level:
		* 1 dump the buffer headers only
		* 2 include the cache and transaction headers from each block
		* 3 include a full dump of each block
		* 4 dump the working set lists and the buffer headers and the cache header for each block
		* 5 include the transaction header from each block
		* 6 include a full dump of each block
		Most levels high than 6 are equivalent to 6, except that levels 8 and 9 are the same as 4 and 5 respectively.
		For level 1 to 3 the information is dumped in buffer header order.
		For levels higher than 3, the buffers and blocks are dumped in hash chain order.]],''},
		{'CALLSTACK','',''},
		{'CBDB_ENTRIES','',''},
		{'CGS','',''},
		{'CHECK_ROREUSE_SANITY','',''},
		{'CONTEXTAREA','',''},
		{'CONTROLF <level>',
		[[The contents of the current controlfile can be dumped in text form to a process trace file in the user_dump_dest directory using the CONTROLF dump.
		  Level:
		  * 1  only the file header
		  * 2  just the file header, the database info record, and checkpoint progress records
		  * 3  all record types, but just the earliest and latest records for circular reuse record types
		  * 4  as above, but includes the 4 most recent records for circular reuse record types
		  * 5+ as above, but the number of circular reuse records included doubles with each level]],'oradebug dump controlf 4'},
		{'CROSSIC','',''},
		{'CRS','',''},
		{'CSS','',''},
		{'CURSORDUMP','',''},
		{'CURSORTRACE','',''},
		{'CURSOR_STATS','',''},
		{'DATA_ERR_OFF','',''},
		{'DATA_ERR_ON','',''},
		{'DATA_READ_ERR_ON','',''},
		{'DBSCHEDULER','',''},
		{'DEAD_CLEANUP_STATE','',''},
		{'DROP_SEGMENTS','',''},
		{'DUMPGLOBALDATA','',''},
		{'DUMP_ADV_SNAPSHOTS','',''},
		{'DUMP_ALL_COMP_GRANULES','',''},
		{'DUMP_ALL_COMP_GRANULE_ADDRS','',''},
		{'DUMP_ALL_OBJSTATS','',''},
		{'DUMP_ALL_REQS','',''},
		{'DUMP_PINNED_BUFFER_HISTORY','',''},
		{'DUMP_SGA_METADATA','',''},
		{'DUMP_TEMP','',''},
		{'DUMP_TRANSFER_OPS','',''},
		{'ENQUEUES','',''},
		{'ERRORSTACK <level>',
		[[Dump of the process call stack and other information.
		 Level:
		 0 dump error buffer
		 1 level 0 + call stack
		 2 level 1 + process state objects
		 3 level 2 + context area]],
		[[1. oradebug dump errorstack 3
		  2. oradebug event immediate trace name errorstack level 3
		  3. oradebug event 942 trace name errorstack level 3]]},
		{'EVENT_TSM_TEST','',''},
		{'EXCEPTION_DUMP','',''},
		{'FAILOVER','',''},
		{'FBHDR','',''},
		{'FBINC','',''},
		{'FBTAIL','',''},
		{'FILE_HDRS <level>',
		[[Dump datafile headers.
		  Level:
		    1 Record of datafiles in controlfile ( for practice compare with controlfile dump)
			2 Level 1 + generic information
			3 Level 2 + additional datafile header information.]],'oradebug dump file_hdrs 10'},
		{'FLASHBACK_GEN','',''},
		{'FLUSH_BUFFER','',''},
		{'FLUSH_CACHE','',''},
		{'FLUSH_JAVA_POOL','',''},
		{'FLUSH_OBJECT','',''},
		{'FULL_DUMPS','',''},
		{'GC_ELEMENTS','',''},
		{'GES_STATE','',''},
		{'GIPC','',''},
		{'GLOBAL_AREA','',''},
		{'GLOBAL_BUFFER_DUMP','',''},
		{'GWM_TEST','',''},
		{'GWM_TRACE','',''},
		{'HANGANALYZE','',''},
		{'HANGANALYZE_GLOBAL','',''},
		{'HANGANALYZE_PROC','',''},
		{'HANGDIAG_HEADER','',''},
		{'HEAPDUMP <level>',
		[[Dump structure of a memory heap.
		Level:
		* 1  include PGA heap
		* 2  include Shared Pool
		* 4  include UGA heap
		* 8  include CGA heap
		* 16 include Top CGA
		* 32 include Large Pool','oradebug dump heapdump 5 <--this dumps PGA and UGA heaps'},
		{'HEAPDUMP_ADDR <level> <address>',
		[[Dump structure of a memory heap with specific address.
		  Level:
		  * 1 dump structure
		  * 2 also include contents]],'oradebug dump heapdump_addr 1 3087751692'},
		{'HM_FDG_VERS','',''},
		{'HM_FW_TRACE','',''},
		{'HNGDET_MEM_USAGE_DUMP','',''},
		{'IMDB_PINNED_BUFFER_HISTORY','',''},
		{'INSTANTIATIONSTATE','',''},
		{'IOERREMUL','',''},
		{'IOERREMULRNG','',''},
		{'IR_FW_TRACE','',''},
		{'JAVAINFO','',''},
		{'KBRS_TRACE','',''},
		{'KCBI_DUMP_FREELIST','',''},
		{'KCBO_OBJ_CHECK_DUMP','',''},
		{'KCBS_ADV_INT_DUMP','',''},
		{'KCB_WORKING_SET_DUMP','',''},
		{'KDFSDMP','',''},
		{'KDLIDMP','',''},
		{'KRA_OPTIONS','',''},
		{'KRBMROR_LIMIT','',''},
		{'KRBMRSR_LIMIT','',''},
		{'KRB_BSET_DAYS','',''},
		{'KRB_CORRUPT_INTERVAL','',''},
		{'KRB_CORRUPT_OFFSET','',''},
		{'KRB_CORRUPT_REPEAT','',''},
		{'KRB_CORRUPT_SIZE','',''},
		{'KRB_CORRUPT_SPBAD_INTERVAL','',''},
		{'KRB_CORRUPT_SPBAD_SIGNAL','',''},
		{'KRB_CORRUPT_SPBITMAP_INTERVAL','',''},
		{'KRB_CORRUPT_SPBITMAP_REPEAT','',''},
		{'KRB_CORRUPT_SPHEADER_INTERVAL','',''},
		{'KRB_CORRUPT_SPHEADER_REPEAT','',''},
		{'KRB_FAIL_INPUT_FILENO','',''},
		{'KRB_OPTIONS','',''},
		{'KRB_OPTIONS2','',''},
		{'KRB_OVERWRITE_ACTION','',''},
		{'KRB_PIECE_FAIL','',''},
		{'KRB_SET_TIME_SWITCH','',''},
		{'KRB_SIMULATE_NODE_AFFINITY','',''},
		{'KRB_UNUSED_OPTION','',''},
		{'KRDRSBF','',''},
		{'KSDTRADV_TEST','',''},
		{'KSFQP_LIMIT','',''},
		{'KSKDUMPTRACE','',''},
		{'KSTDUMPALLPROCS','',''},
		{'KSTDUMPALLPROCS_CLUSTER','',''},
		{'KSTDUMPCURPROC','',''},
		{'KTPR_DEBUG','',''},
		{'KUPPLATCHTEST','',''},
		{'KXFPBLATCHTEST','',''},
		{'KXFPCLEARSTATS','',''},
		{'KXFPDUMPTRACE','',''},
		{'KXFRHASHMAP','',''},
		{'KXFXCURSORSTATE','',''},
		{'KXFXSLAVESTATE','',''},
		{'LATCHES','Dump the latches for a specified process','oradebug dump LATCHES 1'},
		{'LDAP_KERNEL_DUMP','',''},
		{'LDAP_USER_DUMP','',''},
		{'LIBRARY_CACHE <level>',
		[[Dump library cache statistics.
		  Level:
		  * 1 dump libracy cache statistics
		  * 2 also include a hash table
		  * 3 level 2 + dump of the library object handles
		  * 4 Level 3 + dump of the heap]],'oradebug dump library_cache 2'},
		{'LIBRARY_CACHE_OBJECT','',''},
		{'LOCKS','',''},
		{'LOGERROR','',''},
		{'LOGHIST','',''},
		{'LONGF_CREATE','',''},
		{'LREG_STATE','',''},
		{'MGA','',''},
		{'MMAN_ALLOC_MEMORY','',''},
		{'MMAN_CREATE_DEF_REQUEST','',''},
		{'MMAN_CREATE_IMM_REQUEST','',''},
		{'MMAN_IMM_REQUEST','',''},
		{'MMON_TEST','',''},
		{'MODIFIED_PARAMETERS','',''},
		{'NEXT_SCN_WRAP','',''},
		{'OBJECT_CACHE','',''},
		{'OCR','',''},
		{'OLAP_DUMP','',''},
		{'OPEN_FILES','',''},
		{'PDBSTATS','',''},
		{'PGA_DETAIL_CANCEL','',''},
		{'PGA_DETAIL_DUMP','',''},
		{'PGA_DETAIL_GET','',''},
		{'PGA_SUMMARY','',''},
		{'PIN_BLOCKS','',''},
		{'PIN_RANDOM_BLOCKS','',''},
		{'POKE_ADDRESS','',''},
		{'POKE_LENGTH','',''},
		{'POKE_VALUE','',''},
		{'POKE_VALUE0','',''},
		{'POOL_SIMULATOR','',''},
		{'PROCESSSTATE <level>','',
		[[oradebug setospid <process ID>
		  oradebug unlimit
		  oradebug dump processstate 10]]},
		{'PXDOWNGRADE_ANALYZE','',''},
		{'RACDUMP','',''},
		{'REALFREEDUMP','',''},
		{'RECORD_CALLSTACK','',''},
		{'RECOVERY','',''},
		{'REDOHDR <level>',
		[[Dump redo headers.
		Level:
		1 Record of log file records in controlfile
		2 Level 1 + generic information
		3 Level 2 + additional log file header information.]],'oradebug dump redohdr 10'},
		{'REDOLOGS','',''},
		{'REFRESH_OS_STATS','',''},
		{'ROW_CACHE','',''},
		{'RULESETDUMP','',''},
		{'RULESETDUMP_ADDR','',''},
		{'SAVEPOINTS','',''},
		{'SCN_AUTO_ROLLOVER_TS_OVERRIDE','',''},
		{'SELFTESTASM','',''},
		{'SESSION_STATS_FREELIST','',''},
		{'SET_AFN','',''},
		{'SET_ISTEMPFILE','',''},
		{'SET_NBLOCKS','',''},
		{'SET_TSN_P1','',''},
		{'SGA_SUMMARY','',''},
		{'SHARED_SERVER_STATE','',''},
		{'SHORT_STACK','',''},
		{'SIMULATE_EOV','',''},
		{'SLOCK_DUMP','',''},
		{'SQLNET_SERVER_TRACE','',''},
		{'STATE_OBJECT_DELETION_TIME','',''},
		{'STATE_OBJECT_METADATA','',''},
		{'SYSTEMSTATE <level>',[[Dump systemstate.
		Level:
			2:    dump (excluding lock element)
			10:   dump
			11:   dump + global cache of RAC
			256: short stack （function stack）
			258: 256+2   -->short stack +dump(excluding lock element)
			266: 256+10 -->short stack+ dump
			267: 256+11 -->short stack+ dump + global cache of RAC
		]],'oradebug dump systemstate 266'},
		{'SYSTEMSTATE_GLOBAL','',''},
		{'TEST_DB_ROBUSTNESS','',''},
		{'TEST_GET_CALLER','',''},
		{'TEST_SPACEBG','',''},
		{'TEST_STACK_DUMP','',''},
		{'TRACE_BUFFER_OFF','',''},
		{'TRACE_BUFFER_ON','',''},
		{'TREEDUMP <object_id>',
		[[Dumps the structure of an index tree. The dump file contains one line for each block in the tree,
		 indented to show its level, together with a count of the number of index entries in the block.]],'oradebug dump treedump 40'},
		{'TR_CORRUPT_ONE_SIDE','',''},
		{'TR_CRASH_AFTER_WRITE','',''},
		{'TR_READ_ONE_SIDE','',''},
		{'TR_RESET_NORMAL','',''},
		{'TR_SET_ALL_BLOCKS','',''},
		{'TR_SET_BLOCK','',''},
		{'TR_SET_SIDE','',''},
		{'UPDATE_BLOCK0_FORMAT','',''},
		{'WORKAREATAB_DUMP','',''},
		{'XS_SESSION_STATE','',''}
	},
	LKDEBUG={
		{"hashcount","ges resource hash count. Mainly used to determine _lm_res_hash_bucket/_lm_res_tm_hash_bucket","oradebug lkdebug -a hashcount"},
		{'DLM locks','Dump RAC DLM locks',
		[[oradebug lkdebug -a convlock
		  oradebug lkdebug -a convres
		  oradebug lkdebug -r <resource handle> (i.e 0x8066d338 from convres dump)]]},
		{'reconfig',"reconfig lkdebug and release the gc locks","oradebug lkdebug -m reconfig lkdebug"},
		{'-O <object_id> 0 TM','Print the resource details for the object_id','oradebug lkdebug -O 11984883 0 TM'},
		{'-O <addr1> <addr2> <type>','Print the resource defails from gv$ges_resource','oradebug -g all lkdebug -O 0xd4056fb3 0x6873eeb3 LB'},
		{'-B <lmdid> <groupid> <bucketidx>','Identify the hot locks on hash buckets',"SELECT * FROM (select 'oradebug lkdebug -B '||lmdid||' '||groupid||' '||bucketidx,waitcnt FROM x$kjrtbcfp ORDER BY waitcnt DESC) WHERE ROWNUM<=100;"},
		{'-A <name>','List context',
		[[oradebug -g all lkdebug -A res
		  oradebug -g all lkdebug -A lock]]}
	},
	EVENT={
		{'4','determine the Events Set in a System','oradebug dump events 4'},
		{'10309','Tracing trigger actions','oradebug event 10309 trace name context forever, level 1'},
		{'10046',
		[[Trace a specific session.
			Level:
			* 1  Trace all calls
			* 2  Trace "enabled" calls
			* 4  Trace all exceptions
			* 8  Trace "enabled" exceptions
			* 16 Trace w/ circular buffer
			* 17 Trace all calls, using the buffer
			* 22 Trace enabled calls and all exceptions using the buffer
			* 32 Trace bind variables, without using the buffer
			* 53 Yields the maximum level of tracing, using the buffer
			* 37 Yields the maximum level of tracing, without using the buffer]],
		[[oradebug session_event 10046 trace name context forever,level 12
		  oradebug session_event 10046 trace name context off
		  oradebug session_event 10046 trace name context level 12, lifetime 10000, after 5000 occurrences]]},
		{'crash','Kill the specific session','oradebug event immediate crash'},
		{'deadlock','Dump deadlocks',
		[[oradebug event deadlock trace name hanganalyze_global
		oradebug event 60 trace name hanganalyze level 4
		oradebug event 60 trace name hanganalyze_global]]}
	}
}

for k,v in pairs(traces) do
	local item={k,v[1],v[2]}
	ext.EVENT[#ext.EVENT+1]=item
	ext[k]={item}
	ext['RDBMS.'..k]={item}
end

function oradebug.load_dict()
    env.load_data(datapath,true,function(data)
        oradebug.dict=data
        local keywords={}
        for k,v in pairs(data._keys) do keywords[#keywords+1]=k end
        console:setSubCommands({oradebug=data._keys})
        env.log_debug('extvars','Loaded dictionry '..datapath)
    end)
end

function oradebug.build_dict()
	libs={NAME={},SCOPE={},FILTER={},ACTION={},COMPONENT={},HELP={HELP={}},_keys={}}
	local lib_pattern='^%S+.- in library (.*):'
	local item_pattern
	local curr_lib,prefix,prev,prev_prefix
	local scope,sub
	local keys=libs['_keys']
	for _,n in ipairs{'NAME','SCOPE','FILTER','ACTION'} do
		sub=libs[n]
		scope=get_output("doc event "..n)
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
					local buff=get_output("doc event "..n..' '..curr_lib..'.'..item)
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
	scope=get_output("doc component")
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

				local buff=get_output("doc component "..curr_lib..'.'..item)
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
	
	scope=get_output("help")
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
			local buff
			if item:lower()=="dumplist" then
				buff=get_output("oradebug "..item)
			elseif item:lower()=="lkdebug" or item:lower()=="nsdbx" then
				buff=get_output(item.." help")
			else
				buff=get_output("help "..item)
			end
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

	scope=get_output("doc event")
	sub['EVENT']={desc='Set trace event in process',usage=table.concat(scope,'\n')}
	keys['HELP'],keys['EVENT'],keys['DOC']='Library','DOC','DOC'

	sqlplus:terminate()
	env.save_data(datapath,libs)
	oradebug.dict=libs
end

local function print_ext(action)
	if ext[action] then
		local rows={{'Item','Description','Examples'}}
		for k,v in ipairs(ext[action]) do
			if v[2] and v[2]~='' and v[3] then
				v[2]=v[2]:gsub('\n\r?[ \t]+',"\n  ")
				v[3]=v[3]:gsub('\n\r?[ \t]+',"\n")
				rows[#rows+1]=v
			end
		end
		if #rows>1 then
			env.set.set("rowsep","-")
			env.set.set("colsep","|")
			grid.sort(rows,"Item",true)
			grid.print(rows)
			env.set.set("rowsep","back")
			env.set.set("colsep","back")
		end
	end
end

function oradebug.run(action,args)
	local libs
	if action and action:lower() == 'init' then return oradebug.build_dict() end
	
	if not action then action='HELP' end
	action=action:upper()
	if action=='HELP' and args then 
		action,args=args:upper(),nil 
	elseif action=='DOC' and args then
		action,args=args:match('%S+$'):upper(),nil
	end

	if args or no_args[action] then
		local cmd=action..' '..(args or '')
		get_output(cmd,false)
		if action=='SETMYPID' or action=='SETORAPID' or action=='SETORAPID' or action=='SETOSPID' then
			oradebug._pid=cmd
		end
		return
	end

	action=action:gsub('%.%*$',''):gsub('%%','.*')

	local usage={}


	local libs=oradebug.dict
	local key=libs['_keys'][action]
	if key=='DOC' then
		print(libs['HELP']['HELP']['EVENT'].usage)
		return print_ext(action)
	end

	local libs1={}
	for name,lib in pairs(libs) do
		if name~='_keys' then
			libs1[name]={}
			for k,v in pairs(lib) do
				if key=='Library' and k:upper()==action or name==action then
					libs1[name][k]=v
				elseif key~='Library' and not libs[action] then
					libs1[name][k]={}
					for n,d in pairs(v) do
						if key and (action==n:upper():gsub('[%[%] ]','') or action==(k..'.'..n):upper():gsub('[%[%] ]','')) then
							libs1[name][k][n]=d
							if d.usage then
								local target=(name..'.') 
								if name=='COMPONENT' then
									target=target..k..'.'
								elseif name~='HELP' then
									target='EVENT.'..target..k..'.'
								end
								target=target..n
								usage[#usage+1]='\n'..string.rep('=',#target+2)..'\n|'..target..'|\n'..string.rep('-',#target+2)
								usage[#usage+1]=d.usage
							end
						elseif (n:upper():find(action) or d.desc:upper():find(action) or (d.usage or ''):upper():find(action)) then
							libs1[name][k][n]=d
						end
					end
				end
			end
		end
	end
	libs=libs1

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

	if #usage>0 then
		print(table.concat(usage,'\n'))
	end
	print_ext(action)
end

function oradebug.onload()
	oradebug.load_dict()
	event.snoop('ON_DB_DISCONNECTED',function() oradebug._pid="setmypid" end)
	env.set_command(nil,'ORADEBUG',"Show/create dictionary/execute available OraDebug commands. Usage: @@NAME [init|<keyword>|<command line>]",oradebug.run,false,3)
end
return oradebug