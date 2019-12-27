local env,loader=env,loader
local snoop,cfg,default_db=env.event.snoop,env.set,env.db
local flag = 1

local output={}
local prev_transaction
local enabled='on'
local autotrace='off'
local default_args={enable=enabled,cdbid=-1,buff="#VARCHAR",txn="#VARCHAR",lob="#CLOB",con_name="#VARCHAR",con_id="#NUMBER",con_dbid="#NUMBER",dbid="#NUMBER",stats='#CURSOR'}
local prev_stats

function output.setOutput(db)
    local flag=cfg.get("ServerOutput")
    local stmt="BeGin dbms_output."..(flag=="on" and "enable(null)" or "disable()")..";end;"
    pcall(function() (db or env.getdb()):internal_call(stmt) end)
end

output.trace_sql=[[select /*INTERNAL_DBCLI_CMD*/ name,value from v$mystat natural join v$statname where name not like 'session%memory%' and value>0]]

output.stmt=[[/*INTERNAL_DBCLI_CMD*/
        DECLARE
            l_line   VARCHAR2(32767);
            l_done   PLS_INTEGER := 32767;
            l_max    PLS_INTEGER := 0;
            l_child  PLS_INTEGER;
            l_buffer VARCHAR2(32767);
            l_arr    dbms_output.chararr;
            l_lob    CLOB;
            l_enable VARCHAR2(3)  := :enable;
            l_trace  VARCHAR2(30) := :autotrace;
            l_sql_id VARCHAR2(15) := :sql_id;
            l_size   PLS_INTEGER;
            l_cont   VARCHAR2(50);
            l_cid    PLS_INTEGER;
            l_cdbid  INT := :cdbid;
            l_dbid   INT;
            l_stats  SYS_REFCURSOR;
            l_sep    VARCHAR2(10) := chr(1)||chr(2)||chr(3)||chr(10); 
            l_plans  sys.ODCIVARCHAR2LIST;
            l_fmt    VARCHAR2(300):='TYPICAL ALLSTATS LAST';
            l_sql    VARCHAR2(500);
            l_found  BOOLEAN := false;
            TYPE l_rec IS RECORD(sql_id varchar2(13),child_addr raw(8),child_num int);
            TYPE t_recs IS TABLE OF l_rec;
            l_recs t_recs := t_recs();
            procedure wr is
            begin
                l_size   := length(l_buffer);
                IF l_size + 255 > 30000 THEN
                    IF l_lob IS NULL THEN
                        dbms_lob.createtemporary(l_lob, TRUE);
                    END IF;
                    dbms_lob.writeappend(l_lob, l_size, l_buffer) ;
                    l_buffer := NULL;
                END IF;
            end;
        BEGIN
            if l_trace not in ('sql_id','statistics','off') then
                begin
                    execute immediate 'select prev_child_number from v$session where sid=userenv(''sid'') and prev_sql_id=:2'
                    into l_child using l_sql_id;
                exception when others then null;
                end;
                open l_stats for select /*+dbcli_ignore*/ name,value from v$mystat natural join v$statname where name not like 'session%memory%' and value>0;
            else
                open l_stats for select /*+dbcli_ignore*/ * from dual;
            end if;

            $IF dbms_db_version.version > 11 $THEN
                IF l_cdbid != sys_context('userenv', 'con_dbid') THEN
                    dbms_output.disable;
                    dbms_output.enable(null);
                END IF;
                l_cont  :=sys_context('userenv', 'con_name'); 
                l_cid   :=sys_context('userenv', 'con_id'); 
                l_cdbid :=sys_context('userenv', 'con_dbid'); 
            $END

            
            IF l_enable = 'on' THEN
                dbms_output.get_lines(l_arr, l_done);
                FOR i IN 1 .. l_done LOOP
                    l_buffer := l_buffer || l_arr(i) || chr(10);
                    wr;
                END LOOP;
            ELSE
                dbms_output.disable;
                dbms_output.enable(null);
            END IF;

            IF l_trace NOT IN('off','statistics','sql_id') THEN
                IF dbms_db_version.version>11 THEN
                    l_fmt := l_fmt||' +METRICS +REPORT +ADAPTIVE';
                ELSIF dbms_db_version.version>10 THEN
                    l_fmt := l_fmt||' +METRICS';
                END IF;
                BEGIN
                    $IF DBMS_DB_VERSION.VERSION>10 $THEN
                        l_sql :='SELECT /*+dbcli_ignore*/ SQL_ID,'|| CASE WHEN DBMS_DB_VERSION.VERSION>11 THEN 'CHILD_ADDRESS' ELSE 'CAST(NULL AS RAW(8))' END ||',null FROM v$open_cursor WHERE sid=userenv(''sid'') AND cursor_type like ''OPEN%'' AND sql_exec_id IS NOT NULL AND instr(sql_text,''dbcli_ignore'')=0 AND instr(sql_text,''V$OPEN_CURSOR'')=0';
                        BEGIN
                            EXECUTE IMMEDIATE l_sql BULK COLLECT INTO l_recs;
                            FOR i in 1..l_recs.count LOOP
                                IF l_recs(i).sql_id=l_sql_id THEN
                                    l_found := true;
                                END IF;
                            END LOOP;
                        EXCEPTION WHEN OTHERS THEN NULL;    
                        END;
                    $END

                    IF NOT l_found THEN
                        l_recs.extend;
                        l_recs(l_recs.count).sql_id:=l_sql_id;
                        l_recs(l_recs.count).child_num := l_child;
                    END IF;

                    FOR j in 1..l_recs.count LOOP
                        l_sql:='sql_id='''||l_recs(j).sql_id||''' AND ';
                        IF l_recs(j).child_num IS NOT NULL THEN
                        	l_sql := l_sql||'child_number='||l_recs(j).child_num;
                        ELSIF l_recs(j).child_addr IS NOT NULL THEN
                            l_sql := l_sql||'child_address=hextoraw('''||l_recs(j).child_addr||''')';
                        ELSE
                            l_sql := l_sql||'child_number=(select max(child_number) keep(dense_rank last order by executions,last_active_time) from v$sql where sql_id='''||l_sql_id||''')';
                        END IF;
                        SELECT * BULK COLLECT INTO l_plans
                        FROM TABLE(dbms_xplan.display('v$sql_plan_statistics_all',NULL,l_fmt,l_sql));
                        IF j>1 THEN
                            l_buffer := l_buffer || chr(10);
                        END IF;
                        FOR i in 1..l_plans.count LOOP
                            IF l_plans(i) not like 'Error%' then
                                if i = 1 then
                                    l_buffer := l_buffer || l_sep;
                                end if;
                                if trim(l_plans(i)) is not null then
                                    l_max := greatest(l_max,length(l_plans(i)));
                                    l_buffer := l_buffer || replace(l_plans(i),'Plan hash value:','SQL ID: '||l_recs(j).sql_id||'   Plan hash value:') || chr(10);
                                    wr;
                                end if;
                            elsif i=1 and l_recs(j).sql_id=l_sql_id then
                                l_buffer := l_buffer || CASE WHEN j>1 THEN 'TOP_' END || 'SQL_ID: '||l_recs(j).sql_id||chr(10);
                            end if;
                        END LOOP;
                    END LOOP;
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            ELSIF l_trace='sql_id' THEN
                l_buffer := l_buffer || 'SQL_ID: '||l_sql_id||chr(10);
            END IF;

            if l_lob is not null and l_buffer is not null then
                dbms_lob.writeappend(l_lob, length(l_buffer), l_buffer) ;
                l_buffer := null;
            end if;

            if l_max > 0 then
                l_buffer := replace(l_buffer,l_sep,rpad('=',l_max,'=')||chr(10));
                l_lob := replace(l_lob,l_sep,rpad('=',l_max,'=')||chr(10));
            end if;

            $IF dbms_db_version.version > 12 or dbms_db_version.version=12 and dbms_db_version.release>1 $THEN 
                l_dbid  :=sys_context('userenv', 'dbid'); 
            $END
            
            :buff     := l_buffer;
            :txn      := dbms_transaction.local_transaction_id;
            :con_name := l_cont;
            :con_id   := l_cid;
            :con_dbid := l_cdbid;
            :dbid     := l_dbid; 
            :lob      := l_lob;
            :stats    := l_stats;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;]]

local fixed_stats={
    ['DB time']=1,
    ['CPU used by this session']=2,
    ['non-idle wait time']=3,
    ['recursive calls']=4,
    ['db block gets']=5,
    ['consistent gets']=6,
    ['physical reads']=7,
    ['physical writes']=8,
    ['session logical reads']=9,
    ['logical read bytes from cache']=10,
    ['cell physical IO interconnect bytes']=11,
    ['redo size']=12,
    ['bytes sent via SQL*Net to client']=13,
    ['bytes received via SQL*Net from client']=14,
    ['SQL*Net roundtrips to/from client']=15,
    ['sorts (memory)']=16,
    ['sorts (disk)']=17,
    ['sorts (rows)']=18,
    ['rows processed']=19
}

local DML={SELECT=1,WITH=1,UPDATE=1,DELETE=1,MERGE=1}
function output.getOutput(item)
    local db,sql=item[1],item[2]
    if not db or not sql then return end
    local typ=db.get_command_type(sql)
    if DML[typ] and #env.RUNNING_THREADS > 2 and autotrace=='off' then return end
    if sql:find('^BeGin dbms_output') or (not (sql:lower():find('internal',1,true) and not sql:find('%s')) and not db:is_internal_call(sql)) then
        local args=table.clone(default_args)
        args.sql_id=autotrace=='off' and 'x' or loader:computeSQLIdFromText(sql)
        args.autotrace=autotrace
        args.cdbid=tonumber(db.props.container_dbid) or -1
        local done,err=pcall(db.exec_cache,db,output.stmt,args,'Internal_GetDBMSOutput')
        if not done then 
            return
        end
        
        local result=args.lob or args.buff
        if enabled == "on" and result and result:match("[^\n%s]+") then
            result=result:gsub("\r\n","\n"):gsub("%s+$","")
            if result~="" then print(result) end
        end

        if autotrace =='traceonly' or autotrace=='on' or autotrace=='statistics' then
            local stats=db:compute_delta(args.stats,output.prev_stats,'1','2')
            if stats and #stats>0 then 
                local n={}
                local idx,c=-1,0
                grid.sort(stats,1)
                for k,v in pairs(fixed_stats) do
                    n[v]={0,k,env.ansi.mask('HEADCOLOR','/')}
                end
                for k,row in ipairs(stats) do
                    if tonumber(row[2]) and tonumber(row[2])>0 then
                        if fixed_stats[row[1]] then
                            n[fixed_stats[row[1]]][1]=row[2]
                        else
                            idx=math.fmod(idx+1,2)*3
                            if idx==0 then
                                c=c+1
                                if #n<c then n[c]={'','',env.ansi.mask('HEADCOLOR','/')} end
                            end
                            n[c][idx+4],n[c][idx+5]=row[2],row[1]
                            if idx==3 then n[c][6]='|' end
                        end
                    end
                end

                local fmt=env.var.columns.VALUE
                if fmt then env.var.columns['VALUE']=nil end
                env.set.set('sep4k','on')
                env.set.set('rownum','off')
                local rows=env.grid.new()
                rows:add{"Value","Name",'/',"Value","Name",'|',"Value","Name"}
                for k,row in ipairs(n) do rows:add(row) end
                print("")
                rows:print()
                if fmt then env.var.columns['VALUE']=fmt end
                env.set.set('sep4k','back')
                env.set.set('rownum','back')
            end
        elseif type(args.stats)=='userdata' then
            pcall(args.stats.close,args.stats)
        end

        db.resultset:close(args.stats)
        db.props.container=args.cont
        db.props.container_id=args.con_id
        db.props.container_dbid=args.con_dbid
        db.props.dbid=args.dbid or db.props.dbid
        local title={args.con_name and ("Container: "..args.con_name..'('..args.con_id..')')}
        if args.txn and cfg.get("READONLY")=="on" then
            db:rollback()
            env.raise("DML in read-only mode is disallowed, transaction is rollbacked.")
        end
        title[#title+1]=args.txn and ("TXN_ID: "..args.txn)
        title=table.concat(title,"   ")
        if prev_transaction~=title then
            prev_transaction=title
            env.set_title(title)
        end
        
    end
    output.prev_sql=sql
end

function output.capture_stats(info)
    local db,sql=info[1],info[2]
    if sql and not (sql:lower():find('internal',1,true) and not sql:find('%s')) and not db:is_internal_call(sql) then
        if autotrace =='traceonly' or autotrace=='on' or autotrace=='statistics' then
            local done,result=pcall(db.exec_cache,db,output.trace_sql,{},'Internal_GetSQLSTATS')
            if done then 
                output.prev_stats=result
            end
        end
    end
end

function output.get_error_output(info)
    if info.db:is_connect() then
        output.getOutput({info.db,info.sql})
    else
        env.set_title("")
    end
    return info
end

function output.onload()
    snoop("ON_SQL_ERROR",output.get_error_output,nil,40)
    snoop("AFTER_ORACLE_CONNECT",output.setOutput)
    snoop("BEFORE_DB_EXEC",output.capture_stats,nil,1)
    snoop("AFTER_DB_EXEC",output.getOutput,nil,99)
    cfg.init('AUTOTRACE','off',function(name,value)
        autotrace=value
        return value
    end,'oracle','Automatically get a report on the execution path used by the SQL optimizer and the statement execution statistics',
    'on,off,explain,statistics,traceonly,sql_id')

    cfg.init({"ServerOutput",'SERVEROUT'},
        "on",
        function(name,value)
            enabled=value
            return value
        end,
        "oracle",
        "Print Oracle dbms_output after each execution",
        "on,off")
end

return output