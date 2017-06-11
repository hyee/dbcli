local env=env
local db,cfg,event,var=env.getdb(),env.set,env.event,env.var
local extvars={}
local datapath=debug.getinfo(1, "S").source:sub(2):gsub('[%w%.]+$','dict')
local re=env.re

function extvars.on_before_db_exec(item)
    var.setInputs("lz_compress",db.lz_compress);
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
    return item
end

local fmt='%s(select /*+merge*/ * from %s where %s=%d :others:)%s'
local instance,container
local function rep_instance(prefix,full,obj,suffix)
    obj=obj:upper()
    local flag,str=0
    if instance>0 and extvars.dict[obj] and extvars.dict[obj].inst_col then
        str=fmt:format(prefix,full,extvars.dict[obj].inst_col,instance,suffix)
        flag=flag+1
    end
    if container>0 and extvars.dict[obj] and extvars.dict[obj].cdb_col then
        if flag==0 then
            str=fmt:format(prefix,full,extvars.dict[obj].cdb_col,container,suffix)
        else
            str=str:gsub(':others:','and '..extvars.dict[obj].cdb_col..'='..container)
        end
        flag=flag+2
    end
    if flag==0 then
        str=prefix..full..suffix
    elseif flag<3 then 
        str=str:gsub(' :others:','') 
    end
    env.log_debug('extvars',str)
    return str
end

function extvars.on_before_parse(item)
    local db,sql,args,params=table.unpack(item)
    instance,container=tonumber(cfg.get("instance")),tonumber(cfg.get("container"))
    if instance==0 then instance=tonumber(db.props.instance) end
    if container==0 then container=tonumber(db.props.container_id) end
    if instance>0 or container>0 then
        if not extvars.dict then extvars.dict=env.load_data(datapath) end
        item[2]=re.gsub(sql..' ',extvars.P,rep_instance):sub(1,-2)
    end
    return item
end

function extvars.set_title(name,value,orig)
    local get=env.set.get
    local title=table.concat({tonumber(get("INSTANCE"))>-1   and "Inst="..get("INSTANCE") or "",
                              tonumber(get("CONTAINER"))>-1   and "Con_id="..get("CONTAINER") or "",
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
            SELECT table_name,
                   MAX(CASE WHEN COLUMN_NAME IN ('INST_ID', 'INSTANCE_NUMBER') THEN COLUMN_NAME END) INST_COL,
                   MAX(CASE WHEN COLUMN_NAME IN ('CON_ID') THEN COLUMN_NAME END) CON_COL
            FROM   (SELECT table_name, column_name
                    FROM   dba_tab_cols, dba_users
                    WHERE  user_id IN (SELECT SCHEMA# FROM sys.registry$ UNION ALL SELECT SCHEMA# FROM sys.registry$schemas)
                    AND    username = owner
                    AND    column_name IN ('INST_ID', 'INSTANCE_NUMBER', 'CON_ID')
                    UNION ALL
                    SELECT t.kqftanam, c.kqfconam
                    FROM   x$kqfta t, x$kqfco c
                    WHERE  c.kqfconam IN ('INST_ID', 'INSTANCE_NUMBER', 'CON_ID')
                    AND    c.kqfcotab = t.indx
                    AND    c.inst_id = t.inst_id)
            GROUP  BY TABLE_NAME]])
        local rows=db.resultset:rows(rs,-1)
        for i=2,#rows do
            dict[rows[i][1]]={inst_col=(rows[i][2]~="" and rows[i][2] or nil),cdb_col=(rows[i][3]~="" and rows[i][3] or nil)}
            local prefix,suffix=rows[i][1]:match('(.-$)(.*)')
            if prefix=='GV_$' or prefix=='V_$' then
                dict[prefix:gsub('_','')..suffix]=dict[rows[i][1]]
            end
        end
        env.save_data(datapath,dict)
        extvars.dict=dict
        print((#rows-1)..' records saved into '..datapath)
    end
    return tonumber(value)
end

function extvars.set_container(name,value)
    env.checkerr(db.props.db_version and tonumber(db.props.db_version:match('%d+')),'Unsupported version!')
    return tonumber(value)
end

function extvars.onload()
    event.snoop('BEFORE_DB_EXEC',extvars.on_before_parse,nil,50)
    event.snoop('BEFORE_ORACLE_EXEC',extvars.on_before_db_exec)
    event.snoop('ON_SETTING_CHANGED',extvars.set_title)
    cfg.init("instance",-1,extvars.set_instance,"oracle","Auto-limit the inst_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-2 - 99")
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
        prefix  <- "GV_$"/"GV$"/"V_$"/"V$"/"DBA_"/"ALL_"/"CDB_"
    ]],nil,true)
end

db.lz_compress=[[
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
        dbms_lob.createtemporary(t_cpr, FALSE);
        t_cpr := hextoraw('789C'); -- zlib header
        dbms_lob.copy(t_cpr, t_tmp, dbms_lob.getlength(t_tmp) - 10 - 8, 3, 11);
        dbms_lob.append(t_cpr, hextoraw(adler32(p_src))); -- zlib trailer
        dbms_lob.freetemporary(t_tmp);
        RETURN t_cpr;
    END;

    FUNCTION zlib_decompress(p_src IN BLOB) RETURN BLOB IS
        t_out      BLOB;
        t_tmp      BLOB;
        t_buffer   RAW(1);
        t_hdl      BINARY_INTEGER;
        t_s1       PLS_INTEGER; -- s1 part of adler32 checksum
        t_last_chr PLS_INTEGER;
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
                utl_compress.lz_uncompress_extract(t_hdl, t_buffer);
            EXCEPTION
                WHEN OTHERS THEN
                    EXIT;
            END;
            dbms_lob.append(t_out, t_buffer);
            t_s1 := MOD(t_s1 + to_number(rawtohex(t_buffer), 'xx'), 65521);
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

    PROCEDURE base64encode(p_clob IN OUT NOCOPY CLOB, p_width INT := 20000) IS
        v_blob       BLOB;
        v_raw        RAW(32767);
        v_chars      VARCHAR2(32767);
        dest_offset  INTEGER := 1;
        src_offset   INTEGER := 1;
        lob_csid     NUMBER := dbms_lob.default_csid;
        lang_context INTEGER := dbms_lob.default_lang_ctx;
        warning      INTEGER;
    BEGIN
        IF dbms_lob.getLength(p_clob) IS NULL THEN
            RETURN;
        END IF;
        IF p_width !=1000 THEN
            BEGIN
                EXECUTE IMMEDIATE 'begin :lob := sys.dbms_report.ZLIB2BASE64_CLOB(:lob);end;'
                    USING IN OUT p_clob;
                p_clob := REPLACE(p_clob, CHR(10));
                RETURN;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
        dbms_lob.createtemporary(v_blob, TRUE);
        dbms_lob.ConvertToBLOB(v_blob, p_clob, dbms_lob.getLength(p_clob), dest_offset, src_offset, lob_csid, lang_context, warning);
        IF p_width !=1000 THEN
            v_blob := zlib_compress(v_blob);
        ELSE
            v_blob := utl_compress.lz_compress(v_blob);
        END IF;
        dbms_lob.createtemporary(p_clob, TRUE);
        src_offset  := 1;
        dest_offset := dbms_lob.getLength(v_blob);
        LOOP
            v_raw   := dbms_lob.substr(v_blob, p_width, OFFSET => src_offset);
            v_chars := regexp_replace(utl_raw.cast_to_varchar2(utl_encode.base64_encode(v_raw)), '[' || CHR(10) || chr(13) || ']+');
            IF src_offset > 1 THEN
                v_chars := CHR(10) || v_chars;
            END IF;
            dbms_lob.writeappend(p_clob, LENGTH(v_chars), v_chars);
            src_offset := src_offset + p_width;
            EXIT WHEN src_offset >= dest_offset;
        END LOOP;
    END;]]
return extvars