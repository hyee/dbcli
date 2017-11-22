local env=env
local db,cfg,event,var=env.getdb(),env.set,env.event,env.var
local extvars={}
local datapath=debug.getinfo(1, "S").source:sub(2):gsub('[%w%.]+$','dict')
local re=env.re
local uid=nil


local fmt='%s(select /*+merge*/ * from %s where %s=%s :others:)%s'
local instance,container,usr
local function rep_instance(prefix,full,obj,suffix)
    obj=obj:upper()
    local flag,str=0
    if instance>0 and extvars.dict[obj] and extvars.dict[obj].inst_col then
        str=fmt:format(prefix,full,extvars.dict[obj].inst_col,''..instance,suffix)
        flag=flag+1
    end
    if container>0 and extvars.dict[obj] and extvars.dict[obj].cdb_col then
        if flag==0 then
            str=fmt:format(prefix,full,extvars.dict[obj].cdb_col,''..container,suffix)
        else
            str=str:gsub(':others:','and '..extvars.dict[obj].cdb_col..'='..container..' :others:')
        end
        flag=flag+2
    end

    if uid and extvars.dict[obj] and extvars.dict[obj].usr_col then
        local filter="(select /*+no_merge*/ username from all_users where user_id="..uid..")"
        if flag==0 then
            str=fmt:format(prefix,full,extvars.dict[obj].usr_col,filter,suffix)
        else
            str=str:gsub(':others:','and '..extvars.dict[obj].usr_col.."="..filter)
        end
        flag=flag+4
    end

    if flag==0 then
        str=prefix..full..suffix
    elseif flag<7 then
        str=str:gsub(' :others:','') 
    end
    env.log_debug('extvars',str)
    return str
end

function extvars.on_before_db_exec(item)
    for i=1,2 do
        if item and type(item[i])=="string" and item[i]:find('&lz_compress',1,true) then
            item[i]=item[i]:gsub("&lz_compress",db.lz_compress);
        end
    end

    if not var.outputs['INSTANCE'] then
        local instance=tonumber(cfg.get("INSTANCE"))
        var.setInputs("INSTANCE",tostring(instance>0 and instance or instance<0 and "" or db.props.instance))
    end
    if not var.outputs['STARTTIME'] then
        var.setInputs("STARTTIME",cfg.get("STARTTIME"))
    end
    if not var.outputs['ENDTIME'] then
        var.setInputs("ENDTIME",cfg.get("ENDTIME"))
    end
    if not var.outputs['SCHEMA'] then
        var.setInputs("SCHEMA",cfg.get("SCHEMA"))
    end
    if not extvars.dict then return item end
    local db,sql,args,params=table.unpack(item)
    instance,container,usr=tonumber(cfg.get("instance")),tonumber(cfg.get("container")),cfg.get("schema")
    if instance==0 then instance=tonumber(db.props.instance) end
    if container==0 then container=tonumber(db.props.container_id) end
    if sql and (instance>0 or container>0 or (usr and usr~="")) then
        item[2]=re.gsub(sql..' ',extvars.P,rep_instance):sub(1,-2)
    end
    return item
end

function extvars.set_title(name,value,orig)
    local get=env.set.get
    local title=table.concat({tonumber(get("INSTANCE"))>-1   and "Inst="..get("INSTANCE") or "",
                              tonumber(get("CONTAINER"))>-1   and "Con_id="..get("CONTAINER") or "",
                              get("SCHEMA")~=""   and "Schema="..get("SCHEMA") or "",
                              get("STARTTIME")~='' and "Start="..get("STARTTIME") or "",
                              get("ENDTIME")~=''   and "End="..get("ENDTIME") or ""},"  ")
    title=title:trim()
    env.set_title(title~='' and "Filter: ["..title.."]" or nil)
end

function extvars.check_time(name,value)
    if not value or value=="" then return "" end
    print("Time set as",db:check_date(value,'YYMMDDHH24MISS'))
    return value:trim()
end

function extvars.set_instance(name,value)
    if tonumber(value)==-2 then
        local dict={}
        local rs=db:internal_call([[
            with r as(
                    SELECT /*+no_merge*/ owner,table_name, column_name col,data_type
                    FROM   dba_tab_cols, dba_users
                    WHERE  user_id IN (SELECT SCHEMA# FROM sys.registry$ UNION ALL SELECT SCHEMA# FROM sys.registry$schemas)
                    AND    username = owner
                    AND    (owner,table_name) in(select distinct owner,TABLE_NAME from dba_tab_privs where grantee in('PUBLIC','SELECT_CATALOG_ROLE'))  
                    UNION ALL
                    SELECT 'SYS',t.kqftanam, c.kqfconam, decode(kqfcodty,1,'VARCHAR2',2,'NUMBER',null)
                    FROM   (SELECT kqftanam,t.indx,t.inst_id FROM x$kqfta t
                            UNION ALL
                            SELECT KQFDTEQU,t.indx,t.inst_id FROM x$kqfta t,x$kqfdt where kqftanam=KQFDTNAM) t, x$kqfco c
                    WHERE  c.kqfcotab = t.indx
                    AND    c.inst_id = t.inst_id)
            SELECT table_name,
                   MAX(CASE WHEN col IN ('INST_ID', 'INSTANCE_NUMBER') AND TABLE_NAME NOT LIKE 'X$%' THEN col END) INST_COL,
                   MAX(CASE WHEN col IN ('CON_ID') THEN col END) CON_COL,
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
                    select owner,table_name,null,type 
                    from   dba_tab_privs 
                    where  grantee in('EXECUTE_CATALOG_ROLE','SELECT_CATALOG_ROLE'))
            GROUP  BY TABLE_NAME]])
        local rows=db.resultset:rows(rs,-1)
        local cnt1=#rows
        for i=2,cnt1 do
            dict[rows[i][1]]={
                inst_col=(rows[i][2]~="" and rows[i][2] or nil),
                cdb_col=(rows[i][3]~="" and rows[i][3] or nil),
                usr_col=(rows[i][4]~="" and rows[i][4] or nil),
                owner=rows[i][5]
            }
            local prefix,suffix=rows[i][1]:match('(.-$)(.*)')
            if prefix=='GV_$' or prefix=='V_$' then
                dict[prefix:gsub('_','')..suffix]=dict[rows[i][1]]
            end
        end
        local keywords={}
        rs=db:internal_call("select KEYWORD from V$RESERVED_WORDS where length(KEYWORD)>3")
        rows=db.resultset:rows(rs,-1)
        local cnt2=#rows
        for i=2,cnt2 do
            keywords[rows[i][1]]=1
        end
        env.save_data(datapath,{dict=dict,keywords=keywords})
        extvars.dict=dict
        print((cnt1+cnt2-2)..' records saved into '..datapath)
    end
    return tonumber(value)
end

function extvars.set_container(name,value)
    env.checkerr(db.props.db_version and tonumber(db.props.db_version:match('%d+')),'Unsupported version!')
    return tonumber(value)
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
    return value
end

function extvars.on_after_db_conn()
    cfg.force_set('instance','default')
    cfg.force_set('starttime','default')
    cfg.force_set('endtime','default')
    cfg.force_set('schema','default')
    cfg.force_set('container','default')
end

function test_grid()
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

function extvars.onload()
    env.set_command(nil,"TEST_GRID",nil,test_grid,false,1)
    event.snoop('BEFORE_DB_EXEC',extvars.on_before_db_exec,nil,60)
    event.snoop('ON_SUBSTITUTION',extvars.on_before_db_exec,nil,60)
    event.snoop('AFTER_ORACLE_CONNECT',extvars.on_after_db_conn)
    event.snoop('ON_SETTING_CHANGED',extvars.set_title)
    cfg.init("instance",-1,extvars.set_instance,"oracle","Auto-limit the inst_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-2 - 99")
    cfg.init("schema","",extvars.set_schema,"oracle","Auto-limit the schema of impacted tables. ","*")
    cfg.init({"container","con","con_id"},-1,extvars.set_container,"oracle","Auto-limit the con_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-1 - 99")
    cfg.init("starttime","",extvars.check_time,"oracle","Specify the start time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
    cfg.init("endtime","",extvars.check_time,"oracle","Specify the end time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
    
    extvars.P=re.compile([[
        pattern <- {pt} {owner* obj} {suffix}
        suffix  <- [%s,;)]
        pt      <- [%s,(]
        owner   <- ('SYS.'/ 'PUBLIC.'/'"SYS".'/'"PUBLIC".')
        obj     <- full/name
        full    <- '"' name '"'
        name    <- {prefix %a%a [%w$#__]+}
        prefix  <- "GV_$"/"GV$"/"V_$"/"V$"/"DBA_"/"ALL_"/"CDB_"/"X$"/"XV$"
    ]],nil,true)
    env.load_data(datapath,true,function(data)
        extvars.dict=data.dict
        --env.write_cache("1.txt",table.dump(data))
        if data.keywords then
            for k,v in pairs(data.dict) do data.keywords[v.owner..'.'..k]=1 end
            console:setKeywords(data.keywords) 
        end
    end)
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
        t_tmp      BLOB;
    BEGIN  
        dbms_lob.createtemporary(t_tmp, TRUE);
        t_tmp := hextoraw('1F8B0800000000000003'); -- gzip header
        dbms_lob.copy(t_tmp, p_src, dbms_lob.getlength(p_src) - 2 - 4, 11, 3);
        --dbms_lob.append( t_tmp, hextoraw( '0000000000000000' ) ); -- add a fake trailer
        t_tmp := utl_compress.lz_uncompress(t_tmp);
        RETURN t_tmp;
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
        IF p_clob IS NULL OR dbms_lob.getLength(p_clob) IS NULL THEN
            RETURN;
        END IF;
        IF NOT v_impmode THEN
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