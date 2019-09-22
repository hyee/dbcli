local env,printer,grid=env,env.printer,env.grid
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local sqlplus=db.C.sqlplus
local oradebug={_pid='setmypid'}
local writer=writer
local datapath=env.join_path(env.WORK_DIR,'oracle/oradebug.pack')
local init,no_args,trace,ext,addons,functions
no_args={
        INIT=1,
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
        UNLIMIT=1,
        GET_TRACE=1
    }


local function load_functions()
    if functions then return end
    local funcs,err=loadstring(env.load_data(db.ROOT_PATH..env.PATH_DEL..'functions.txt',false))
    env.checkerr(not err,err)
    funcs=funcs()
    functions={}
    for k,v in pairs(funcs) do
        local prefix=k:sub(1,2):lower()
        if not functions[prefix] then functions[prefix]={} end
        prefix=functions[prefix]
        prefix[k]=v
        if k:lower()~=k then
            prefix[k:lower()]=v
        end
    end
    oradebug.kernel_functions=functions
end

local cache={}
function oradebug.find_func(key,is_print)
    load_functions()
    local rows
    if is_print~=false then
        rows=grid.new()
        rows:add{'Function','Description'}
    elseif cache[key:lower()] then
        return cache[key:lower()]
    end
    local prefix=functions[key:lower():sub(1,2)]
    if not prefix then
        if is_print==false then
            cache[key:lower()]=''
            return ''
        else
            env.raise('No function is found for the input keyword: %s', key)
        end
    end

    local k,v=key,prefix[key]
    if not v then k,v=key:lower(),prefix[key:lower()] end
    if v then
        if is_print~=false then
            rows:add{k,v}
        else
            cache[key:lower()]=' ($PROMPTSUBCOLOR$'..v..'$NOR$)'
            return cache[key:lower()]
        end
    end
    
    key=key:lower():gsub('%%','.-')

    local candidates={}
    for k,v in pairs(prefix) do
        if k~=key then
            local n,c,l=k:match(key),1
            if not n then
                for i=#k,#k,-1 do --for i=#k,3,-1 do
                    n,c=key:match(k:sub(1,i)),1+(#k-i)*2
                    if n and i~=k then
                        l,k=#n,n..'$HIR$'..k:sub(i+1)
                        n=k
                        break
                    end
                end
            end
            if n then 
                candidates[#candidates+1]={k,l or #n,n,v,c}
            end
        end
    end

    if #candidates>0 then
        table.sort(candidates,function(a,b) return a[5]<b[5] or a[5]==b[5] and a[2]>b[2] end)
        for k,v in ipairs(candidates) do
            if is_print==false and k==1 then
                cache[key]=' ($COMMANDCOLOR$['..v[3]..'$COMMANDCOLOR$]$PROMPTSUBCOLOR$'..v[4]..'...$NOR$)'
                return cache[key]
            end
            rows:add{v[1]..'$NOR$',v[4]}
        end
    elseif is_print==false then
        cache[key]=''
        return ''
    elseif #rows.data<2 then
        env.raise('No function is found for the input keyword')
    end
    rows:sort(1)
    rows:print()
end

local tmp_cache
function oradebug.rep_func_desc(comp,prefix,org)
    org=org or prefix

    load_functions() 

    local funcs=tmp_cache or {}
    if not tmp_cache then
        for _,v in pairs(functions) do
            for n,c in pairs(v) do
                funcs[n:lower()]=c
            end
        end
    end
    prefix='['..prefix..'] '
    for k,v in pairs(funcs) do
        --v=v:gsub('^%[(.-)%]',function(s) return '['..s:initcap()..']' end)
        if k:trim()~=k then 
            funcs[k],k=nil,k:trim()
            funcs[k]=v
        end
        if k:lower():trim():find(comp:lower(),1,true)==1 then
            if k==comp then
                v=prefix
            else
                if v:trim():lower():find(org:lower(),1,true)==1 then
                    v=v:trim():sub(#org+1)
                end
                v=prefix..v:trim()
            end
            funcs[k:trim()]=v:gsub('^(%[.-%]%s)+','%1')
        end
    end

    tmp_cache=funcs
    local fmt='    %s="%s",'
    local rows,src={'--Some data is copied from http://orafun.info/\nreturn {'},{}
    for k,v in pairs(funcs) do
        if v then
            src[#src+1]={k,v:gsub('"','\\"')}
        end
    end

    table.sort(src,function(a,b)return a[1]:lower()<b[1]:lower() end)
    for k,v in ipairs(src) do
        rows[#rows+1]=fmt:format(v[1],v[2])
    end
    rows[#rows+1]='}'
    print("Result written to file "..env.write_cache('functions.txt',table.concat(rows,'\n')))
end


function oradebug.scan_func_from_plsql(dir)
    load_functions()
    local typ,path=os.exists(dir)
    env.checkerr(typ and typ~='file','No such directory: '..dir)
    local prefixes={'PROCEDURE','FUNCTION'}
    for i=1,2 do
        local v=prefixes[i]
        prefixes[i]=(v..'%s+([^%s%(;]+)[^;]+%sNAME%s+"([^%s;"]+)"[^;]-%sLIBRARY%s+([^%s;]+)'):case_insensitive_pattern()
        prefixes[i+2]=(v..'%s+([^%s%(;]+)[^;]+%sLIBRARY%s+([%(%)^%s;]+)[^;]-%sNAME%s+"([^%s;"]+)"'):case_insensitive_pattern()
        prefixes[i+4]=(v..'%s+([^%s%(;]+)[^;]+;%s+PRAGMA%s+INTERFACE%s*%((C)%s*,%s*([^%s;%)]+)%)'):case_insensitive_pattern()
    end
    --[[
    local f=env.load_data("E:\\19.2.plsql\\SYS.DBMS_TF.sql",false)

    for i,prefix in ipairs(prefixes) do
        for n,f,l in f:gmatch(prefix) do
            if i>2 then f,l=l,f end
            print(n,f,l)
        end
    end
    --]]
    
    local fmt='%s%s(%s)'
    local cnt={0,0,0,0}
    local funcs=tmp_cache or {}
    if not tmp_cache then
        for _,v in pairs(functions) do
            for n,c in pairs(v) do
                funcs[n]=c
            end
        end
    end

    local news={}
    os.list_dir(path,"sql",nil,function(event,file)
        if event=='ON_SCAN' then return 32*1024*1024 end
        if not file.data then return end
        local name=file.name:gsub('%.[^%.]+$','.')
        local cnames={}
        for i,prefix in ipairs(prefixes) do
            for n,f,l in file.data:gmatch(prefix) do
                if i>2 then f,l=l,f end
                cnt[2-math.fmod(i,2)]=cnt[2-math.fmod(i,2)]+1
                n,f,l=n:trim('"'),f:trim('"'),l:trim('"')
                if f:upper()==f then f=f:lower() end
                n=fmt:format(name,n,l)
                for i=1,(f:find('_',1,true) and 2 or 1) do
                    if i==2 then f=f:gsub('%_(.)',"%1") end
                    if news[f] and news[f]<5 and not funcs[f]:find(n,1,true) then
                        funcs[f]=(funcs[f]..'/')..n
                    elseif not news[f] then
                        local p=(funcs[f] or ''):match('^%[.-%] ?')
                        funcs[f]=(p or '') ..n
                    end
                    cnames[#cnames+1]=f:lower()
                    news[f]=(news[f] or 0)+1
                end
            end
        end
        if #cnames>1 then
            local prefix
            for i=3,10 do
                local c=cnames[1]:sub(1,i)
                local m=true
                for j=2,#cnames do
                    if cnames[j]:sub(1,i)~=c then m=false end
                end
                if m then 
                    prefix=c 
                else
                    break
                end
            end
        end
    end)

    fmt='    %s="%s",'
    local rows={'return {'}
    

    for k,v in pairs(funcs) do
        local k1=k:lower()
        if k~=k1 then
            local v1=funcs[k1]
            if v1 and news[k1] and not news[k]then
                funcs[k]=nil
            elseif v1 and not news[k1] then
                funcs[k1]=nil
            end
        end
    end

    tmp_cache=funcs
    local rows,src={'return {'},{}
    for k,v in pairs(funcs) do
        if v then
            src[#src+1]={k,v:gsub('"','\\"')}
        end
    end

    table.sort(src,function(a,b)return a[1]:lower()<b[1]:lower() end)
    for k,v in ipairs(src) do
        cnt[3]=cnt[3]+1
        rows[#rows+1]=fmt:format(v[1],v[2])
    end
    rows[#rows+1]='}'
    print(cnt[1],'procedures and',cnt[2],'functions detected and total',cnt[3],'entries generated.')
    print("Result written to file "..env.write_cache('functions.txt',table.concat(rows,'\n')))
end

local function load_ext()
    if init or not oradebug.dict then return end
    init=true
    traces={
        SQL_TRACE={
            'Dump SQL Trace',
           [[1 oradebug event sql_trace[SQL: 32cqz71gd8wy3] {pgadep: exactdepth 0} plan_stat=all_executions,wait=true,bind=true
             2 oradebug event sql_trace[SQL: 32cqz71gd8wy3] {pgadep: exactdepth 0} {callstack: fname opiexe} plan_stat=all_executions,wait=true,bind=true
             3 oradebug event sql_trace wait=true, plan_stat=never
             4 oradebug event sql_trace[sql: g3yc1js3g2689 | 7ujay4u33g337]
             5 oradebug event sql_trace[sql: sql_id=g3yc1js3g2689 | sql_id=7ujay4u33g337] 
             6 oradebug event sql_trace {process_pname=DBW} wait=true
             7 oradebug event sql_trace {process : pname = dw | pname =dm} wait=true, bind=true,plan_stat=all_executions ,level=12]]
        },
        TRACE={'Dump trace to disk',
            [[* oradebug event trace[RDBMS.SQL_Transform] [SQL: 32cqz71gd8wy3] disk=high RDBMS.query_block_dump(1) processstate(1) callstack(1)
              * oradebug event trace[sql_mon.*] memory=high,get_time=highres
              * trace RAC: oradebug event trace[rac_enq] disk highest
              * trace RAC: oradebug event trace[ksi] disk highest
              * trace SQL Compiler: oradebug event trace[SQL_Compiler | PX_Granule] disk high'
              * trace DML: oradebug event trace[DML] {callstack: fname dmlTrace} disk=high trace("DML restarted sqlid : %\n", sqlid())
              * trace DB_TRACE: oradebug event trace[db_trace] disk=highest, memory=disable
            ]]

        },
        SQL_MONITOR={'Force SQL Monitor on specific SQL ID',
        [[* oradebug event sql_monitor [sql: 5hc07qvt8v737] force=true]]},
        WAIT_EVENT={'Trace wait event',
            [[oradebug session_event wait_event["log file sync"|"log file sequential read"] trace("shortstack: %s\n", shortstack())
              oradebug session_event wait_event["log file sync"] crash()
              oradebug session_event wait_event[all] trace('event="%", p1=%, p2=%, p3=%, ela=%, tstamp=%, Stk=%\n', evargs(5), evargn(2), evargn(3),evargn(4), evargn(1), evargn(7),shortstack())
              oradebug event wait_event["latch: ges resource hash list"] {wait: minwait=8000} trace(''event "%", p1 %, p2 %, p3 %, wait time % Stk=%'', evargs(5), evargn(2), evargn(3),evargn(4), evargn(1), shortstack())
            ]]
        },
        MILLSAP={'11g+ Trace 10046 events',"oradebug event Millsap {process : pname = dw | pname =dm} wait=true, bind=true,plan_stat=all_executions ,level=12"}
    }

    ext={
        HANGANALYZE={
            {'HANGANALYZE <level>',
             [[Analyze System Hangs.
                Level:
                1-2 Only HANGANALYZE output, no process dump at all
                3   Level 2 + Dump only processes thought to be in a hang (IN_HANG state)
                4   Level 3 + Dump leaf nodes (blockers) in wait chains (LEAF,LEAF_NW,IGN_DMP state)
                5   Level 4 + Dump all processes involved in wait chains (NLEAF state)
                6   Level 5 + Dump errorstacks of processes involved in wait chains
                10  Dump all processes (IGN state)
             Node State:
             * IGN: ignore
             * LEAF: A waiting leaf node
             * LEAF_NW: A running (using CPU?) leaf node
             * NLEAF: An element in a chain but not at the end (not a leaf)
             ]],
             [[oradebug setmypid
                oradebug unlimit
                oradebug setinst all
                oradebug -g def hanganalyze 5
                oradebug -g def dump systemstate 266]]
            }
        },
        DUMP={
            {'ADJUST_SCN','',''},
            {'ALRT_TEST','',''},
            {'ARCHIVE_ERROR','',''},
            {'ASHDUMP <minutes>','Dump ASH table into sqlldr file','oradebug dump ashdump 5'},
            {'ASHDUMPSECONDS <seconds>','Dump ASH table into sqlldr file','oradebug dump ashdump 5'},
            {'ASMDISK_ERR_OFF <level>','Turn off dumping Dump ASM disk errors','oradebug ASMDISK_ERR_OFF 3221553153'},
            {'ASMDISK_ERR_ON <level>','Dump ASM disk errors. Level: group_number*65536 + disk_number + ASMDISK_ERR_CLUSTER','oradebug ASMDISK_ERR_ON 3221553153'},
            {'ASMDISK_READ_ERR_ON','',''},
            {'ATSK_TEST','',''},
            {'AWR_DEBUG_FLUSH_TABLE_OFF','',''},
            {'AWR_DEBUG_FLUSH_TABLE_ON','',''},
            {'AWR_FLUSH_TABLE_OFF','',''},
            {'AWR_FLUSH_TABLE_ON','',''},
            {'AWR_TEST','',''},
            {'BC_SANITY_CHECK','',''},
            {'BGINFO <level>','Dump background process info','oradebug dump BGINFO 15'},
            {'BG_MESSAGES <level>','Dump background process messages','oradebug dump BG_MESSAGES 1'},
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
            {'CALLSTACK <level>','Dump callstack','oradebug dump callstack 3'},
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
            {'CURSORDUMP <level>','DUMP shared cursors in the sga and not the open cursors of the session','oradebug dump cursordump 16'},
            {'CURSORTRACE <level> <addr>','Dump cursr trace','oradebug dump cursortrace 612 address 1745700775'},
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
            {'MODIFIED_PARAMETERS <level>','Dump modified parameters(alter session/system)','oradebug dump MODIFIED_PARAMETERS 1'},
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
            {"hashcount",
            [[Dump ges resource hash count(event "latch: ges resource hash list"). 
             Mainly used to determine _lm_res_hash_bucket/_lm_res_tm_hash_bucket]],
            [[oradebug lkdebug -a hashcount
              oradebug event trace [rac_enq] disk highest
              oradebug event trace [ksi] disk highest]]},
            {'DLM locks','Dump RAC DLM locks',
            [[oradebug lkdebug -a convlock
              oradebug lkdebug -a convres
              oradebug lkdebug -r <resource handle> (i.e 0x8066d338 from convres dump)]]},
            {'reconfig',"reconfig lkdebug and release the gc locks","oradebug lkdebug -m reconfig lkdebug"},
            {'-O <object_id> 0 TM','Print the resource details for the object_id','oradebug lkdebug -O 11984883 0 TM'},
            {'-O <addr1> <addr2> <type>','Print the resource defails from gv$ges_resource','oradebug -g all lkdebug -O 0xd4056fb3 0x6873eeb3 LB'},
            {'-B [con_id] <lmdid> <groupid> <bucketidx>','Identify the hot locks on hash buckets',"SELECT * FROM (select 'oradebug lkdebug -B '||lmdid||' '||groupid||' '||bucketidx,waitcnt FROM x$kjrtbcfp ORDER BY waitcnt DESC) WHERE ROWNUM<=100;"},
            {'-A <name>','List context',
            [[oradebug -g all lkdebug -A res
              oradebug -g all lkdebug -A lock]]},
            {'-m pkey <object_id>','relocate the master from one instance in the cluster to another','oradebug lkdebug -m pkey 492984'}
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
              oradebug session_event 10046 trace name context level 12, lifetime 10000, after 5000 occurrences
              oradebug event Millsap {process : pname = dw | pname =dm} wait=true, bind=true,plan_stat=all_executions ,level=12]]},
            {'crash','Kill the specific session','oradebug event immediate crash'},
            {'deadlock','Dump deadlocks',
            [[oradebug event deadlock trace name hanganalyze_global
            oradebug event 60 trace name hanganalyze level 4
            oradebug event 60 trace name hanganalyze_global
            oradebug session_event 60 trace name hanganalyze_global level 4, forever; -
            |                      name heapdump level 29, forever; -
            |                      name systemstate level 266, lifetime 1; -
            |                      name latches level 5 ,after 3 times; -
            |                      name record_callstack level 1000, life 5; -
            |                      name processstate level 2, forever]]},
            {'10200','Trace Consistent gets','oradebug event 10200 trace name level 4'}
        }
    }


    

    for k,v in pairs(traces) do
        local item={k,v[1],v[2]}
        ext.EVENT[#ext.EVENT+1]=item
        ext[k]={item}
        ext['RDBMS.'..k]={item}
    end

    
end

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
    if is_comment==nil then print('Running command: '..cmd) end
    local out=sqlplus:get_lines(cmd)
    if is_comment==false then 
        if out then print(out) end
    end
    if not out then 
        return get_output(cmd) 
    elseif is_comment~=nil then
        sqlplus:call_process('bye',true)
    end
    return out:gsub('%z',''):split('\n\r?')
end

oradebug.exec_command=get_output

function oradebug.get_trace(file,size)
    size=tonumber(size) or 8
    file=file or get_output("TRACEFILE_NAME",true)[1]
    local dumper=db.C.tracefile
    dumper.get_trace(file,size)
end

function oradebug.pmem(sid)
    sid=tonumber(sid)
    env.checkerr(sid,'Usage: oradebug pmem <sid>')
    local pid=db:get_value([[select pid from v$session a,v$process b where a.paddr=b.addr and a.sid=:1]],{sid})
    env.checkerr(tonumber(pid),'No PID found for the specific sid.')
    get_output("DUMP PGA_DETAIL_GET "..pid,true)
    env.sleep(3)
    db:query([[SELECT * from v$process_memory_detail where pid=:1 ORDER BY bytes DESC]],{pid})
end

function oradebug.load_dict()
    addons={
        BUILD_DICT={desc='Rebuild the offline help doc, should be executed in RAC environment',func=oradebug.build_dict},
        FUNC={desc='#Extract kernel function. Usage: oradebug func <keyword>',args=1,func=oradebug.find_func},
        REP_DESC={desc="#rep",args=3,func=oradebug.rep_func_desc},
        SCAN_FUNCTION={desc='#Scan offline PLSQL code and list the mapping C functions. Usage: scan_function <dir>',args=1,func=oradebug.scan_func_from_plsql},
        GET_TRACE={desc='Download current trace file. Usage: oradebug get_trace [file] [<size in MB>]',args=2,func=oradebug.get_trace},
        SHORT_STACK={desc='Get abridged OS stack. Usage: oradebug short_stack [<short_stack_string>|<sid>]',lib='HELP',func=oradebug.short_stack},
        PMEM={desc="Show process memory detail. Usae: oradebug pmen <sid>",args=1,func=oradebug.pmem},
        PROFILE={desc='Sample abridged OS stack. Usage: oradebug profile {<sid> [<samples>] [<interval in sec>]} | <file>',
                args=4,func=oradebug.profile,
                usage=[[
                    Profile abridged OS stack. The profile efficiency heavily relies on the network latency.
                    Usage: oradebug profile {<sid> [<samples>] [<interval in sec>]} | <file>
                    
                    Parameters:
                    ===========
                      samples  : Number of samples to taken, defaults as 100
                      interval : The repeat interval for taking samples in second, defaults as 0.1 sec. When 0 then rapidly sample the shortstack
                    
                    Examples:
                    ========= 
                      * oradebug profile 142308 
                      * oradebug profile 142308 1000 0
                      * oradebug profile D:\dbcli\cache\imtst_srv4\shortstacks_142308.log 
                ]]},
        KILL={desc="Kill a specific process within the same instance(event immediate crash). Usage: oradebug kill <sid>",func=oradebug.kill}   
    }
    local undoc={
        BUILDINFO={desc='Print the ADE label used to build the "oracle" binary'},
        DIRECT_ACCESS={desc='{ SET | ENABLE | DISABLE | SELECT }: Execute limited SQL under the attached process',args=1,
                       usage=[[
                        The semi-colon (;) should not be present at the end of the command
                        Only X$ tables can be selected from. Attempts to select from non-X$ tables results in an error of:
                            ORA-15653: Fixed table ... is not supported by DIRECT_ACCESS.
                            
                        The select statement must be very simple and there's currently no support for predicates etc (see next point).
                        The kqfd_run() function is the real driving function here and that function has header comments that gives examples of usage:
                            NOTES:
                            ======
                              Statement should be one of
                              - a simple SELECT query
                              - a SET command
                              - an ENABLE command
                              - a DISABLE command

                            SYNTAX:
                            =======
                              statement ::=
                                { select_query | set_command | enable_command | disable_command }
                                            
                              select_query ::=
                                SELECT { * | column_name [, column_name ]... } FROM table_name

                              set_command ::=
                                SET attribute = value
                            
                              enable_command ::=
                                ENABLE option
                            
                              disable_command ::= 
                                DISABLE option

                              option ::=
                                { REPLY | TRACE }

                              attribute ::=
                                { CONTENT_TYPE | MODE }

                            EXAMPLES:
                            ==========
                              oradebug direct_access SELECT * FROM x$ksdhng_chains 
                              oradebug direct_access SELECT blocked_sid, blocker_sid FROM x$ksdhng_chains
                              oradebug direct_access SET CONTENT_TYPE = 'text/xml'
                              oradebug direct_access SET CONTENT_TYPE = 'text/plain'
                              oradebug direct_access DISABLE REPLY
                              oradebug direct_access enable reply
                              oradebug direct_access set trace on
                              oradebug direct_access SET MODE = unsafe
                              oradebug direct_access SET MODE = safe
                              oradebug direct_access select * from x$kewam
                       ]]},
        EVENTDUMP={desc='{session | process | system}: List the event settings that a target process sees', args=1},
        KSTDUMPCURPROC={desc='<Event ID>: Dumps the KST records that the current process has generated fro the specified event to the process tracefile',args=1},
        PATCH={desc='Patch utility interface',args=1,usage='Refer to bug 9908867/13827934'},
        PDUMP={desc='{interval=<sec> ndumps=<count> [pids|orapids|orapnames=...] <command> <args>}: Produce a periodic dump',
              args=3,usage=[[
                             Usage: oradebug pdump interval=<sec> ndumps=<count> [pids|orapids|orapnames=...] <command> <args>}
                             
                             Examples:
                                 oradebug pdump interval=5 ndumps=3 hanganalyze 3 
                                 oradebug pdump interval=5 ndumps=3 short_stack 0
                                 oradebug pdump ndumps=5 orapids=1,2 errorstack 2
                                 oradebug pdump interval=10 ndumps=2 orapnames=dbw0,smon errorstack 2]]},
        PGA_DETAIL_GET={desc='Produce a breakdown of PGA memory contents for a specific Oracle Pid'},
        PLSQL_STACK={desc='Dump PLSQL stacks when a deadlock is seen'},
        PROT={desc=' {NONE|ALL|RDONLY} address len granule_size: allows one to adjust memory protection on shared memory.',args=1},
        RELEASE={desc='Release instance list'},
        UNIT_TEST={desc='{list|<command>} Invoke a standalone test harness',args=1},
        UNIT_TEST_NOLG={desc='{list|<command>} Invoke a standalone test harness',args=1},
        UNIT_TEST_REM={desc='{list|<command>} Invoke a standalone test harness on a remote instance',args=1},
    }


    env.load_data(datapath,true,function(data)
        oradebug.dict=data
        local help,keys=data.HELP,data._keys
        help['ADDON']={}
        for k,v in pairs(addons) do
            k=k:upper()
            local lib=v.lib or 'ADDON'
            keys[k]='HELP.'..lib
            if v.usage then
                v.usage=v.usage:gsub('^%s+[\n\r]+','')
                local prefix=v.usage:match('^%s+')
                if prefix then v.usage=v.usage:sub(#prefix+1):gsub('[\n\r]+'..prefix,'\n') end
            end
            if not help[lib] then help[lib]={} end
            help[lib][k]=v
        end
        help=help.HELP
        for k,v in pairs(undoc) do
            k=k:upper()
            if not v.args then no_args[k]=1 end
            help[k]=v
            keys[k]='HELP.HELP'
        end
        local keywords={}
        for k,v in pairs(keys) do keywords[#keywords+1]=k end
        console:setSubCommands({oradebug=data._keys,odb=data._keys})
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

function oradebug.short_stack(stack)
    if not stack or tonumber(stack) then
        if tonumber(stack) then
            oradebug.attach_sid(stack)
        end
        stack=get_output("short_stack",true)[1]
        env.checkerr(not stack:trim():find('^%u+%-%d+:'),stack)
        print(stack..'\n')
    end
    local pieces=stack:split('<-',true)
    local result={}
    local sep='  '
    for i=#pieces,1,-1 do
        local func=pieces[i]:gsub('%(.*','')
        result[#result+1]=tostring(#result+1):lpad(#(''..#pieces))..'| '..sep:rep(#result)..pieces[i]..oradebug.find_func(func,false)
    end
    print(table.concat(result,'\n'))
end

function oradebug.get_pid(sid)
    sid=tonumber(sid)
    env.checkerr(sid,"Please input the valid SID.")
    local pid=db:get_value([[select pid from v$session a,v$process b where a.paddr=b.addr and a.sid=:1]],{sid})
    env.checkerr(tonumber(pid),'No PID found for the specific sid.')
    return pid
end

function oradebug.attach_sid(sid)
    get_output("SETORAPID ".. oradebug.get_pid(sid))
end

function oradebug.profile(sid,samples,interval)
    local out,log
    local typ,file=os.exists(sid)
    if typ then
        out=env.load_data(file,false)
        file=file:gsub('.*[\\/]',''):gsub('%..-$','')
    elseif sid and not tonumber(sid) then
        env.raise('No such file, please input a valid file path or a sid.')
    else
        sid=oradebug.attach_sid(sid)
        file=sid
        samples=tonumber(samples) or 100
        interval=tonumber(interval) or 0.1
        get_output("unlimit",true)
        out=sqlplus:get_lines("oradebug short_stack",interval*1000,samples)
        log=env.write_cache("shortstacks_"..sid..".log",out)
    end
    local c,funcs,result=0,{},{}
    local stacks={}
    local items={}
    local sub,item
    local calls,trees=0,0
    local cnt
    for line in out:gsub('[\n\r]+%S+>%s+','\n'):gsplit('[\n\r]+%s*') do
        line,cnt=line:gsub('^.-%_%_sighandler%(%)','',1)
        if cnt==0 then
            line,cnt=line:gsub('^.-sspuser%(%)','',1)
        end
        table.clear(items)
        local depth=0
        for f in line:gmatch("<%-([^%s<%(]+)") do
            if not funcs[f] then
                c=c+1
                result[c],funcs[f]={func=f,subtree=0,calls=0,stacks={}},c
            end
            depth=depth+1
            items[depth]=funcs[f]
        end
        sub=stacks
        for i=depth,1,-1 do
            item=items[i]
            if not sub[item] then
                sub[item]={f=result[item].func,subtree=1,calls=0}
            else
                sub[item].subtree=sub[item].subtree+1
            end
            trees=trees+1
            if i==1 then
                calls=calls+1
                sub[item].calls=sub[item].calls+1
                result[item].calls=result[item].calls+1
            else
                sub=sub[item]
                result[item].subtree=result[item].subtree+1
            end
        end
    end
    out=nil

    local rows,index=grid.new(),0
    rows:add{'#','Calls','Subtree','|*|','  Call Stacks'}
    local function compare(a,b)
        return a.subtree>b.subtree and true or
               a.subtree==b.subtree and a.calls>b.calls and true or false
    end
    local sep='  '
    local fmt='%5s%%(%d)'
    local cfmt='<-%s(%d)%s'
    local function build_stack(sub,depth,prefix,chain)
        local trees={}
        for k,v in pairs(sub) do
            if type(v)=='table' then
                trees[#trees+1]=v
                v.index=k
            end
        end

        if #trees>0 then
            if #trees>1 then table.sort(trees,compare) end
            for k,v in ipairs(trees) do
                index=index+1
                if v.calls>0 then
                    result[v.index].stacks[#result[v.index].stacks+1]='Line #'..(''..index):lpad(4)..': '..v.f..'('..v.calls..')'..chain
                end
                local func=oradebug.find_func(v.f,false)
                rows:add{index,v.calls==0 and ' ' or fmt:format(math.round(100.0*v.calls/calls,2)..'',v.calls),v.subtree-v.calls,'|*|',prefix..v.f..func}
                build_stack(v,depth+1,prefix..(k<#trees and '| ' or sep),cfmt:format(v.f,v.calls,chain))
            end
        end
    end

    build_stack(stacks,0,'  ','')
    out=rows:tostring()

    table.sort(result,function(a,b)
        return a.calls>b.calls and true or
               a.calls==b.calls and a.subtree>b.subtree and true or
               a.calls==b.calls and a.subtree==b.subtree and a.func>b.func and true or false
    end)

    local max=math.min(30,#result)
    rows,index=grid.new(),0
    rows:add{'#','Function','calls','Calls%','Subtree','Call Stacks'}
    compare=function(a,b) return tonumber(a:match('%d+'))>tonumber(b:match('%d+')) end
    for i=1,max do
        if result[i].calls >0 then
            if #result[i].stacks>0 then
                table.sort(result[i].stacks,compare)
                result[i].stacks[#result[i].stacks]='$UDL$'..result[i].stacks[#result[i].stacks]..'$NOR$'
            end
            index=index+1
            rows:add{index,result[i].func,result[i].calls,math.round(100.0*result[i].calls/calls,2),result[i].subtree,table.concat(result[i].stacks,'\n')}
        end
    end

    out=out..'\n\n'..rows:tostring(true)

    print(out..'\n')
    if log then print("Short stacks are written to", log) end
    print("Analyze result is saved to",env.write_cache("printstack_"..file..".log",out:strip_ansi()))
end

function oradebug.kill(sid)
    oradebug.attach_sid(sid)
    result=get_output("event immediate crash",true)
    print(table.concat(result,'\n'))
end

function oradebug.run(action,args)
    local libs,is_help
    load_ext()
    if not action then action='HELP' end
    action=action:upper()
    if action=='HELP' and args then 
        is_help,action,args=true,args:upper(),nil 
    elseif action=='DOC' and args then
        is_help,action,args=true,args:match('%S+$'):upper(),nil
    end

    if not is_help and (args or no_args[action]) then
        if addons[action] then
            local nargs=addons[action].args or 0
            if nargs<2 then return addons[action].func(args) end
            args=env.parse_args(nargs,args)
            return  addons[action].func(table.unpack(args))
        end
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
                                usage[#usage+1]=env.helper.colorful(d.usage,'')
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
                    if d.desc and d.desc:sub(1,1)~='#' then
                        rows[#rows+1]={(name=='COMPONENT' or name=='HELP') and name or ('EVENT.'..name),k,n..(d.is_parent and '.*' or ''),d.desc}
                    end
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
    env.set_command(nil,{'ORADEBUG','ODB'},"Execute available OraDebug commands. Usage: @@NAME [<search keyword>|<command line>]",oradebug.run,false,3)
end
return oradebug