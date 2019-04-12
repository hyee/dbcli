local env=env
local db,cfg,event,var,type=env.getdb(),env.set,env.event,env.var,type
local extvars={}
local datapath=env.join_path(env.WORK_DIR,'oracle/dict.pack')
local re=env.re
local uid=nil
local cache={}

local fmt='%s(select /*+merge*/ * from %s where %s=%s :others:)%s'
local fmt1='%s(select /*+merge*/  %d inst_id,a.* from %s a where 1=1 :others:)%s'
local instance,container,usr,dbid,starttime,endtime
local cdbmode='off'
local cdbstr='^[CD][DB][BA]_HIST_'
local noparallel='off'
local gv1=('(%s)table%(%s*gv%$%(%s*cursor%('):case_insensitive_pattern()
local gv2=('(%s)gv%$%(%s*cursor%('):case_insensitive_pattern()
local function rep_instance(prefix,full,obj,suffix)
    obj=obj:upper()
    local flag,str=0
    if extvars.dict[obj] then
        for k,v in ipairs{
            {instance and instance>0,extvars.dict[obj].inst_col,instance},
            {container and container>=0,extvars.dict[obj].cdb_col,container},
            {dbid and dbid>0,extvars.dict[obj].dbid_col,dbid},
            {usr and usr~="",extvars.dict[obj].usr_col,"(select /*+no_merge*/ username from all_users where user_id="..usr..")"},
        } do
            if v[1] and v[2] and v[3] then
                if k==1 and obj:find('^GV_?%$') and v[3]==tonumber(db.props.instance)
                then
                    str=fmt1:format(prefix,instance,full:gsub("[gG]([vV]_?%$)","%1"),suffix)
                elseif flag==0 then
                    str=fmt:format(prefix,full,v[2],''..v[3],suffix)
                else
                    str=str:gsub(':others:','and '..v[2]..'='..v[3]..' :others:')
                end
                flag = flag +1
            end

            if cdbmode~='off' and extvars.dict[obj] and obj:find(cdbstr)  then
                local new_obj=obj:gsub('^DBA_HIST_',cdbmode=='cdb' and 'CDB_HIST_' or 'AWR_PDB_')
                if extvars.dict[new_obj] and new_obj~=obj then
                    if not full:find(obj) then new_obj=new_obj:lower() end
                    if flag==0 then
                        full=full:gsub(obj:escape('*i'),new_obj)
                    else
                        str=str:gsub(obj:escape('*i'),new_obj)
                    end
                end
            end
        end
    end
    if flag==0 then
        str=prefix..full..suffix
    else
        str=str:gsub('where 1=1 and','where'):gsub(' where 1=1 :others:',''):gsub(' :others:','')
        env.log_debug('extvars',str)
    end
    return str
end

function extvars.on_before_db_exec(item)
    for i=1,2 do
        if item and type(item[i])=="string" and item[i]:find('@lz_compress@',1,true) then
            item[i]=item[i]:gsub("@lz_compress@",db.lz_compress);
        end
    end

    instance,container,usr,dbid,starttime,endtime=tonumber(cfg.get("instance")),tonumber(cfg.get("container")),cfg.get("schema"),cfg.get("dbid"),cfg.get("STARTTIME"),cfg.get("ENDTIME")
    if instance==0 then instance=tonumber(db.props.instance) end
    for k,v in ipairs{
        {'INSTANCE',instance and instance>0 and instance or ""},
        {'DBID',dbid and dbid>0 and dbid or ""},
        {'CON_ID',container and container>=0 and container  or ""},
        {'STARTTIME',starttime},
        {'ENDTIME',endtime},
        {'SCHEMA',usr},
        {'cdbmode',cdbmode~='off' and cdbmode or ''}
    } do
        if var.outputs[v[1]]==nil then var.setInputs(v[1],''..v[2]) end
    end

    if not extvars.dict then return item end
    local db,sql,args,params=table.unpack(item)

    if sql and not cache[sql] then
        if db.props and type(db.props.version)=='number' and (db.props.israc==false or db.props.version<11) and not sql:find('^'..(env.ROOT_CMD:escape())) then
            sql=sql:gsub(gv1,'%1((('):gsub(gv2,"%1((")
        end
        item[2]=re.gsub(sql..' ',extvars.P,rep_instance):sub(1,-2)
        cache[item[2]]=1
    end
    return item
end

function extvars.on_after_db_exec()
    table.clear(cache)
end

local noparallel_sql=[[
    begin 
        execute immediate 'alter session set events ''10384 trace name context %s''';
    exception
        when others then
            if sqlcode=-1031 then execute immediate 'alter session %s parallel query';end if;
    end;
]]
function extvars.set_noparallel(name,value)
    if noparallel==value then return value end
    db:internal_call(noparallel_sql:format(value=="off" and "off" or "forever , level 16384",value=='off' and 'enable' or 'disable'))
    noparallel=value
    return value
end

function extvars.set_title(name,value,orig)
    local get=env.set.get
    local title={ tonumber(get("INSTANCE"))>-1   and "Inst="..get("INSTANCE") or "",
                  tonumber(get("DBID"))>0   and "DBID="..get("DBID") or "",
                  tonumber(get("CONTAINER"))>-1   and "Con_id="..get("CONTAINER") or "",
                  get("SCHEMA")~=""   and "Schema="..get("SCHEMA") or "",
                  get("STARTTIME")~='' and "Start="..get("STARTTIME") or "",
                  get("ENDTIME")~=''   and "End="..get("ENDTIME") or "",
                  get("CDBMODE")~='off' and (get("CDBMODE"):upper().."=on") or "",
                  noparallel~='off' and "PX=off" or ""}
    for i=#title,1,-1 do
        if title[i]=='' then table.remove(title,i) end
    end
    title=table.concat(title,'   '):trim()
    env.set_title(title~='' and "Filter: ["..title.."]" or nil)
end

function extvars.check_time(name,value)
    if not value or value=="" then return "" end
    print("Time set as",db:check_date(value,'YYMMDDHH24MISS'))
    return value:trim()
end

function extvars.set_instance(name,value)
    return tonumber(value)
end

function extvars.set_container(name,value)
    if name=='CONTAINER' and value>=0 then env.checkerr(db.props.version and db.props.version > 11,'Current db version does not support the CDB feature!') end
    value=tonumber(value)
    env.checkerr(value and value>=-1 and value==math.floor(value),'Input value must be an integer!');
    return value
end


function extvars.set_schema(name,value)
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
function extvars.set_cdbmode(name,value)
    if value~='off' then db:assert_connect() end
    if not db.props then return end
    if cdbmode==value then return value end
    env.checkerr(value=='off' or db.props.version>11, "Unsupported database: v"..db.props.db_version)
    if value=='pdb' then
        if db.props.container_dbid and db.props.container_id>1 then
            prev_container.dbid=cfg.get('dbid')
            prev_container.container=cfg.get('container')
            prev_container.new_dbid=db.props.container_dbid
            prev_container.new_container=db.props.container_id
            cfg.force_set('dbid',db.props.container_dbid)
            cfg.force_set('container',db.props.container_id)
        end
    elseif cdbmode=='pdb' then
        if prev_container.new_dbid==cfg.get('dbid') and prev_container.new_container==cfg.get('container') then
            cfg.force_set('dbid','default')
            cfg.force_set('container','default')
        end
    end
    cdbmode=value
    return value
end

function extvars.on_after_db_conn()
    if db.props and db.props.isadb==true and db.props.israc==false then
        cfg.force_set('instance', db.props.instance)
    else
        cfg.force_set('instance','default')
    end
    prev_container={}
    --cfg.force_set('starttime','default')
    cfg.force_set('cdbmode','default')
    cfg.force_set('schema','default')
    cfg.force_set('container','default')
    cfg.force_set('dbid','default')
    noparallel='off'
    cfg.force_set('noparallel','off')

    if db.props then
        extvars.db_dict_path=env._CACHE_BASE..'dict_'..(db.props.dbname or 'db'):gsub("%..*$",""):gsub('%W+','-'):lower()..'_'..(db.props.dbid or 0)..'.dat'
    else
        extvars.db_dict_path=datapath
    end

    extvars.cache_obj=nil
    if extvars.current_dict.path~=extvars.db_dict_path and os.exists(extvars.db_dict_path) then
        extvars.load_dict(extvars.db_dict_path)
    end
end


function extvars.test_grid()
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

function extvars.set_dict(type)
    if not type then
        local dict=extvars.current_dict
        if dict.cache==0 then
            for k,v in pairs(extvars.cache_obj or {}) do
                dict.cache=dict.cache+1
            end
        end
        local fmt='$HEADCOLOR$%-18s$NOR$ : %s'
        print(string.rep('=',100))
        print(fmt:format('Current Dictionary',dict.path))
        print(fmt:format('Level#1 Keywords',dict.objects..' (Tab-completion on [<owner>.]<Keyword>)'))
        print(fmt:format('Level#2 Keywords',dict.subobjects..' (Tab-completion on <L1 Keyword>.<L2 Keyword>)'))
        print(fmt:format(' Cached Objects',dict.cache.." (Caches the current db's online dictionary that used for quick search(i.e.: desc/ora obj))"))
        print(fmt:format('    VPD Objects',dict.vpd..' (Used to auto-rewrite SQL for options "SET instance/container/dbid/schema")'))
        checkhelp(type)
    end
    type=type:lower()
    env.checkerr(type=='public' or type=='init',"Invalid parameter!")
    db:assert_connect()
    local sql;
    local path=datapath
    if type=='init' then 
        path=extvars.db_dict_path
        sql=[[
            with r as(
                    SELECT /*+no_merge*/ owner,table_name, column_name col,data_type
                    FROM   dba_tab_cols
                    WHERE  owner in('SYS','PUBLIC')
                    @XTABLE@)
            SELECT  table_name,
                    MAX(CASE WHEN col IN ('INST_ID', 'INSTANCE_NUMBER') THEN col END) INST_COL,
                    MAX(CASE WHEN col IN ('CON_ID') THEN col END) CON_COL,
                    MAX(CASE WHEN col IN ('DBID') THEN col END) DBID_COL,
                    MAX(CASE WHEN DATA_TYPE='VARCHAR2' AND regexp_like(col,'(OWNER|SCHEMA|KGLOBTS4|USER.*NAME)') THEN col END)
                        KEEP(DENSE_RANK FIRST ORDER BY CASE WHEN col LIKE '%OWNER' THEN 1 ELSE 2 END) USR_COL,
                    MAX(owner)
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
            GROUP  BY TABLE_NAME]]
    else
        extvars.load_dict(path)
        sql=[[
            with r as(
                    SELECT /*+no_merge*/ owner,table_name, column_name col,data_type
                    FROM   dba_tab_cols, dba_users
                    WHERE  user_id IN (SELECT SCHEMA# FROM sys.registry$ UNION ALL SELECT SCHEMA# FROM sys.registry$schemas)
                    AND    username = owner
                    AND    (owner,table_name) in(select distinct owner,TABLE_NAME from dba_tab_privs where grantee in('PUBLIC','SELECT_CATALOG_ROLE','EXECUTE_CATALOG_ROLE'))  
                    @XTABLE@)
            SELECT  table_name,
                    MAX(CASE WHEN col IN ('INST_ID', 'INSTANCE_NUMBER') THEN col END) INST_COL,
                    MAX(CASE WHEN col IN ('CON_ID') THEN col END) CON_COL,
                    MAX(CASE WHEN col IN ('DBID') THEN col END) DBID_COL,
                    MAX(CASE WHEN DATA_TYPE='VARCHAR2' AND regexp_like(col,'(OWNER|SCHEMA|KGLOBTS4|USER.*NAME)') THEN col END)
                        KEEP(DENSE_RANK FIRST ORDER BY CASE WHEN col LIKE '%OWNER' THEN 1 ELSE 2 END) USR_COL,
                    MAX(owner)
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
                    where  owner='SYS' 
                    and    regexp_like(object_name,'^(DBMS_|UTL_)')
                    and    instr(object_type,' ')=0
                    union  all
                    select distinct owner,object_name||'.'||procedure_name,null,'PROCEDURE'
                    from   dba_procedures
                    where  owner='SYS' 
                    and    regexp_like(object_name,'^(DBMS_|UTL_)')
                    and    procedure_name is not null
                    union  all
                    select owner,table_name,null,null 
                    from   dba_tab_privs a
                    where  grantee in('EXECUTE_CATALOG_ROLE','SELECT_CATALOG_ROLE'))
            GROUP  BY TABLE_NAME]]
    end

    sql = sql:gsub('@XTABLE@',db.props.isdba~=true and '' or [[
            UNION ALL
            SELECT 'SYS',t.kqftanam, c.kqfconam, decode(kqfcodty,1,'VARCHAR2',2,'NUMBER',null)
            FROM   (SELECT kqftanam,t.indx,t.inst_id FROM x$kqfta t
                    UNION ALL
                    SELECT KQFDTEQU,t.indx,t.inst_id FROM x$kqfta t,x$kqfdt where kqftanam=KQFDTNAM) t, x$kqfco c
            WHERE  c.kqfcotab = t.indx
            AND    c.inst_id = t.inst_id
        ]])

    print('Bulding, it could take several minutes...')
    local rs=db:dba_query(db.internal_call,sql)
    local rows=db.resultset:rows(rs,-1)
    if type=='init' then extvars.dict={} end
    local dict=extvars.dict
    local cnt1=#rows
    for i=2,cnt1 do
        local exists=dict[rows[i][1]]
        dict[rows[i][1]]={
            inst_col=(rows[i][2] or "")~="" and rows[i][2] or (exists and dict[rows[i][1]].inst_col),
            cdb_col=(rows[i][3] or "")~=""  and rows[i][3] or (exists and dict[rows[i][1]].cdb_col),
            dbid_col=(rows[i][4] or "")~="" and rows[i][4] or (exists and dict[rows[i][1]].dbid_col),
            usr_col=(rows[i][5] or "")~=""  and rows[i][5] or (exists and dict[rows[i][1]].usr_col),
            owner=(rows[i][6] or "")~=""    and rows[i][6] or (exists and dict[rows[i][1]].owner)
        }
        local prefix,suffix=rows[i][1]:match('(.-$)(.*)')
        if prefix=='GV_$' or prefix=='V_$' then
            dict[prefix:gsub('_','')..suffix]=dict[rows[i][1]]
        end
    end
    local keywords,done,cnt2={}
    done,rs=pcall(db.internal_call,db,"select KEYWORD from V$RESERVED_WORDS where length(KEYWORD)>3")
    if done then
        rows=db.resultset:rows(rs,-1)
        cnt2=#rows
        for i=2,cnt2 do
            keywords[rows[i][1]]=1
        end
    else
        cnt2=2
    end
    env.save_data(path,{dict=dict,keywords=keywords,cache=(type=='init' and extvars.cache_obj) or nil},31*1024*1024)
    extvars.load_dict(path)
    print((cnt1+cnt2-2)..' records saved into '..path)
end

function extvars.load_dict(path)
    env.load_data(path,true,function(data)
        extvars.dict=data.dict
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
        end
        extvars.current_dict=dict
        if data.cache then 
            extvars.cache_obj=data.cache
        end
        env.log_debug('extvars','Loaded dictionry '..path)
    end)
end

function extvars.onload()
    env.set_command(nil,"TEST_GRID",nil,extvars.test_grid,false,1)
    env.set_command(nil,'DICT',"Show or create dictionary for auto completion. Usage: @@NAME [init]\n\n init: Create a separate offline dictionary that only used for current database",extvars.set_dict,false,2)
    event.snoop('BEFORE_DB_EXEC',extvars.on_before_db_exec,nil,60)
    event.snoop('AFTER_DB_EXEC',extvars.on_after_db_exec)
    event.snoop('ON_SUBSTITUTION',extvars.on_before_db_exec,nil,60)
    event.snoop('AFTER_ORACLE_CONNECT',extvars.on_after_db_conn)
    event.snoop('ON_DB_DISCONNECTED',extvars.on_after_db_conn)
    event.snoop('ON_SETTING_CHANGED',extvars.set_title)
    cfg.init("cdbmode","off",extvars.set_cdbmode,"oracle","Controls whether to auto-replace all SQL texts from 'DBA_HIST_' to 'CDB_HIST_'/'AWR_PDB_'","cdb,pdb,off")
    cfg.init("instance",-1,extvars.set_instance,"oracle","Auto-limit the inst_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-1 - 99")
    cfg.init("schema","",extvars.set_schema,"oracle","Auto-limit the schema of impacted tables. ","*")
    cfg.init({"container","con","con_id"},-1,extvars.set_container,"oracle","Auto-limit the con_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-1 - 32768")
    cfg.init("dbid",0,extvars.set_container,"oracle","Specify the dbid for AWR analysis")
    cfg.init("starttime","",extvars.check_time,"oracle","Specify the start time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
    cfg.init("endtime","",extvars.check_time,"oracle","Specify the end time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
    cfg.init("noparallel","off",extvars.set_noparallel,"oracle","Controls executing SQL statements in no parallel mode. refer to MOS 1114405.1","on,off");
    extvars.P=re.compile([[
        pattern <- {pt} {owner* obj} {suffix}
        suffix  <- [%s,;)]
        pt      <- [%s,(]
        owner   <- ('SYS.'/ 'PUBLIC.'/'"SYS".'/'"PUBLIC".')
        obj     <- full/name
        full    <- '"' name '"'
        name    <- {prefix %a%a [%w$#__]+}
        prefix  <- "GV_$"/"GV$"/"V_$"/"V$"/"DBA_"/"AWR_"/"ALL_"/"CDB_"/"X$"/"XV$"
    ]],nil,true)
    extvars.load_dict(datapath)
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
        declare x raw(?);
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
                    EXECUTE IMMEDIATE REPLACE(sq, '?', t_adj)
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
return extvars