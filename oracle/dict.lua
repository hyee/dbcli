local env=env
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local dicts={}
local datapath=env.join_path(env.WORK_DIR,'oracle/dict.pack')
local re=env.re
local uid=nil
local cache={}

local fmt='%s(select /*+merge*/ * from %s where %s=%s :others:)%s'
local fmt1='%s(select /*+merge*/  %d inst_id,a.* from %s a where 1=1 :others:)%s'
local instance,container,usr,dbid
local cdbmode='off'
local cdbstr='^[CDA][DBL][BAL]_'
local noparallel='off'
local gv1=('(%s)table%(%s*gv%$%(%s*cursor%('):case_insensitive_pattern()
local gv2=('(%s)gv%$%(%s*cursor%('):case_insensitive_pattern()
local checking_access
local function rep_instance(prefix,full,obj,suffix)
    obj=obj:upper()
    local dict,dict1,flag,str=dicts.dict[obj],dicts.dict[obj:sub(2)],0
    if not checking_access and cdbmode~='off' and dicts.dict[obj] and obj:find(cdbstr) then
        local new_obj = obj:gsub('^CDB_','DBA_')
        if cdbmode=='pdb' and (dicts.dict[new_obj] or {}).comm_view and db.props.version<21 then 
            if db.props.select_dict==nil then
                checking_access=true
                db.props.select_dict=db.props.isdba or db:check_access('SYS.INT$DBA_SYNONYMS',1) or false
                checking_access=false
            end
            if db.props.select_dict  then
                obj=new_obj
                new_obj='NO_CROSS_CONTAINER(SYS.'..dicts.dict[new_obj].comm_view..')'
                full=new_obj
            end
        else
            new_obj=obj:gsub(cdbmode=='cdb' and '^[DA][BL][AL]_' or '^[CD][DB][BA]_HIST_',cdbmode=='cdb' and 'CDB_' or 'AWR_PDB_') 
            if new_obj~=obj and dicts.dict[new_obj] and (db.props.version or 10)>=(dicts.dict[new_obj].ver or 10) then
                if not full:find(obj) then new_obj=new_obj:lower() end
                full=full:gsub(obj:escape('*i'),new_obj)
                obj=new_obj
            end
        end
    end

    if dict then
        for k,v in ipairs{
            {instance and instance>0,dict.inst_col,instance},
            container and container>=0 and dict.cdb_col and {true,'nvl('..dict.cdb_col..','..container..')',container} or {},
            {dbid and dbid>0,dict.dbid_col,dbid},
            {usr and usr~="",dict.usr_col,"(select /*+no_merge*/ username from all_users where user_id="..(uid or '')..")"},
        } do
            if v[1] and v[2] and v[3] then
                if k==1 and obj:find('^GV_?%$') and v[3]==tonumber(db.props.instance) 
                    and dict1 and dict1.inst_col~="INST_ID"
                then
                    str=fmt1:format(prefix,instance,full:gsub("[gG]([vV]_?%$)","%1"),suffix)
                elseif flag==0 then
                    str=fmt:format(prefix,full,v[2],''..v[3],suffix)
                else
                    str=str:gsub(':others:','and '..v[2]..'='..v[3]..' :others:')
                end
                flag = flag +1
            end
        end
    end

    if flag==0 then
        str=prefix..full..suffix
    else
        str=str:gsub('where 1=1 and','where'):gsub(' where 1=1 :others:',''):gsub(' :others:','')
        env.log_debug('dicts',str)
    end
    return str
end

function dicts.set_inputs(inputs)
    dicts.on_before_db_exec({'',''})
end

function dicts.on_before_db_exec(item)
    for i=1,2 do
        if item and type(item[i])=="string" and item[i]:find('@lz_compress@',1,true) then
            item[i]=item[i]:gsub("@lz_compress@",db.lz_compress);
        end
    end

    instance,container,usr,dbid=tonumber(cfg.get("instance")),tonumber(cfg.get("container")),cfg.get("schema"),cfg.get("dbid")
    if instance==0 then instance=tonumber(db.props.instance) end
    for k,v in ipairs{
        {'INSTANCE',instance and instance>0 and instance or ""},
        {'DBID',dbid and dbid>0 and dbid or ""},
        {'CON_ID',container and container>=0 and container  or ""},
        {'SCHEMA',usr},
        {'_SQL_ID',db.props.last_sql_id or ''},
        {'G_MBRC',db.props.mbrc or 0.271},
        {'D_MBRC',db.props.d_mbrc or db.props.mbrc or 0.271},
        {'cdbmode',cdbmode~='off' and cdbmode or ''}
    } do
        if var.outputs[v[1]]==nil then var.setInputs(v[1],''..v[2]) end
    end

    if not dicts.dict then return item end
    local _,sql,args,params=table.unpack(item)

    if sql and not sql:sub(1,128):find('BYPASS_DBCLI_REWRITE',1,true) and not cache[sql] then
        if (tonumber(db.props.instance)==instance or type(db.props.version)=='number' and (db.props.israc==false or db.props.version<11)) and not sql:find('^'..(env.ROOT_CMD:escape())) then
            sql=sql:gsub(gv1,'%1((('):gsub(gv2,"%1((")
        end
        item[2]=re.gsub(sql..' ',dicts.P,rep_instance):sub(1,-2)
        cache[item[2]]=1
    end
    return item
end

function dicts.on_after_db_exec()
    table.clear(cache)
end

local noparallel_sql=[[
    begin 
        execute immediate 'alter session set events ''10384 trace name context %s''';
    exception
        when others then
            if sqlcode=-1031 then 
                execute immediate 'alter session %s parallel query';
            end if;
    end;
]]
function dicts.set_noparallel(name,value)
    if noparallel==value then return value end
    db:internal_call(noparallel_sql:format(value=="off" and "off" or "forever , level 16384",value=='off' and 'enable' or 'disable'))
    noparallel=value
    return value
end

function dicts.set_title(name,value,orig)
    local get=env.set.get
    local title={ tonumber(get("INSTANCE"))>-1   and "Inst="..get("INSTANCE") or "",
                  tonumber(get("DBID"))>0   and "DBID="..get("DBID") or "",
                  tonumber(get("CONTAINER"))>-1   and "Con_id="..get("CONTAINER") or "",
                  get("SCHEMA")~=""   and "Schema="..get("SCHEMA") or "",
                  get("CDBMODE")~='off' and (get("CDBMODE"):upper().."=on") or "",
                  noparallel~='off' and "PX=off" or ""}
    for i=#title,1,-1 do
        if title[i]=='' then table.remove(title,i) end
    end
    title=table.concat(title,'   '):trim()
    env.set_title(title~='' and "Filter: ["..title.."]" or nil)
end

function dicts.set_instance(name,value)
    return tonumber(value)
end

function dicts.set_container(name,value)
    if name=='CONTAINER' and value>=0 then 
        env.checkerr(db.props.version and db.props.version >= 12,'Current db version does not support the CDB feature!') 
    elseif name=='DBID' then
        if not tonumber(value) or tonumber(value)==db.props.dbid or tonumber(value)==0 then
            db.props.d_mbrc=nil
        else
            local val=tonumber(db:get_value([[select /*BYPASS_DBCLI_REWRITE*/ max(value) from dba_hist_parameter where dbid=:1 and parameter_name='db_block_size' and rownum<2]],{value}))
            db.props.d_mbrc=val==8192 and 0.271 or val==16384 and 0.375 or 0.519
            val=tonumber(db:get_value([[select /*BYPASS_DBCLI_REWRITE*/ max(decode(ISDEFAULT,'FALSE',value)) from dba_hist_parameter where dbid=:1 and parameter_name='db_file_multiblock_read_count' and rownum<2]],{value}))
            if val then
                db.props.d_mbrc=math.round(db.props.d_mbrc*8/val,4)
            end
        end
    end
    value=tonumber(value)
    env.checkerr(value and value>=-1 and value==math.floor(value),'Input value must be an integer!');
    return value
end


function dicts.set_schema(name,value)
    if value==nil or value=="" then 
        uid=nil
        --db:internal_call("alter session set current_schema="..db.props.db_user)
        return value
    end
    value=value:upper()
    local id=db:get_value([[select max(user_id) from all_users where username=:1]],{value})
    env.checkerr(id~=nil and id~="", "No such user: "..value)
    --db:internal_call("alter session set current_schema="..value)
    uid=tonumber(id)
    if #env.RUNNING_THREADS == 1 then db:clearStatements(true) end
    return value
end

local prev_container={}
function dicts.set_cdbmode(name,value)
    if value~='off' then
        if not db:is_connect() then return end
    end
    if not db.props.version then return end
    if cdbmode==value then return value end
    env.checkerr(value=='off' or db.props.version>=12, "Unsupported database: v"..db.props.db_version)
    if value=='pdb' then
        if db.props.container_id and db.props.container_id>1 then
            prev_container.dbid=cfg.get('dbid')
            prev_container.container=cfg.get('container')
            prev_container.new_dbid=db.props.container_dbid
            prev_container.new_container=db.props.container_id
            if tonumber(prev_container.dbid) == nil then
                cfg.force_set('dbid',db.props.container_dbid)
            end
            --pcall(db.internal_call,db,'alter session set container_data=current');
            --cfg.force_set('container',db.props.container_id)
        end
    elseif cdbmode=='pdb' then
        if prev_container.new_dbid==cfg.get('dbid') and prev_container.new_container==cfg.get('container') then
            cfg.force_set('dbid','default')
            --if db:is_connect() then
            --    pcall(db.internal_call,db,'alter session set container_data=all');
            --end;
            --cfg.force_set('container','default')
        end
    end
    cdbmode=value
    return value
end
local url,usr
function dicts.on_after_db_conn(instance,sql,props)
    if db.props.isadb==true then
        local mode=''
        cfg.force_set('cdbmode', 'pdb')
        print('Switched into PDB'..mode..' mode for Oracle ADW/ATP environment, some SQLs will be auto-rewritten.');
        print('You can run "set cdbmode default" to switch back.')
    else
        cfg.force_set('instance','default')
        cfg.force_set('cdbmode','default')
    end
    prev_container={}
    cfg.force_set('schema','default')
    cfg.force_set('container','default')
    cfg.force_set('dbid','default')
    noparallel='off'
    cfg.force_set('noparallel','off')
    if db.props.version then
        dicts.db_dict_path=env._CACHE_BASE..'dict_'..(db.props.dbname or 'db'):gsub("%..*$",""):gsub('%W+','-'):lower()..'_'..(db.props.dbid or 0)..'.dat'
    else
        dicts.db_dict_path=datapath
    end

    if props and (props.url~=url or props.user~=usr) then
        dicts.cache_obj=nil
        url,usr=props.url,props.user
    end
    if dicts.current_dict and dicts.current_dict.path~=dicts.db_dict_path and os.exists(dicts.db_dict_path) then
        console.completer:resetKeywords()
        dicts.load_dict(dicts.db_dict_path)
    end

    if not db:is_connect(true) then
        env.set_title("")
    end
end


function dicts.test_grid()
    local rs1=db:internal_call([[select * from (select * from v$sysstat order by 1) where rownum<=20]])
    local rs2=db:internal_call([[select * from (select rownum "#",name,hash from v$latch) where rownum<=30]])
    local rs3=db:internal_call([[select * from (select rownum "#",event,total_Waits from v$system_event) where rownum<=60]])
    local rs4=db:internal_call([[select * from (select * from v$sysmetric order by 1) where rownum<=10]])
    local rs5=db:internal_call([[select * from v$waitstat]])
    
    local merge=grid.merge
    rs1=db.resultset:rows(rs1,-1)
    rs2=db.resultset:rows(rs2,-1)
    rs3=db.resultset:rows(rs3,-1)
    rs4=db.resultset:rows(rs4,-1)
    rs5=db.resultset:rows(rs5,-1)
    rs3.height=55
    rs1.topic,rs2.topic,rs3.topic,rs4.topic,rs5.topic="System State","System Latch","System Events","System Matrix","Wait Stats"
    merge({rs3,'|',merge{rs1,'-',{rs2,'+',rs5}},'-',rs4},true)
end

function dicts.set_dict(typ,scope)
    if not typ then
        local dict=dicts.current_dict
        if not dict then return print('Please run "dict public" to build the global dictionary.') end
        if dict.cache==0 then
            for k,v in pairs(dicts.cache_obj or {}) do
                dict.cache=dict.cache+1
            end
        end
        local fmt='$HEADCOLOR$%-18s$NOR$ : %s'
        print(string.rep('=',100))
        print(fmt:format('Current Dictionary',dict.path))
        fmt='$HEADCOLOR$%-18s$NOR$ : %5s %s'
        print(fmt:format('Level#1 Keywords',dict.objects,'(Tab-completion on [<owner>.]<Keyword>)'))
        print(fmt:format('Level#2 Keywords',dict.subobjects,'(Tab-completion on <L1 Keyword>.<L2 Keyword>)'))
        print(fmt:format(' Cached Objects',dict.cache,"(Caches the current db's online dictionary that used for quick search(i.e.: desc/ora obj))"))
        print(fmt:format('    VPD Objects',dict.vpd,'(Used to auto-rewrite SQL for options "SET instance/container/dbid/schema")'))
        checkhelp(typ)
    end
    typ=typ:lower()
    env.checkerr(typ=='public' or typ=='init' or typ=='param' or typ=='obj',"Invalid parameter!")
    env.checkerr(scope or (typ=='public' or typ=='init'),"Invalid parameter!")
    scope=(scope or "all"):lower()
    local sql;
    local path=datapath
    local cnt1,cnt2,cnt3,rs,rows=0,0,0
    local dict,keywords,params={},{},{}
    local pattern=scope:gsub('%%','@'):escape():gsub('@','.*')
    local keys={}
    if typ=='param' then
        params=dicts.params
        local is_connect=db:is_connect()
        for k,v in pairs(params) do
            if (k..' '..v[1]..' '..v[7]):lower():find(pattern) and (not is_connect or v[1]<=db.props.version) then
                keys[#keys+1]=k
            end
        end
        if is_connect and #keys==0 and pattern:find('^[0-9_a-z]+$') then
            keys[#keys+1]={pattern:lower(),99,0,0,1,1,'unkown'}
        end
        env.checkerr(#keys<=2000,"Too many matched parameters.")
        table.sort(keys)
        local rows={{"#","Name","Type","Value","Version|Since","Optimizer|Env","Session|Modify","System|Modify","Instance|Modify","Description"}}
        local show_value=is_connect and #keys <=50
        if not show_value then table.remove(rows[1],4) end
        for i,k in ipairs(keys) do
            local v,value=params[k],''
            if type(k)=='table' then v,k=k,k[1] end
            if is_connect and #keys <=50 then
                local args={name=k..':'..v[2],value='#VARCHAR'}
                local res=pcall(db.exec_cache,db,[[
                    DECLARE
                        x VARCHAR2(300);
                        y BINARY_INTEGER;
                        t PLS_INTEGER;
                        n VARCHAR2(128):=:name;
                        p PLS_INTEGER := instr(n,':');
                    BEGIN
                        t:=sys.dbms_utility.get_parameter_value(substr(n,1,p-1),y,x);
                        :value := NVL(CASE WHEN substr(n,p+1) IN ('1','3','6','99') THEN ''||y END, x);
                    EXCEPTION WHEN OTHERS THEN
                        :value := 'N/A'||CASE WHEN substr(n,p+1) = '6' THEN '(Type 6)' END;
                    END;]],args,'Internal_GetDBParameter')
                value=res and (args.value or '') or 'N/A'
            end
            rows[i+1]={
                i,
                k,
                v[2],
                v[2]==1 and (value=='0' and 'FALSE' or value=='1' and 'TRUE') or value,
                v[1],
                v[3]==1 and 'TRUE' or 'FALSE',
                v[4]==1 and 'TRUE' or 'FALSE',
                v[5]==1 and 'IMMEDIATE' or v[5]==2 and 'DEFERRED'  or v[5]==3 and 'IMMEDIATE' or 'FALSE',
                v[6]==1 and 'TRUE' or 'FALSE',
                v[7]}
            if not show_value then table.remove(rows[i+1],4) end
        end
        return env.grid.print(rows)
    elseif typ=='obj' then
        dict=dicts.dict
        for k,v in pairs(dict) do
            if (k..' '..(v.comm_view or '')):lower():find(pattern) then
                keys[#keys+1]=k
            end
        end
        env.checkerr(#keys<=1000,"Too many matched views.")
        table.sort(keys)
        local rows={{"#","Object|Owner","Object|Name","Object|SubName","Instance|Column","CDB|Column","DBID|Column","User|Column","Comm|View"}}
        for i,k in ipairs(keys) do
            local v=dict[k]
            rows[i+1]={
                i,
                v.owner or '',
                k:match('^[^%.]+'),
                k:match('%.(.+)') or '',
                v.inst_col or '',
                v.cdb_col or '',
                v.dbid_col or '',
                v.usr_col or '',
                v.comm_view or ''}
        end
        return env.grid.print(rows)
    elseif typ=='init' then 
        path=dicts.db_dict_path
        dicts.dict,dicts.keywords,dicts.params={},{},{}
        sql=[[
            with r as(
                    SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode')*/ owner,table_name, column_name col,data_type
                    FROM   dba_tab_cols
                    WHERE  owner in('SYS','PUBLIC')
                    @XTABLE@)
            SELECT * FROM (
                SELECT  table_name,
                        MAX(CASE WHEN col = 'INST_ID' and substr(table_name,1,3) NOT IN('DBA','PDB','CDB','ALL') OR col='INSTANCE_NUMBER' THEN col END) INST_COL,
                        MAX(CASE WHEN col IN ('CON_ID') THEN col END) CON_COL,
                        MAX(CASE WHEN col IN ('DBID') THEN col END) DBID_COL,
                        MAX(CASE WHEN DATA_TYPE='VARCHAR2' AND regexp_like(col,'(OWNER|SCHEMA|KGLOBTS4|USER.*NAME)') THEN col END)
                            KEEP(DENSE_RANK FIRST ORDER BY CASE WHEN col LIKE '%OWNER' THEN 1 ELSE 2 END) USR_COL,
                        MAX(owner) owner
                FROM   (select * from r
                        union  all
                        select s.owner,s.synonym_name,r.col,r.data_type 
                        from   dba_synonyms s,r 
                        where  r.table_name=s.table_name 
                        and    r.owner=s.table_owner
                        and    s.synonym_name!=s.table_name
                        union  all
                        select owner,object_name,null,object_type
                        from   dba_objects
                        where  instr(object_type,' ')=0
                        union  all
                        select distinct owner,object_name||nullif('.'||procedure_name,'.'),null,'PROCEDURE'
                        from   dba_procedures
                        where  procedure_name is not null)
                GROUP  BY TABLE_NAME
                ORDER  BY decode(owner,'SYS',' ','PUBLIC','  ',owner),table_name)
            WHERE ROWNUM<=65536*5]]
    else
        dicts.load_dict(path)
        dict,params,keywords=dicts.dict,dicts.params,{}
        sql=[[
            with r as(
                    SELECT /*+no_merge opt_param('_connect_by_use_union_all','old_plan_mode')*/ owner,table_name, column_name col,data_type
                    FROM   dba_tab_cols, dba_users
                    WHERE  username IN (SELECT COMP_ID FROM dba_registry_schemas UNION SELECT COMP_ID FROM dba_registry)
                    AND    username = owner
                    AND    (owner,table_name) in(select distinct owner,TABLE_NAME from dba_tab_privs where grantee in('PUBLIC','SELECT_CATALOG_ROLE','EXECUTE_CATALOG_ROLE'))  
                    @XTABLE@)
            SELECT  table_name,
                    MAX(CASE WHEN col = 'INST_ID' and substr(table_name,1,3) NOT IN('DBA','PDB','CDB','ALL') OR col='INSTANCE_NUMBER' THEN col END) INST_COL,
                    MAX(CASE WHEN col IN ('CON_ID') THEN col END) CON_COL,
                    MAX(CASE WHEN col IN ('DBID') THEN col END) DBID_COL,
                    MAX(CASE WHEN DATA_TYPE='VARCHAR2' AND regexp_like(col,'(OWNER|SCHEMA|KGLOBTS4|USER.*NAME)') THEN col END)
                        KEEP(DENSE_RANK FIRST ORDER BY CASE WHEN col LIKE '%OWNER' THEN 1 ELSE 2 END) USR_COL,
                    MAX(owner),
                    MAX(decode(owner||data_type,'SYSREF',col)) COMM_VIEW
            FROM   (select * from r
                    union  all
                    select s.owner,s.synonym_name,r.col ,r.data_type 
                    from   dba_synonyms s,r 
                    where  r.table_name=s.table_name 
                    and    r.owner=s.table_owner
                    and    s.synonym_name!=s.table_name
                    union  all
                    select owner,object_name,null,object_type
                    from   dba_objects
                    where  owner IN('SYS') 
                    and    regexp_like(object_name,'^(DBMS_|UTL_)')
                    and    instr(object_type,' ')=0
                    union  all
                    select distinct owner,object_name||'.'||procedure_name,null,'PROCEDURE'
                    from   dba_procedures
                    where  owner IN('SYS') 
                    and    regexp_like(object_name,'^(DBMS_|UTL_)')
                    and    procedure_name is not null
                    union  all
                    select owner,table_name,null,null 
                    from   dba_tab_privs a
                    where  grantee in('EXECUTE_CATALOG_ROLE','SELECT_CATALOG_ROLE','DBA')
                    union  all
                    SELECT /*+no_merge(a) no_merge(b) use_hash(a b)*/
                           a.owner, a.name, nvl(b.referenced_name, a.referenced_name) ref_name,'REF'
                    FROM   (SELECT *
                            FROM   dba_dependencies a
                            WHERE  OWNER = 'SYS'
                            AND    REFERENCED_OWNER = 'SYS'
                            AND    REFERENCED_NAME LIKE 'INT$%'
                            AND    SUBSTR(NAME, 1, 4) IN ('ALL_', 'DBA_')) a,
                           (SELECT *
                            FROM   dba_dependencies a
                            WHERE  OWNER = 'SYS'
                            AND    REFERENCED_OWNER = 'SYS'
                            AND    REFERENCED_NAME LIKE 'INT$%'
                            AND    SUBSTR(NAME, 1, 4) = 'INT$') b
                    WHERE  a.referenced_name = b.name(+)
                )
            GROUP  BY TABLE_NAME]]
    end
    db:assert_connect()
    sql = sql:gsub('@XTABLE@',db.props.isdba~=true and '' or [[
            UNION ALL
            SELECT 'SYS',t.kqftanam, c.kqfconam, decode(kqfcodty,1,'VARCHAR2',2,'NUMBER',null)
            FROM   (SELECT kqftanam,t.indx,t.inst_id FROM sys.x$kqfta t
                    UNION ALL
                    SELECT KQFDTEQU,t.indx,t.inst_id FROM sys.x$kqfta t,sys.x$kqfdt where kqftanam=KQFDTNAM) t, sys.x$kqfco c
            WHERE  c.kqfcotab = t.indx
            AND    c.inst_id = t.inst_id
        ]])
    if scope=='all' or scope=='dict' then
        print('Building, it could take several minutes...')
        rs=db:dba_query(db.internal_call,sql)
        rows=db.resultset:rows(rs,-1)
        cnt1=#rows
        for i=2,cnt1 do
            local exists=dict[rows[i][1]]
            dict[rows[i][1]]={
                inst_col=(rows[i][2] or "")~=""  and rows[i][2] or (exists and dict[rows[i][1]].inst_col),
                cdb_col=(rows[i][3] or "")~=""   and rows[i][3] or (exists and dict[rows[i][1]].cdb_col),
                dbid_col=(rows[i][4] or "")~=""  and rows[i][4] or (exists and dict[rows[i][1]].dbid_col),
                usr_col=(rows[i][5] or "")~=""   and rows[i][5] or (exists and dict[rows[i][1]].usr_col),
                owner=(rows[i][6] or "")~=""     and rows[i][6] or (exists and dict[rows[i][1]].owner),
                comm_view=(rows[i][7] or "")~="" and rows[i][7] or (exists and dict[rows[i][1]].comm_view),
                ver=not exists and db.props.version or math.min(dict[rows[i][1]].ver,db.props.version) or nil
            }
            local prefix,suffix=rows[i][1]:match('(.-$)(.*)')
            if prefix=='GV_$' or prefix=='V_$' then
                dict[prefix:gsub('_','')..suffix]=dict[rows[i][1]]
            end
        end
        local done={}
        sql="select KEYWORD from V$RESERVED_WORDS"
        if db.props.version>=11.2 then
            sql=sql..[[ union select name from v$sql_hint where length(name)>5 union select descr from v$sqlfn_metadata where length(descr)>5 and instr(descr,' ')=0]]
        end
        done,rs=pcall(db.internal_call,db,sql)
        if done then
            rows=db.resultset:rows(rs,-1)
            cnt2=#rows
            for i=2,cnt2 do
                local key=rows[i][1]
                local exists=keywords[key]
                if tonumber(exist) and #key<6 then 
                    keywords[key]=nil
                elseif not exists then
                    keywords[key]=1
                end
            end
        else
            cnt2=2
        end
    end

    if db.props.isdba==true and (scope=='all' or scope=='param') then
        sql=[[SELECT ksppinm   NAME,
                     ksppity   TYPE,
                     nvl2(z.PNAME_QKSCESYROW, 1, 0) ISOPT_ENV,
                     bitand(ksppiflg / 256, 1) ISSES_Mdf,
                     bitand(ksppiflg / 65536, 3) ISSYS_MDF,
                     decode(bitand(ksppiflg, 4), 4,0, decode(bitand(ksppiflg / 65536, 3), 0, 0, 1)) ISINST_MD,
                     ksppdesc DESCRIPTION
            FROM     sys.x$ksppi x, sys.X$QKSCESYS z
            WHERE    x.ksppinm = z.PNAME_QKSCESYROW(+)]]
        rs=db:dba_query(db.internal_call,sql)
        rows=db.resultset:rows(rs,-1)
        cnt3=#rows
        for _,v in ipairs(rows) do
            local param=params[v[1]] or {}
            local version=param[1] or 999
            if version>db.props.version then 
                param[1]=db.props.version
            end
            for i=2,#v do
                if version~=999 or version<=db.props.version or not param[i] then param[i]=v[i] end
            end
            params[v[1]]=param
        end
    end

    env.save_data(path,{dict=dict,params=params,keywords=keywords,cache=(typ=='init' and dicts.cache_obj) or nil},31*1024*1024)
    dicts.load_dict(path)
    print((cnt1+cnt2+cnt3-2)..' records saved into '..path)
end

function dicts.load_dict(path)
    env.load_data(path,true,function(data)
        dicts.dict=data.dict
        dicts.params=data.params or {}
        dicts.keywords={}
        local dict={objects=0,subobjects=0,vpd=0,cache=0,path=path}
        if data.keywords then
            for k,v in pairs(data.dict) do 
                data.keywords[k]=v.owner or 1
                if k:find('.',1,2,true) then 
                    dict.subobjects=dict.subobjects+1
                else
                    dict.objects=dict.objects+1
                end

                if v.inst_col or v.cdb_col or v.dbid_col or v.usr_col then
                    dict.vpd=dict.vpd+1
                end
            end
            console:setKeywords(data.keywords)
            table.clear(data.keywords)
        end
        dicts.current_dict=dict
        if data.cache then 
            dicts.cache_obj=data.cache
        end
        data=nil
        env.log_debug('dicts','Loaded dictionry '..path)
    end)
end

function dicts.onload()
    env.set_command(nil,"TEST_GRID",nil,dicts.test_grid,false,1)
    env.set_command(nil,'DICT',[[
        Show or create dictionary for auto completion. Usage: @@NAME {<init|public [all|dict|param]>} | {<obj|param> <keyword>}
        init  : Create a separate offline dictionary that only used for current database
        public: Create a public offline dictionary(file oracle/dict.pack), which accepts following options
            * dict  : Only build the Oracle maintained object dictionary
            * param : Only build the Oracle parameter dictionary
            * all   : Build either dict and param
        obj   : Fuzzy search the objects that stored in offline dictionary
        param : Fuzzy search the parameters that stored in offline dictionary]],dicts.set_dict,false,3)

    event.snoop('BEFORE_DB_EXEC',dicts.on_before_db_exec,nil,60)
    event.snoop('AFTER_DB_EXEC',dicts.on_after_db_exec)
    event.snoop('ON_SUBSTITUTION',dicts.on_before_db_exec,nil,60)
    event.snoop('AFTER_ORACLE_CONNECT',dicts.on_after_db_conn)
    event.snoop('ON_DB_DISCONNECTED',dicts.on_after_db_conn)
    event.snoop('ON_SETTING_CHANGED',dicts.set_title)
    event.snoop('ON_SHOW_INPUTS',dicts.set_inputs)
    cfg.init("cdbmode","off",dicts.set_cdbmode,"oracle","Controls whether to auto-replace all SQL texts from 'DBA_HIST_' to 'CDB_HIST_'/'AWR_PDB_'","cdb,pdb,off")
    cfg.init("instance",-1,dicts.set_instance,"oracle","Auto-limit the inst_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-1 - 99")
    cfg.init("schema","",dicts.set_schema,"oracle","Auto-limit the schema of impacted tables. ","*")
    cfg.init({"container","con","con_id"},-1,dicts.set_container,"oracle","Auto-limit the con_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-1 - 32768")
    cfg.init("dbid",0,dicts.set_container,"oracle","Specify the dbid for AWR analysis")
    cfg.init("noparallel","off",dicts.set_noparallel,"oracle","Controls executing SQL statements in no parallel mode. refer to MOS 1114405.1","on,off");
    dicts.P=re.compile([[
        pattern <- {pt} {owner* obj} {suffix}
        suffix  <- [%s,;)]
        pt      <- [%s,(]
        owner   <- ('SYS.'/ 'PUBLIC.'/'"SYS".'/'"PUBLIC".')
        obj     <- full/name
        full    <- '"' name '"'
        name    <- {prefix %a%a [%w$#_]+}
        prefix  <- "GV_$"/"GV$"/"V_$"/"V$"/"INT$"/"DBA_"/"AWR_"/"ALL_"/"CDB_"/"X$"/"XV$"
    ]],nil,true)
    dicts.load_dict(datapath)
end

db.lz_compress=[[
    --Refer to: https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/ 
    FUNCTION adler32(p_src IN BLOB) RETURN VARCHAR2 IS
        s1 INT := 1;
        s2 INT := 0;
        ll PLS_INTEGER := dbms_lob.getlength(p_src);
        cc VARCHAR2(32766);
        p  PLS_INTEGER := 1;
        l  PLS_INTEGER;
    BEGIN
        LOOP
            cc := to_char(dbms_lob.substr(p_src,16383,p));
            l  := LENGTH(cc)/2;
            FOR i IN 1 .. l LOOP
                s1 := s1 + to_number(SUBSTR(cc,(i-1)*2+1,2), 'XX');
                s2 := s2 + s1;
            END LOOP;
            s1 := mod(s1,65521);
            s2 := mod(s2,65521);
            p := p + 16383;
            EXIT WHEN p >= ll;
        END LOOP;
        RETURN to_char(s2, 'fm0XXX') || to_char(s1, 'fm0XXX');
    END;

    FUNCTION zlib_compress(p_src IN BLOB) RETURN BLOB IS
        t_tmp BLOB;
        t_cpr BLOB;
    BEGIN
        t_tmp := utl_compress.lz_compress(p_src);
        dbms_lob.createtemporary(t_cpr, TRUE);
        t_cpr := hextoraw('789C'); -- zlib header
        dbms_lob.copy(t_cpr, t_tmp, dbms_lob.getlength(t_tmp) - 10 - 8, 3, 11);
        dbms_lob.append(t_cpr, hextoraw(adler32(p_src))); -- zlib trailer
        dbms_lob.freetemporary(t_tmp);
        RETURN t_cpr;
    END;

    FUNCTION zlib_decompress(p_src IN BLOB) RETURN BLOB IS
        t_out      BLOB;
        t_tmp      BLOB;
        t_raw      RAW(1);
        t_buffer   RAW(32767);
        t_hdl      BINARY_INTEGER;
        t_s1       PLS_INTEGER; -- s1 part of adler32 checksum
        t_last_chr PLS_INTEGER;
        t_size     PLS_INTEGER := length(p_src);
        t_adj      PLS_INTEGER;
        sq         VARCHAR2(2000) := '
        declare x raw(@LEN@);
        begin
            utl_compress.lz_uncompress_extract(:t_hdl, x);
            :buff := x;
        end;';
    BEGIN
        dbms_lob.createtemporary(t_out, FALSE);
        dbms_lob.createtemporary(t_tmp, FALSE);
        t_tmp := hextoraw('1F8B0800000000000003'); -- gzip header
        dbms_lob.copy(t_tmp, p_src, dbms_lob.getlength(p_src) - 2 - 4, 11, 3);
        dbms_lob.append(t_tmp, hextoraw('0000000000000000')); -- add a fake trailer
        t_hdl := utl_compress.lz_uncompress_open(t_tmp);
        t_s1  := 1;
        LOOP
            BEGIN
                t_adj := least(t_size * 5, 4000);
                IF t_adj < 128 THEN
                    utl_compress.lz_uncompress_extract(t_hdl, t_raw);
                    t_buffer := t_raw;
                    t_size   := 0;
                ELSE
                    EXECUTE IMMEDIATE REPLACE(sq, '@LEN@', t_adj)
                        USING IN OUT t_hdl, IN OUT t_buffer;
                    t_size := t_size - floor(t_adj / 5);
                END IF;
                t_adj := utl_raw.length(t_buffer);
                dbms_lob.append(t_out, t_buffer);
                FOR i IN 1 .. t_adj LOOP
                    t_s1 := MOD(t_s1 + to_number(rawtohex(utl_raw.substr(t_buffer, i, 1)), 'xx'), 65521);
                END LOOP;
            EXCEPTION
                WHEN OTHERS THEN
                    EXIT;
            END;
        END LOOP;

        t_last_chr := to_number(dbms_lob.substr(p_src, 2, dbms_lob.getlength(p_src) - 1), '0XXX') - t_s1;
        IF t_last_chr < 0 THEN
            t_last_chr := t_last_chr + 65521;
        END IF;
        dbms_lob.append(t_out, hextoraw(to_char(t_last_chr, 'fm0X')));
        IF utl_compress.isopen(t_hdl) THEN
            utl_compress.lz_uncompress_close(t_hdl);
        END IF;
        dbms_lob.freetemporary(t_tmp);
        RETURN t_out;
    END;

    PROCEDURE base64encode(p_clob IN OUT NOCOPY CLOB, p_func_name VARCHAR2 := NULL) IS
        v_blob       BLOB;
        v_raw        RAW(32767);
        v_chars      VARCHAR2(32767);
        v_impmode    BOOLEAN := (p_func_name IS NOT NULL);
        v_width PLS_INTEGER := CASE WHEN v_impmode THEN 1000 ELSE 20000 END;
        dest_offset  INTEGER := 1;
        src_offset   INTEGER := 1;
        lob_csid     NUMBER := dbms_lob.default_csid;
        lang_context INTEGER := dbms_lob.default_lang_ctx;
        warning      INTEGER;
        PROCEDURE wr(p_line VARCHAR2) IS
        BEGIN
            dbms_lob.writeAppend(p_clob, LENGTH(p_line) + 1, p_line || CHR(10));
            dbms_output.put_line(p_line);
        END;
    BEGIN
        IF p_clob IS NULL OR nvl(dbms_lob.getLength(p_clob),0)=0 THEN
            RETURN;
        END IF;
        IF NOT v_impmode AND dbms_db_version.version not in(18,19) THEN --bug# 28649388
            BEGIN
                EXECUTE IMMEDIATE 'begin :lob := sys.dbms_report.ZLIB2BASE64_CLOB(:lob);end;'
                    USING IN OUT p_clob;
                p_clob := REPLACE(p_clob, CHR(10));
                RETURN;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END IF;

        dbms_lob.createtemporary(v_blob, TRUE);
        dbms_lob.ConvertToBLOB(v_blob, p_clob, dbms_lob.getLength(p_clob), dest_offset, src_offset, lob_csid, lang_context, warning);
        dbms_lob.createtemporary(p_clob, TRUE);
        IF NOT v_impmode THEN
            v_blob := zlib_compress(v_blob);
        ELSE
            v_blob := utl_compress.lz_compress(v_blob);
            wr('FUNCTION '||p_func_name||' RETURN CLOB IS ');
            wr('    v_clob       CLOB;');
            wr('    v_blob       BLOB;');
            wr('    dest_offset  INTEGER := 1;');
            wr('    src_offset   INTEGER := 1;');
            wr('    lob_csid     NUMBER  := dbms_lob.default_csid;');
            wr('    lang_context INTEGER := dbms_lob.default_lang_ctx;');
            wr('    warning      INTEGER;');
            wr('    procedure ap(p_line VARCHAR2) is r RAW(32767) := utl_encode.base64_decode(utl_raw.cast_to_raw(p_line));begin dbms_lob.writeAppend(v_blob,utl_raw.length(r),r);end;');
            wr('BEGIN');
            wr('    dbms_lob.CreateTemporary(v_blob,TRUE);');
            wr('    dbms_lob.CreateTemporary(v_clob,TRUE);');
        END IF;
        
        src_offset  := 1;
        dest_offset := dbms_lob.getLength(v_blob);
    
        LOOP
            v_raw   := dbms_lob.substr(v_blob, v_width, OFFSET => src_offset);
            v_chars := regexp_replace(utl_raw.cast_to_varchar2(utl_encode.base64_encode(v_raw)), '[' || CHR(10) || chr(13) || ']+');
            IF v_impmode THEN
                wr('    ap(''' || v_chars || ''');');
            ELSE
                IF src_offset > 1 THEN
                    v_chars := CHR(10) || v_chars;
                END IF;
                dbms_lob.writeappend(p_clob, LENGTH(v_chars), v_chars);
            END IF;
            src_offset := src_offset + v_width;
            EXIT WHEN src_offset >= dest_offset;
        END LOOP;
        IF v_impmode THEN
           wr('    v_blob := utl_compress.lz_uncompress(v_blob);');
           wr('    dbms_lob.ConvertToCLOB(v_clob, v_blob, dbms_lob.getLength(v_blob), dest_offset, src_offset, lob_csid, lang_context, warning);');
           wr('    return v_clob;'); 
           wr('END;'); 
        END IF;
    END;]]
return dicts