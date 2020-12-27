--References:
--    http://blog.teusink.net/2010/04/unwrapping-oracle-plsql-with-unwrappy.html
--    http://blog.csdn.net/akinosun/article/details/8041199

local table,string=table,string
local env,db,ffi,zlib=env,env.getdb(),env.ffi,env.zlib
local unwrap={}

local charmap={0x3d, 0x65, 0x85, 0xb3, 0x18, 0xdb, 0xe2, 0x87, 0xf1, 0x52,
               0xab, 0x63, 0x4b, 0xb5, 0xa0, 0x5f, 0x7d, 0x68, 0x7b, 0x9b,
               0x24, 0xc2, 0x28, 0x67, 0x8a, 0xde, 0xa4, 0x26, 0x1e, 0x03,
               0xeb, 0x17, 0x6f, 0x34, 0x3e, 0x7a, 0x3f, 0xd2, 0xa9, 0x6a,
               0x0f, 0xe9, 0x35, 0x56, 0x1f, 0xb1, 0x4d, 0x10, 0x78, 0xd9,
               0x75, 0xf6, 0xbc, 0x41, 0x04, 0x81, 0x61, 0x06, 0xf9, 0xad,
               0xd6, 0xd5, 0x29, 0x7e, 0x86, 0x9e, 0x79, 0xe5, 0x05, 0xba,
               0x84, 0xcc, 0x6e, 0x27, 0x8e, 0xb0, 0x5d, 0xa8, 0xf3, 0x9f,
               0xd0, 0xa2, 0x71, 0xb8, 0x58, 0xdd, 0x2c, 0x38, 0x99, 0x4c,
               0x48, 0x07, 0x55, 0xe4, 0x53, 0x8c, 0x46, 0xb6, 0x2d, 0xa5,
               0xaf, 0x32, 0x22, 0x40, 0xdc, 0x50, 0xc3, 0xa1, 0x25, 0x8b,
               0x9c, 0x16, 0x60, 0x5c, 0xcf, 0xfd, 0x0c, 0x98, 0x1c, 0xd4,
               0x37, 0x6d, 0x3c, 0x3a, 0x30, 0xe8, 0x6c, 0x31, 0x47, 0xf5,
               0x33, 0xda, 0x43, 0xc8, 0xe3, 0x5e, 0x19, 0x94, 0xec, 0xe6,
               0xa3, 0x95, 0x14, 0xe0, 0x9d, 0x64, 0xfa, 0x59, 0x15, 0xc5,
               0x2f, 0xca, 0xbb, 0x0b, 0xdf, 0xf2, 0x97, 0xbf, 0x0a, 0x76,
               0xb4, 0x49, 0x44, 0x5a, 0x1d, 0xf0, 0x00, 0x96, 0x21, 0x80,
               0x7f, 0x1a, 0x82, 0x39, 0x4f, 0xc1, 0xa7, 0xd7, 0x0d, 0xd1,
               0xd8, 0xff, 0x13, 0x93, 0x70, 0xee, 0x5b, 0xef, 0xbe, 0x09,
               0xb9, 0x77, 0x72, 0xe7, 0xb2, 0x54, 0xb7, 0x2a, 0xc7, 0x73,
               0x90, 0x66, 0x20, 0x0e, 0x51, 0xed, 0xf8, 0x7c, 0x8f, 0x2e,
               0xf4, 0x12, 0xc6, 0x2b, 0x83, 0xcd, 0xac, 0xcb, 0x3b, 0xc4,
               0x4e, 0xc0, 0x69, 0x36, 0x62, 0x02, 0xae, 0x88, 0xfc, 0xaa,
               0x42, 0x08, 0xa6, 0x45, 0x57, 0xd3, 0x9a, 0xbd, 0xe1, 0x23,
               0x8d, 0x92, 0x4a, 0x11, 0x89, 0x74, 0x6b, 0x91, 0xfb, 0xfe,
               0xc9, 0x01, 0xea, 0x1b, 0xf7, 0xce}


local function decode_base64_package(base64str)
    local base64dec = loader:Base642Bytes(base64str):sub(21)
    local decoded = {}
    for i=1,#base64dec do
            --print(base64dec:sub(i,i):byte(),base64dec:sub(i,i))
            --decoded[i] = string.char(charmap[base64dec:sub(i,i):byte()+1])
        decoded[i] = charmap[base64dec:sub(i,i):byte()+1]
    end
    --print(table.concat(decoded,''))
    return loader:inflate(decoded)
    --return zlib.uncompress(table.concat(decoded,''))
end

function unwrap.unwrap_schema(obj,ext)
    local list=db:dba_query(db.get_rows,[[
        select owner||'.'||object_name o 
        from all_objects 
        where owner=:1 and object_type in('TRIGGER','TYPE','PACKAGE','FUNCTION','PROCEDUR') 
        and   not regexp_like(object_name,'^(SYS_YOID|SYS_PLSQL_|KU$_WORKER)')
        ORDER BY 1]],{obj:upper()})
    if type(list) ~='table' or #list<2 then return false end
    for i=2,#list do
        local n=list[i][1]
        local done,err=pcall(unwrap.unwrap,n,ext)
        if not done then env.warn(err) end
    end
    return true
end

function unwrap.unwrap(obj,ext,prefix)
    env.checkhelp(obj)
    local filename=obj
    local typ,f=os.exists(obj)
    if ext=='.' then 
        ext=nil
    elseif ext and ext:lower()=='18c' then
        ext,prefix=nil,'18c'
    end
    prefix=prefix or ''
    if typ then
        if typ~="file" then return end
        filename,org_ext=obj:match("(.*)%.(.-)$")
        if filename then
            if not ext then
                filename,ext=filename..'_unwrap',org_ext
            end
            filename=filename.."."..ext
        else
            filename=obj..'.'..(ext or 'unwrap')
        end

        local f=io.open(obj)

        local found,stack,org,repidx=false,{},{}
        for line in f:lines() do
            local piece=line:match("^%s*([%w%+%/%=]+)$")
            if not found and piece and #piece>=64 then
                found=true
                repidx=#org+1
            end
            if found then 
                if piece then
                    stack[#stack+1]=piece
                else
                    org[#org+1]=line
                end
                if not piece or #piece<64 then
                    org[#org+1]=loader:Base64ZlibToText({table.concat(stack,'')})
                    stack={}
                    found=false
                end
            else
                if line:match('encode=".-"') and line:match('compress=".-"') then
                    org[#org+1]=line:gsub('encode=".-"',''):gsub('compress=".-"','')
                else
                    org[#org+1]=line
                end
            end
        end
        if repidx == -1 then return end
        if #stack>0 then org[#org]=loader:Base64ZlibToText({table.concat(stack,'')}) end
        local text=table.concat(org,'\n')
        if prefix:lower()=='18c' then
            local ver
            text = text:gsub('(version *= *"(%d+%.%d+%.[%d%.]+))"',function(txt,v)
                local v1=tonumber(v:match('%d+'))
                if v1 > 18 then
                    ver=v1
                    return 'version = "18.0.0.0.0"'
                end
                return txt
            end)
            if ver > 18 then
                text = text:gsub("(https?://[^\n]+/)omx/",'%1',1)
                text = text:gsub('emsaasui[^\n]+(/scripts/activeReportInit.js)','emviewers%1',1)
            end
        end
        env.save_data(filename,text)
        print("Decoded Base64 written to file "..filename)
        return;
    end
    local info=db:check_obj(obj,1)
    if type(info) ~='table' or not info then
        local rtn=unwrap.unwrap_schema(obj:upper(),ext)
        return env.checkerr(rtn,'No maching objects found in schema: '..obj);
    end
    if not info.object_type:find('^JAVA') then
        local qry=[[
            SELECT TEXT,
                   MAX(CASE WHEN LINE = 1 AND TEXT LIKE '% wrapped%' || CHR(10) || '%' THEN 1 ELSE 0 END) OVER(PARTITION BY TYPE) FLAG,
                   LINE,
                   MAX(line) OVER(PARTITION BY TYPE) max_line
            FROM  ALL_SOURCE a
            WHERE OWNER = :owner
            AND   NAME  = :name
            ORDER BY TYPE, LINE]]
        if db.props.version>=12 then
            qry=qry:gsub(':name',':name and origin_con_id=(select origin_con_id from all_source where rownum<2 and OWNER = :owner and NAME  = :name)')
        end
        local rs=db:dba_query(db.exec,qry,{owner=info.owner,name=info.object_name})
        local cache={}
        local result=""
        local txt=""
        local rows=db.resultset:rows(rs,-1)
        table.remove(rows,1)
        for index,piece in ipairs(rows) do
            cache[#cache+1]=piece[1]
            if piece[3]==piece[4] then
                txt,cache=table.concat(cache,''),{};
                if tonumber(piece[2])==1 then
                    local cnt,lines=txt:match('\r?\n[0-9a-f]+ ([0-9a-f]+)\r?\n(.*)')
                    env.checkerr(lines,'Cannot find matched text!')
                    txt=decode_base64_package(lines:gsub('[\n\r]+',''))
                end
                txt=txt:sub(1,-100)..(txt:sub(-99):gsub('%s*;[^;]*$',';'))
                result=result..'CREATE OR REPLACE '..txt..'\n/\n\n'
            end
        end
        db.resultset:close(rs)
        env.checkerr(result~="",'Cannot find targt object: '..obj)
        print("Result written to file "..env.write_cache(prefix..filename..'.'..(ext or 'sql'),result))
    else
        env.set.set('CONVERTRAW2HEX','on')
        local args={clz='#BLOB',owner=info.owner,name=info.object_name,object_type=info.object_type,suffix='#VARCHAR'}
        db:internal_call([[
            DECLARE
                v_blob   BLOB;
                v_len    INTEGER;
                v_buffer RAW(32767);
                v_chunk  BINARY_INTEGER := 32767;
                v_pos    INTEGER := 1;
                v_type   VARCHAR2(30) := :object_type;
                v_name   VARCHAR2(800):= REPLACE(:name, '/', '.');
            BEGIN
                dbms_lob.createtemporary(v_blob, TRUE);
                IF v_type='JAVA CLASS' THEN
                    dbms_java.export_class(v_name, :owner, v_blob);
                    v_type := 'class';
                ELSIF v_type='JAVA SOURCE' THEN
                    dbms_java.export_source(v_name, :owner, v_blob);
                    v_type := 'java';
                ELSE
                    dbms_java.export_resource(v_name, :owner, v_blob);
                    v_type := 'properties';
                END IF;
                v_len := DBMS_LOB.GETLENGTH(v_blob);
                WHILE v_pos <= v_len LOOP
                    IF v_pos + v_chunk - 1 > v_len THEN
                        v_chunk := v_len - v_pos + 1;
                    END IF;
                    DBMS_LOB.READ(v_blob, v_chunk, v_pos, v_buffer);
                    v_pos := v_pos + v_chunk;
                END LOOP;
                :suffix := v_type;
                :clz := v_blob;
            END;]],args)
        local path,class=info.object_name:match('^(.-)([^\\/]+)$')
        path=env.join_path(env._CACHE_PATH,path)
        loader:mkdir(path)
        print("Result written to file "..env.save_data(path..class..'.'..args.suffix,args.clz,nil,true))
    end
end

function unwrap.onload()
    env.set_command(nil,"unwrap",'Extract the source code of the specific wrapped object(sqlmon/procedure/package/function/trigger/type). Usage: @@NAME {[<owner>.]<object_name> [<file_ext>] [prefix]} | {<sql monitor filename>}',unwrap.unwrap,false,4)
end

return unwrap