local env,loader=env,loader
local snoop,cfg,default_db=env.event.snoop,env.set,env.db
local flag = 1
local term,sqlerror,timer
local output={}
local prev_transaction
local enabled='on'
local autotrace='off'
local default_args={
    enable=enabled,
    cdbid=-1,
    buff="#VARCHAR",
    txn="#VARCHAR",
    lob="#CLOB",
    con_name="#VARCHAR",
    con_id="#NUMBER",
    con_dbid="#NUMBER",
    ccflag='#VARCHAR',
    dbid="#NUMBER",
    last_sql_id='#VARCHAR',
    curr_service='#VARCHAR',
    curr_schema='#VARCHAR'}
local prev_stats
local switch_prefix="BeGin /*switch*/dbms_output."
function output.setOutput(db)
    local flag=cfg.get("ServerOutput")
    cfg.force_set('autotrace','off')
    sqlerror,timer=nil
    local stmt=switch_prefix..(flag=="on" and "enable(null)" or "disable()")..";end;"
    pcall(function() (db or env.getdb()):internal_call(stmt) end)
end

output.trace_sql=[[select /*INTERNAL_DBCLI_CMD dbcli_ignore*/ name,value from sys.v_$mystat join sys.v_$statname using(STATISTIC#) where value>0]]
output.trace_sql_after=([[
    DECLARE/*INTERNAL_DBCLI_CMD dbcli_ignore*/
        l_sql_id VARCHAR2(15);
        l_tmp_id VARCHAR2(15) := :sql_id; 
        l_child  PLS_INTEGER;
        l_sid    PLS_INTEGER;
        l_cid    PLS_INTEGER;
    BEGIN
        l_sid :=sys_context('userenv','sid');
        begin
            execute immediate q'[
                select /*+opt_param('_optimizer_generate_transitive_pred' 'false') opt_param('_optimizer_transitivity_retain' 'false')*/ 
                      prev_sql_id,prev_child_number 
                from sys.v_$session 
                where sid=:sid 
                and username is not null 
                and prev_hash_value!=0]'
                into l_sql_id,l_child using l_sid;
        exception when others then null; end;
        open :stats for @GET_STATS@;
        
        if l_sql_id is null then
            l_sql_id := l_tmp_id;
        elsif l_sql_id != l_tmp_id and l_tmp_id != 'X' then
            begin
                execute immediate '
                    select max(child_number) 
                    from   sys.v_$sql 
                    where  sql_id=:1 
                    and    last_active_time>=sysdate-numtodsinterval(2,''second'') 
                    and    rownum<2'
                into l_cid using l_tmp_id;
                IF l_cid IS NOT NULL THEN
                    l_sql_id := l_tmp_id;
                    l_child  := l_cid;
                END IF;
            exception when others then null; end;
        end if;
        
        :last_sql_id := l_sql_id;
        :last_child  := l_child; 
    END;]]):gsub('@GET_STATS@',output.trace_sql)

output.stmt=([[/*INTERNAL_DBCLI_CMD dbcli_ignore*/
    DECLARE
        l_line   VARCHAR2(32767);
        l_done   PLS_INTEGER := 32767;
        l_max    PLS_INTEGER := 0;
        l_buffer VARCHAR2(32767);
        l_arr    dbms_output.chararr;
        l_lob    CLOB;
        l_enable VARCHAR2(3)  := :enable;
        l_trace  VARCHAR2(30) := lower(:autotrace);
        l_sql_id VARCHAR2(15) := :sql_id; 
        l_tmp_id VARCHAR2(15) := :sql_id; 
        l_child  PLS_INTEGER  := :child;
        l_secs   PLS_INTEGER  := :secs;
        l_size   PLS_INTEGER;
        l_cont   VARCHAR2(50);
        l_cid    PLS_INTEGER;
        l_cdbid  INT := :cdbid;
        l_ccflag VARCHAR2(2000) := :ccflag;
        l_dbid   INT;
        l_stats  SYS_REFCURSOR;
        l_sep    VARCHAR2(10) := chr(1)||chr(2)||chr(3)||chr(10); 
        l_plans  sys.ODCIVARCHAR2LIST;
        l_fmt    VARCHAR2(300):='TYPICAL ALLSTATS LAST';
        l_sid    PLS_INTEGER:=sys_context('userenv','sid');
        l_sql    VARCHAR2(2000);
        l_found  BOOLEAN := false;
        TYPE l_rec IS RECORD(sql_id varchar2(13),sql_text varchar2(200),child_addr raw(8),child_num int);
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
        IF l_trace NOT IN('on','statistics','traceonly','switch') AND l_child IS NOT NULL THEN
            begin
                execute immediate q'[
                    select /*+opt_param('_optimizer_generate_transitive_pred' 'false') opt_param('_optimizer_transitivity_retain' 'false')*/ 
                           prev_sql_id,prev_child_number 
                    from   sys.v_$session 
                    where  sid=:sid and username is not null and prev_hash_value!=0]'
                    into l_sql_id,l_child USING l_sid;
                if l_sql_id is null then
                    l_sql_id := l_tmp_id;
                elsif l_sql_id != l_tmp_id and l_tmp_id != 'X' then
                    begin
                        execute immediate '
                            select max(child_number) 
                            from   sys.v_$sql 
                            where  sql_id=:1 
                            and    last_active_time>=sysdate-numtodsinterval(:2,''second'') 
                            and    rownum<2'
                        into l_cid using l_tmp_id,l_secs;
                        IF l_cid IS NOT NULL THEN
                            l_sql_id := l_tmp_id;
                            l_child  := l_cid;
                            l_cid    := null;
                        END IF;
                    exception when others then null; end;
                end if;
            exception when others then null;
            end;
        END IF;

        $IF dbms_db_version.version > 11 $THEN
            BEGIN
                IF l_cdbid != sys_context('userenv', 'con_dbid') THEN
                    dbms_output.disable;
                    dbms_output.enable(null);
                END IF;
                l_cont  :=sys_context('userenv', 'con_name'); 
                l_cid   :=sys_context('userenv', 'con_id'); 
                l_cdbid :=sys_context('userenv', 'con_dbid'); 
                l_dbid  :=sys_context('userenv', 'dbid'); 
                l_ccflag:=$$PLSQL_CCFLAGS; 
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
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

        IF l_trace NOT IN('off','statistics','sql_id','switch') THEN
            IF dbms_db_version.version>11 THEN
                l_fmt := l_fmt||' +METRICS +REPORT -ADAPTIVE';
            ELSIF dbms_db_version.version>10 THEN
                l_fmt := l_fmt||' +METRICS';
            END IF;
            BEGIN
                $IF DBMS_DB_VERSION.VERSION>10 $THEN
                    l_sql := 'SELECT /*+dbcli_ignore ordered_predicates no_expand*/ SQL_ID,trim(SQL_TEXT),'
                              || CASE WHEN DBMS_DB_VERSION.VERSION>11 THEN 'CHILD_ADDRESS' ELSE 'CAST(NULL AS RAW(8))' END 
                              || q'!,null 
                             FROM sys.V_$OPEN_CURSOR a
                             WHERE a.sid=:sid
                             AND   cursor_type like '%OPEN%'
                             AND   instr(sql_text,'dbcli_ignore')=0 
                             AND   instr(sql_text,'INTERNAL_DBCLI_CMD')=0
                             AND   instr(sql_text,'index(idl')=0
                             AND   sql_text not like 'table_%'
                             AND   sql_text not like 'select owner#,name,namespace%'
                             AND   lower(regexp_substr(sql_text,'\w+')) IN('create','with','select','update','merge','delete')
                             AND   0 < (
                                       select /*+outline_leaf push_pred(b)*/ 
                                              1
                                       from   sys.v_$sql b
                                       where  b.sql_id=a.sql_id
                                       and    parsing_schema_name=sys_context('userenv','current_schema')
                                       and    last_active_time>=SYSDATE-numtodsinterval(:2,'second')
                                       and    rownum < 2!'
                              || CASE WHEN DBMS_DB_VERSION.VERSION>11 THEN ' AND A.CHILD_ADDRESS=B.CHILD_ADDRESS)' ELSE ')' END;
                    BEGIN
                        EXECUTE IMMEDIATE l_sql BULK COLLECT INTO l_recs USING l_sid,l_secs;
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
                    IF l_recs(j).sql_id!='@GET_STATS_ID@' THEN
                        l_sql:='sql_id='''||l_recs(j).sql_id||''' AND ';
                        IF l_recs(j).child_num IS NOT NULL THEN
                            l_sql := l_sql||'child_number='||l_recs(j).child_num;
                        ELSIF l_recs(j).child_addr IS NOT NULL THEN
                            l_sql := l_sql||'child_address=hextoraw('''||l_recs(j).child_addr||''')';
                        ELSE
                            l_sql := l_sql||'child_number=(select max(child_number) keep(dense_rank last order by last_active_time) from sys.v_$sql where sql_id='''||l_recs(j).sql_id||''')';
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
                                    IF instr(l_plans(i),'Plan hash value:')>0 THEN
                                        l_plans(i) := replace(l_plans(i),'Plan hash value:','SQL ID: '||l_recs(j).sql_id||'   Plan hash value:')
                                                    ||CASE WHEN l_recs(j).sql_text IS NOT NULL THEN '   SQL: '||l_recs(j).sql_text||'...' END;
                                    END IF;  
                                    l_buffer := l_buffer || l_plans(i) || chr(10);
                                    wr;
                                end if;
                            elsif i=1 and l_recs(j).sql_id=l_sql_id then
                                l_buffer := l_buffer || CASE WHEN j>1 THEN 'TOP_' END || 'SQL_ID: '||l_recs(j).sql_id||chr(10);
                            end if;
                        END LOOP;
                    END IF;
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

        :last_sql_id := l_sql_id;
        :buff        := l_buffer;
        :txn         := dbms_transaction.local_transaction_id;
        :con_name    := l_cont;
        :con_id      := l_cid;
        :con_dbid    := l_cdbid;
        :ccflag      := l_ccflag;
        :dbid        := l_dbid; 
        :lob         := l_lob;
        :curr_service:= SYS_CONTEXT('USERENV','SERVICE_NAME');
        :curr_schema := SYS_CONTEXT('USERENV','CURRENT_SCHEMA');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;]]):gsub('@GET_STATS_ID@',loader:computeSQLIdFromText(output.trace_sql))

local idx=0;
local function next_()
    idx=idx+1
    return idx
end

local fixed_stats={
    ['DB time']={next_(),1},
    ['CPU used by this session']={next_(),1},
    ['CPU used when call started']={next_(),1},
    ['RM usage by this session']=next_(),
    ['non-idle wait time']={next_(),1},
    ['non-idle wait count']={next_(),3},
    ['recursive calls']={next_(),10},
    ['db block changes']=next_(),
    ['db block gets']=next_(),
    ['db block gets from cache']=next_(),
    ['db block gets from cache (fastpath)']=next_(),
    ['buffer is pinned count']={next_(),0},--Reports the times of visited a buffer without the expense of having to first use a latch.
    ['buffer is not pinned count']={next_(),1}, 
    ['consistent gets']={next_(),1},
    ['consistent gets direct']=next_(),
    ['consistent gets from cache']={next_(),1},
    ['consistent gets from cache (fastpath)']={next_(),1},
    ['consistent gets examination']={next_(),0},
    ['consistent gets examination (fastpath)']={next_(),0},
    ['consistent gets pin']={next_(),1},
    ['consistent gets pin (fastpath)']={next_(),1}, --_fastpin_enable  to reduce CBC latch contention
    ['no work - consistent read gets']={next_(),0},
    ['physical reads']=next_(),
    ['physical writes']=next_(),
    ['session logical reads']=next_(),
    ['logical read bytes from cache']=next_(),
    ['cell physical IO interconnect bytes']=next_(),
    ['redo size']=next_(),
    --['bytes sent via SQL*Net to client']={next_(),3600},
    --['bytes received via SQL*Net from client']={next_(),1314},
    --['SQL*Net roundtrips to/from client']={next_(),2},
    ['sorts (memory)']=next_(),
    ['sorts (disk)']=next_(),
    ['sorts (rows)']=next_()
}

local DML={SELECT=1,WITH=1,UPDATE=1,DELETE=1,MERGE=1,INSERT=1}
local DDL={CREATE=1,ALTER=1,DROP=1,GRANT=1,REVOKE=1,COMMIT=1,ROLLBACK=1}
local CODES={PACKAGE=1,FUNCTION=1,TRIGGER=1,VIEW=1,PROCEDURE=1,TYPE=1}

function output.getOutput(item)
    if output.is_exec then return end
    if term then cfg.set('TERMOUT','on') end
    local db,sql,sql_id=item[1],item[2]
    if not db or not sql then return end
    local typ,objtype,objname=db.get_command_type(sql)

    if DML[typ] and not env.is_main_thread() and autotrace=='off' and not sql:sub(1,1024):upper():find('SERVEROUTPUT',1,true) then
        if not db:is_internal_call(sql) then
            db.props.last_sql_id=loader:computeSQLIdFromText(sql)
            sql_id=db.props.last_sql_id
        end
        return 
    end

    if DDL[typ] then
        if (typ=='CREATE' or typ=='ALTER') and CODES[objtype] and objname then
            local orgname,owner,cnt=objname,''
            if objname:find('.',2,true) then owner,objname=objname:match('^(.-)%.(.+)$') end
            local inputs={owner=owner,name=objname}
            for k,v in pairs(inputs) do
                v,cnt=v:gsub('^"(.*)"$','%1')
                if cnt==0 then v=v:upper() end
                inputs[k]=v
            end
            local done,res=pcall(db.get_rows,db,[[SELECT Type,TO_CHAR(LINE)||'/'||TO_CHAR(POSITION) "LINE/COL", TEXT "ERROR" FROM ALL_ERRORS WHERE OWNER=Nvl(:owner,SYS_CONTEXT('USERENV','CURRENT_SCHEMA')) AND NAME=:name ORDER BY Type,LINE, POSITION, ATTRIBUTE, MESSAGE_NUMBER]],inputs)
            if done then
                if #res>1 then
                    db.props.error_obj,db.props.error_owner=objname,owner
                    env.warn('Warnning: %s %s created with compilation errors:',objtype:lower(),orgname)
                    cfg.set('feed','off')
                    env.grid.print(res)
                else
                    db.props.error_obj,db.props.error_owner=nil
                end
            else
                print(err)
            end
        end
        if autotrace=='off' and objtype~='SESSION' then return end
    end

    if sql:sub(1,32):find(switch_prefix,1,true)==1 or (sql:find('%s') and not db:is_internal_call(sql)) then
        local args,stats
        output.is_exec=true
        sql_id=sql_id or loader:computeSQLIdFromText(sql)
        if autotrace =='traceonly' or autotrace=='on' or autotrace=='statistics' then
            args={stats='#CURSOR',last_sql_id='#VARCHAR',last_child='#NUMBER',sql_id=sql_id}
            --db:query([[select /*dbcli_ignore INTERNAL_DBCLI_CMD*/ * from v$open_cursor where sid=userenv('sid') and cursor_type like '%OPEN%' and upper(SQL_TEXT） like '%SELECT%']])
            local done,err=pcall(db.exec_cache,db,output.trace_sql_after,args,'Internal_GetSQLSTATS_Next')
            if not done then
                output.is_exec=nil
                return --print(err)
            end
            stats=db:compute_delta(args.stats,output.prev_stats,'1','2')
        end

        local args1=args or {}
        local clock=os.timer()
        args=table.clone(default_args)

        args.sql_id=args1.last_sql_id or sql_id
        args.child=tonumber(args1.last_child) or ''
        args.autotrace=(sql:sub(1,64):find(switch_prefix,1,true)==1 or objtype=='SESSION') and 'switch' or autotrace
        args.cdbid=tonumber(db.props.container_dbid) or -1
        args.secs,timer=timer and math.min(30,math.ceil(clock-timer)) or 3,clock
        local done,err=pcall(db.exec_cache,db,output.stmt,args,'Internal_GetDBMSOutput')
        if not done then
            output.is_exec=nil
            return --print(err)
        end
        
        local result=args.lob or args.buff
        if (enabled == "on" or autotrace~="off") and result and result:match("[^\n%s]+") then
            result=result:gsub("\r\n","\n"):rtrim()
            if result~="" then
                if autotrace~="off" and result:find('Plan hash value',1,true) then
                    local rows=env.grid.new()
                    rows:add{'PLAN_TABLE_OUTPUT'}
                    rows:add{result}
                    rows:print()
                else
                    print(result)
                end 
            end
        end

        if not sqlerror and stats and #stats>0 then 
            local n,n1={},{}
            local idx,c,v=-1,0
            grid.sort(stats,1)
            for k,v in pairs(fixed_stats) do
                n1[type(v)=='table' and v[1] or v]={0,k,env.ansi.mask('HEADCOLOR','/')}
            end
            for k,row in ipairs(stats) do
                if tonumber(row[2]) and tonumber(row[2])>0 then
                    v=fixed_stats[row[1]]
                    if v then
                        n1[type(v)=='table' and v[1] or v][1]=math.max(0,row[2]-(type(v)=='table' and v[2] or 0))
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

            for k=#n1,3,-1 do
                if n1[k][1]==0 then
                    table.remove(n1,k)
                end
            end

            for k,row in ipairs(n1) do
                if #n<k then
                    n[k]={row[1],row[2],env.ansi.mask('HEADCOLOR','/')}
                else
                    n[k][1],n[k][2]=row[1],row[2]
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
            print("")
            if fmt then env.var.columns['VALUE']=fmt end
            env.set.set('sep4k','back')
            env.set.set('rownum','back')
        end

        if type(args.stats)=='userdata' then
            pcall(args.stats.close,args.stats)
        end

        db.resultset:close(args.stats)
        db.props.curr_service=args.curr_service
        db.props.curr_schema=args.curr_schema
        db.props.container=args.cont
        db.props.container_id=args.con_id
        db.props.container_name=args.con_name
        db.props.container_dbid=args.con_dbid
        db.props.dbid=args.dbid or db.props.dbid
        db.props.curr_ccflags=args.ccflag;
        if not db.props.last_sql_id or args.last_sql_id~='X' then
            db.props.last_sql_id=args.last_sql_id
        end
        local title={args.con_name and ("Container: "..args.con_name..'('..args.con_id..')')}
        if args.txn and cfg.get("READONLY")=="on" then
            db:rollback()
            env.raise("DML in read-only mode is disallowed, transaction is rollbacked.")
        end
        title[#title+1]=args.txn and ("TXN_ID: "..args.txn)
        if db.props.curr_schema ~= db.props.db_user then title[#title+1]='SCHEMA: '..db.props.curr_schema end
        title=table.concat(title,"   ")
        if prev_transaction~=title then
            prev_transaction=title
            env.set_title(title)
        end
        output.is_exec=nil
    end
    output.prev_sql=sql
end

function output.capture_stats(info)
    if output.is_exec then return end
    sqlerror=false
    if term then cfg.set('TERMOUT','off') end
    local db,sql=info[1],info[2]
    if sql and sql:find('%s') and not db:is_internal_call(sql) then
        if autotrace =='traceonly' or autotrace=='on' or autotrace=='statistics' then
            output.is_exec=true
            local done,result=pcall(db.exec_cache,db,output.trace_sql,{},'Internal_GetSQLSTATS')
            if done then 
                output.prev_stats=result
            end
            output.is_exec=nil
        end
    end
end

function output.get_error_output(info)
    sqlerror=true
    if info.db:is_connect() then
        output.getOutput({info.db,info.sql})
    else
        if term then cfg.set('TERMOUT','on') end
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
        if autotrace==value then return value end
        if value=='traceonly' or value=='trace' then
            value='traceonly'
            term=cfg.get('TERMOUT')
            if term~='off' then
                cfg.set('TERMOUT','off') 
            else
                term=nil
            end
        else
            if term then cfg.set('TERMOUT','on') end
            term=nil
        end
        autotrace=value
        return value
    end,'oracle','Automatically get a report on the execution path used by the SQL optimizer and the statement execution statistics',
    'on,off,trace,traceonly,sql_id')

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