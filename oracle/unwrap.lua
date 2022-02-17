--References:
--    http://blog.teusink.net/2010/04/unwrapping-oracle-plsql-with-unwrappy.html
--    http://blog.csdn.net/akinosun/article/details/8041199

--Uses a handler that converts the XML to a Lua table

local table,string=table,string
local env,db,ffi,zlib=env,env.getdb(),env.ffi,env.zlib
local tonumber,math=tonumber,math
local unwrap={}
local xml2lua = require("xml2lua")
local handler = require("xmlhandler.tree")
local object_pattern='%d%a#$_'
local object_full_pattern=object_pattern..'"%.'
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
    local list
    if obj:upper()=='ORACLE' then
        list=db:dba_query(db.get_rows,[[
            select distinct owner||'.'||object_name o 
            from   all_objects a,
                   all_users b 
            where  a.oracle_maintained='Y'
            and    b.oracle_maintained='Y'
            and    a.owner=b.username
            and    a.owner not like 'APEX_%'
            and    a.object_type in('TRIGGER','TYPE','PACKAGE','FUNCTION','PROCEDUR') 
            and    not regexp_like(object_name,'^(SYS_YOID|SYS_PLSQL_|KU$_WORKER)')
            ORDER BY 1]])
    else
        list=db:dba_query(db.get_rows,[[
            select distinct owner||'.'||object_name o 
            from   all_objects 
            where  owner=:1 
            and    object_type in('TRIGGER','TYPE','PACKAGE','FUNCTION','PROCEDUR') 
            and    not regexp_like(object_name,'^(SYS_YOID|SYS_PLSQL_|KU$_WORKER)')
            ORDER BY 1]],{obj:upper()})
    end
    if type(list) ~='table' or #list<2 then return false end
    for i=2,#list do
        local n=list[i][1]
        local done,err=pcall(unwrap.unwrap,n,ext)
        if not done then env.warn(err) end
    end
    return true
end

local thresholds={
    skew_rate=0.7,
    skew_min_diff=100,
    px_process_count=4,
    sqlstat_aas_min=10,
    sqlstat_min=1024*1024,
    buff_gets_min=1024*1024/16,
    sqlstat_warm={
        user_fetch_count=256,
        from_start={1,3},
        disk_reads=math.pow(1024,3)*256/8192,
        buffer_gets=math.pow(1024,4)/8192,
        time_per_buffer_get=300, --300us
        time_per_io_req=30*1e3 --30ms
    }
    --buff_get_rate=0.7 --the threshold of cpu_time/elapsed_time to calc avg buffer get time
}

local function pair(o)
    return ipairs(type(o)~='table' and {} or (type(o[1])=='table' or #o>1) and o or {o})
end

local function load_xml(parser,xml)
    local raw=table.new(8192,0)
    local idx=0
    for line in xml:gsplit('(\r?\n\r?)') do
        if line:sub(1,1):match('[%s<]') then
            idx=idx+1
            raw[idx]=line
        elseif raw[idx] and #raw[idx]<512 then
            idx=idx+1
            raw[idx]=line
        else
            raw[idx]=raw[idx]..line
        end
    end
    parser:parse(table.concat(raw,'\n'))
end


local function to_pct(a,b,c,quote)
    if b==0 then
        if c and c>0 then 
            b=c
        else
            return ''
        end
    elseif a>b and c then
        b=b+c
    end
    b=('%.1f%%'):format(100*a/b):gsub('%.0%%','%%')
    if b=='0%' then return '' end
    if quote~=false then
        return '('..b..')'
    else
        return ' '..b
    end
end

local function split_text(text)
    local width=console:getScreenWidth()-50
    local len,result,pos,pos1,c,p=#text,{},1
    local pt="[|),%] =]"
    while true do
        result[#result+1]=text:sub(pos,pos+width-1)
        pos=pos+width
        pos1=pos
        local ln=0
        while true do
            pos1=pos1+1
            c=p or text:sub(pos1,pos1)
            p=text:sub(pos1+1,pos1+1)
            if c=='' or (c:find(pt) and not p:find(pt)) then
                ln=ln+1
                result[#result+1]=text:sub(pos,pos1)..'\n'
                pos=pos1+1
                break
            end
        end
        if len<pos then break end
        if ln>32 then
            result[#result]='\n...... The Full SQL Text can be found in the text file ......'
            break
        end
    end
    return table.concat(result,'')
end

local function load_sql_text(sql_fulltext,pr,title,sql_id)
    local sql_text,brief_text=sql_fulltext
    if sql_text then
        title('$PROMPTCOLOR$SQL '..sql_id..'$NOR$')
        sql_text=(type(sql_text)=='table' and sql_text[1] or sql_text):trim()
        local is_cut
        if #sql_text>512 and not sql_text:sub(1,512):find('\n') then
            sql_text=split_text(sql_text)
        else
            sql_text=sql_text:split('\n')
            local ln=#sql_text
            if ln>32 then
                sql_text[33]='\n...... The Full SQL Text can be found in the text file ......'
            end
            sql_text=table.concat(sql_text,'\n',1,math.min(33,ln))
        end
        local text,data=grid.tostring({{sql_text}},false,'','')
        pr(text..'\n',sql_fulltext)
    end
end

local function get_top_events(events,as,rt,top)
    local lines,l,first={},{}
    for id,aas in pairs(events) do
        --aas: {rt,aas}
        local v=type(aas)=='table' and (aas[2]==0 and aas[1] or aas[2]) or aas
        lines[#lines+1]={id,v}
    end
    table.sort(lines,function(o1,o2) return o1[2]>o2[2] end)
    for i=1,math.min(top or 1,#lines) do
        if i==1 and (top or 1)==1 then
            local pct=to_pct(lines[i][2],as,rt):match('[%d%.]+')
            if pct then pct=tonumber(pct)/100 end
            return lines[i][1],pct
        end
        l[i]=lines[i][1]..' '..to_pct(lines[i][2],as,rt)
    end
    return table.concat(l,', '),first
end

local function scan_events(activities,row,aas_idx)
    if not row.events then row.events={} end
    for k,v in pair(type(activities)=='table' and activities.activity or nil) do
        local event=v._attr.event or v._attr.class
        if event=='Cpu' then event='ON CPU' end
        row.events[event]=(row.events[event] or 0)+tonumber(v[1])
        if aas_idx then row[aas_idx]=(row[aas_idx] or 0)+tonumber(v[1]) end
    end
end

local function strip_quote(str)
    if type(str)~='string' then return str end
    return str:gsub('"([%u%d_$#]+)"','%1')
end

local cp='"(['..object_pattern..']+)"'
local function process_pred(preds,id,type,pred,node,alias)
    if not pred then return end
    pred=pred:gsub('%s*\n%s*',' '):trim()
    if pred=='' then return end
    if type:lower()~='proj' then
        local pred1=strip_quote(pred)
        if #pred1>256 then pred1=split_text(pred1):trim() end
        preds[#preds+1]={tonumber(id),type:initcap(),pred1}
        preds.ids[id]=preds.ids[id] or {}
        if node then
            if not node.pred then node.pred={'',''} end
            local df='__DEFAULT__'
            local sets={[df]={0}}
            pred=(' '..pred..' '):gsub('([^'..object_full_pattern..'])','%1%1')
            if alias then 
                alias='"'..alias:gsub('@.*',''):gsub('"',''):escape()..'"'
                pred=pred:gsub('([^%."])'..alias..'."','%1"')
            end
            pred=pred:gsub('([^%."])("['..object_full_pattern..']+")([^%."])',function(p,c,s)
                local t,o=c:match('^'..cp..'%.'..cp..'$')
                if not t then
                    o=c:match('^'..cp..'$')
                    if o then t=df end
                end
                if t then
                    if not sets[t] then sets[t]={0} end
                    if not sets[t][o] then
                        sets[t][1],sets[t][o]=sets[t][1]+1,1
                    end
                end
                return p..c..s
            end)
            local c=0

            if alias and sets[df][1]>0 then 
                c=sets[df][1]
            else
                c=0
                for k,v in pairs(sets) do
                    c=c<v[1] and v[1] or c
                end
            end
            if c>0 then
                if type:lower()=='filter' then
                    node.pred[2]='F'..c
                elseif type:lower()=='access' then
                    node.pred[1]='A'..c
                else
                    node.pred[1]='A'..c
                end
            end
        end
    elseif node then
        local keys,c=pred:match('#keys=([1-9]%d+)')
        if keys then node.proj[1]='K'..keys..',' end
        keys=pred:match('rowset=([1-9]%d+)')
        if keys then
            node.proj[2]='R'..keys..',' 
        end
        c,keys=(pred..', '):gsub('], ','')
        if keys>0 then node.proj[3]='C'..keys..',' end
    end
end

local function qb_name(qb) return '@"'..qb:gsub('["@]+','')..'"' end
local function add_hint(envs,outlines,text,hint1)
    if not text then text,hint1=hint1,text end
    if text:upper():find('^OPT_PARAM') then
        local sub=text:sub(10)
        local name=sub:match('(['..object_pattern.."]+)")
        text='OPT_PARAM'..sub
        if envs[name] then return end
        envs[name]=text
    end
    outlines[#outlines+1]={text:find('@') and '' or "Env",text,hint1}
end

local function process_qb(qbs,qb,alias,id,depth)
    id=tonumber(id)
    if not qbs.__qbs then qbs.__qbs={} end
    if (alias or '')~='' then qbs['"'..alias:gsub('"',''):gsub('@','"@"')..'"']=id end
    if qb and qb~='' then
        qb=qb_name(qb)
        local range=qbs[qb] or {min=id,qb=qb}
        range.max=id
        qbs[qb]=range
        qbs.__qbs[depth]=range
        for i=#qbs.__qbs,depth+1,-1 do
            qbs.__qbs[i]=nil
        end
    else
        for i=depth-1,0,-1 do
            if qbs.__qbs[i] then
                qb=qbs.__qbs[i].qb
                qbs.__qbs[i].max=id
                break
            end
        end
    end
end

function unwrap.parse_qb_registry(reg,qbs,src)
    if type(reg)=='string' then
        local content=handler:new()
        local parser =xml2lua.parser(content)
        parser:parse(reg)
        reg=content.root.qb_registry
    end
    if type(reg)~='table' then return end
    local origins={
        [0]='NOT NAMED',
        [1]='ALLOCATE',
        [2]='',
        [3]='HINT',
        [4]='COPY',
        [5]='SAVE',
        [6]='REWRITE',
        [7]='PUSH_PRED',
        [8]='STAR TRANSFORM SUBQUERY',
        [9]='COMPLEX VIEW MERGE',
        [10]='COMPLEX SUBQUERY UNNEST',
        [11]='USE_CONCAT',
        [12]='SUBQ INTO VIEW FOR COMPLEX UNNEST',
        [13]='PROJECTION VIEW FOR CVM',
        [14]='GROUPING SET TO UNION',
        [15]='SPLIT/MERGE QUERY BLOCKS',
        [16]='COPY PARTITION VIEW',
        [17]='RESTORE',
        [18]='MERGE',
        [19]='UNNEST',
        [20]='STAR_TRANSFORMATION',
        [21]='INDEX JOIN',
        [22]='STAR TRANSFORM TEMP TABLE',
        [23]='MAP QUERY BLOCK',
        [24]='VIEW ADDED',
        [25]='SET QUERY BLOCK',
        [26]='QUERY BLOCK TABLES CHANGED',
        [27]='QUERY BLOCK SIGNATURE CHANGED',
        [28]='MV UNION QUERY BLOCK',
        [29]='EXPAND_GSET_TO_UNION',
        [30]='PULL_PRED',
        [31]='PREDICATES ADDED TO QUERY BLOCK',
        [32]='OLD_PUSH_PRED',
        [33]='ELIMINATE_OBY',
        [34]='ELIMINATE_JOIN',
        [35]='OUTER_JOIN_TO_INNER',
        [36]='STAR ELIMINATE_JOIN',
        [37]='BITMAP ELIMINATE_JOIN',
        [38]='CONNECT_BY_COST_BASED',
        [39]='CONNECT_BY_FILTERING',
        [40]='NO_CONNECT_BY_FILTERING',
        [41]='CONNECT BY START WITH QUERY BLOCK',
        [42]='CONNECT BY FULL SCAN QUERY BLOCK',
        [43]='PLACE_GROUP_BY',
        [44]='NO_CONNECT_BY_FILTERING COMBINE',
        [45]='VIEW ON SELECT DISTINCT',
        [46]='COALESCE_SQ',
        [47]='QUERY HAS COALESCE_SQ',
        [48]='TRANSFORM_DISTINCT_AGG',
        [49]='CONNECT_BY_ELIM_DUPS',
        [50]='CONNECT_BY_CB_WHR_ONLY',
        [51]='EXPAND_TABLE',
        [52]='TABLE EXPANSION BRANCH',
        [53]='FACTORIZE_JOIN',
        [54]='PLACE_DISTINCT',
        [55]='JOIN FACTORIZATION BRANCH QUERY BLOCK',
        [56]='TABLE_LOOKUP_BY_NL',
        [57]='FULL_OUTER_JOIN_TO_OUTER',
        [58]='OUTER_JOIN_TO_ANTI',
        [59]='VIEW DECORRELATE',
        [60]='QUERY DECORRELATE',
        [61]='NOT EXISTS SQ ADDED',
        [62]='BRANCH WITH OUTER JOIN',
        [63]='BRANCH WITH ANTI JOIN',
        [64]='UNION ALL FOR FULL OUTER JOIN',
        [65]='VECTOR_TRANSFORM',
        [66]='VECTOR TRANSFORMATION TEMP TABLE',
        [67]='QUERY ANSI_REARCH',
        [68]='VIEW ANSI_REARCH',
        [69]='ELIM_GROUPBY',
        [70]='UAL BRANCH OF UNNESTED SUBQUERY',
        [71]='BUSHY_JOIN',
        [72]='ELIMINATE_SQ',
        [73]='OR EXPANSION UNION ALL BRANCH',
        [74]='OR_EXPAND',
        [75]='USE_DAGG_UNION_ALL_GSETS',
        [76]='MATERIALIZED WITH CLAUSE',
        [77]='STATISTCS BASED TRANSFORMED QB',
        [78]='PQ TABLE EXPANSION',
        [79]='LEFT OUTER JOIN TRANSFORMED TO BOTH INNER AND ANTI',
        [80]='SHARD TEMP TABLE',
        [81]='BRANCH OF COMPLEX UNNESTED SET QUERY BLOCK',
        [82]='DAGG_OPTIM_GSETS'}
    local function push(qb,parent,final)
        local q=qbs[qb] or {childs={},parents={},objs={},qb=qb}
        local pos=qb:find('@',1,true)
        if parent then
            if final=='y' then
                table.insert(q.parents,1,parent)
            else
                q.parents[#q.parents+1]=parent
            end
            if pos and pos>1 then
                parent.objs[q.qb]=q
            else
                parent.childs[#parent.childs+1]=q
            end
        end
        qbs[qb]=q
        return q
    end

    local alias='"%s"@"%s"'
    for k,q in pair(reg.q) do
        if type(q.n)=='string' then
            local qb=push(qb_name(q.n))
            local attr=q._attr or {}
            if attr.o then
                qb.o=origins[tonumber(attr.o)] or attr.o
            end

            if q.p then push(qb_name(q.p),qb,attr.f) end
            for _,o in pair(q.i and q.i.o) do
                local n=o.v:gsub('"','')
                local pos=n:find('@',1,true)
                local p
                if pos and pos>1 then
                    p=qb_name(n:sub(pos+1))
                    p=qbs[p] or push(p,qb,attr.f)
                    n='"'..n:gsub('@','"@"')..'"'
                else
                    n=qb_name(n)
                end
                local obj=push(n,qb,attr.f)
                if p then p.objs[obj.qb]=obj end
            end

            for _,o in pair(q.f and q.f.h) do
                local obj=push(alias:format(o.t,o.s),qb,attr.f)
                local p=qb_name(o.s)
                p=qbs[p] or push(p,qb,attr.f)
                p.objs[obj.qb]=obj
            end
        end
    end
    return type(src)=='table' and unwrap.print_qb_registry(qbs,src) or qbs
end

function unwrap.print_qb_registry(qb_transforms,qbs)
    local tops={}
    for qb,v in pairs(qb_transforms) do
        local o=qbs[qb]
        if o then
            if type(o)=='number' then
                v.line=o
            else
                v.min,v.max=o.min,o.max
            end
        end
        if #v.parents==0 and (#v.childs>0 or (v.o or '')~='') then
            tops[#tops+1]={v,v.line or v.min or 0}
        end
    end
    if #tops==0 then return {} end
    table.sort(tops,function(a,b) return a[2]<b[2] end)
    local rows={{"Hierachy (Final <- Init)","Objects"}}
    local function to_list(list,func)
        local items={}
        for _,qb in (func or pairs)(list) do
            items[#items+1]=qb.qb:gsub('"',""):ltrim('@')
        end
        return table.concat(items,'; ')
    end
    local function walk(qb,indent,siblings)
        local comment=qb.o or ''
        rows[#rows+1]={indent..qb.qb:gsub('"',""):sub(2)..(comment~='' and (' ('..comment..')') or ''),to_list(qb.objs)}
        local l=#qb.childs
        for i,c in ipairs(qb.childs) do
            walk(c,indent..(siblings and '|' or ' ')..' ',i<l)
        end
    end
    for _,qb in ipairs(tops) do
        walk(qb[1],'')
    end
    --print(table.dump(qb_transforms))
    return rows
end

local function parse_other_xml(xml,add_header,envs,outlines,qb_transforms,skp)
    if type(xml)~='table' then return end
    for k,v in pair(xml.info) do
        local typ=v._attr and v._attr.type or nil
        if typ and typ~='nodeid/pflags' and typ~='px_ext_opns' and typ~='db_version' then
            add_header(typ,v[1],v._attr.note)
        end
    end

    for _,op in pair(xml.display_map and xml.display_map.row) do
        local attr=op._attr
        skp[tonumber(attr.op)]=tonumber(attr.skp)
    end

    if xml.stats then
        local t=xml.stats._attr.type
        for k,v in pair(xml.stats.stat) do
            if t and v._attr.name then
                add_header(t..'.'..v._attr.name,v[1],10)
            end
        end
    end

    unwrap.parse_qb_registry(xml.qb_registry,qb_transforms)

    if xml.outline_data then
        for k,v in pair(xml.outline_data.hint) do
            if v~='IGNORE_OPTIM_EMBEDDED_HINTS' then
                add_hint(envs,outlines,v)
            end
        end
    end

    if xml.hint_usage then
        for k,v in pairs(xml.hint_usage) do
            if k=='q' then
                for idx,v1 in pair(v) do
                    local qb_='@"'..v1.n..'"'
                    local t=v1.h or v1.t and v1.t.h or nil
                    if t and t.x and not t.x:upper():find('^OPT_PARAM') then
                        local hint,alias_,hint1=t.x
                        local pos=hint:find('(',1,true)
                        if hint:find('@"',1,true) then pos=nil end
                        if t.r then hint=hint..' / '..t.r end
                        local alias_= v1.t and v1.t.f or nil
                        if pos then 
                            hint1=hint:sub(1,pos)..(alias_ or qb_)..' '..hint:sub(pos+1)
                        else
                            hint1=hint..'('..(alias_ or qb_)..')'
                        end
                        add_hint(envs,outlines,hint1,hint..' (SQL Hint)')
                    end
                end
            elseif k=='s' and v.h then
                for idx,h1 in pair(v.h) do
                    local hint=h1.x
                    if h1.r then hint=hint..' / '..h1.r end
                    add_hint(envs,outlines,hint..' (SQL Hint)')
                end
            end
        end
    end
end

local function load_binds(binds)
    if not binds[1] and not binds[2] then
        return nil
    end
    local dtypes={
          [1] = 'VARCHAR2',
          [2] = function(attr)  
                    return attr.scal=="-127" and 'FLOAT' or 
                           attr.pre=='38' and (attr.scal or '0')=='0' and 'INTEGER' or 
                           ('NUMBER('.. (attr.pre or '38')..','..(attr.scal or '*')..')')
                end,
          [3] = 'NATIVE INTEGER',
          [8] = 'LONG',
          [9] = 'VARCHAR',
         [11] = 'ROWID',
         [12] = 'DATE',
         [23] = 'RAW',
         [24] = 'LONG RAW',
         [29] = 'BINARY_INTEGER',
         [69] = 'ROWID',
         [96] = 'CHAR',
        [100] = 'BINARY_FLOAT',
        [101] = 'BINARY_DOUBLE',
        [102] = 'REF CURSOR',
        [104] = 'UROWID',
        [105] = 'MLSLABEL',
        [106] = 'MLSLABEL',
        [110] = 'REF',
        [111] = 'REF',
        [112] = 'CLOB',
        [113] = 'BLOB', 
        [114] = 'BFILE', 
        [115] = 'CFILE',
        [121] = 'OBJECT',
        [122] = 'TABLE',
        [123] = 'VARRAY',
        [178] = 'TIME',
        [179] = 'TIME WITH TIME ZONE',
        [180] = 'TIMESTAMP',
        [181] = 'TIMESTAMP WITH TIME ZONE',
        [231] = 'TIMESTAMP WITH LOCAL TIME ZONE',
        [182] = 'INTERVAL YEAR TO MONTH',
        [183] = 'INTERVAL DAY TO SECOND',
        [250] = 'PL/SQL RECORD',
        [251] = 'PL/SQL TABLE',
        [252] = 'PL/SQL BOOLEAN'}
    local rows={_names={}}
    local positions={}
    for i=1,2 do
        for j,b in pair(binds[i] and binds[i].bind or nil) do
            local att=b._attr
            local nam=att.nam or att.name
            local maxlen=tonumber(att.maxlen or att.mxl)
            local row=rows._names[nam] or {nam,nil,maxlen}
            if not positions[nam] then positions[nam]={c=0} end
            if att.pos and not positions[nam][att.pos] then
                positions[nam][att.pos],positions[nam].c=1,1+positions[nam].c
            end
            if not row[2] or att.dtystr then
                row[2]=att.dtystr
                if att.format=="hexdump" or not row[2] then
                    local dty=att.dty
                    dty=dtypes[tonumber(dty)] or dty
                    if type(dty)=='function' then
                        dty=dty(att)
                    elseif dty=='VARCHAR2' or dty=='VARCHAR' or dty=='CHAR' or dty=='RAW' then
                        dty=dty..'('..(att.len or att.maxlen or att.mxl)..')'
                    end
                    if b[1] and (att.dty=='1' or att.dty=='9' or att.dty=='96') then
                        att.dtystr=dty
                        att.format=nil
                        b[1]=b[1]:fromhex()
                    elseif b[1] and (att.dty=='2' or att.dty=='3' or att.dty=='29') then
                        att.dtystr=dty
                        att.format=nil
                        local sets,idx,sign,p,s={'0.'},0
                        b[1]:gsub('..',function(s1)
                            idx=idx+1
                            s=tonumber(s1,16)
                            if idx>=2 then
                                if sign>0 then
                                    sets[idx]=s-1
                                else
                                    sets[idx]=102-s-1
                                end
                            else
                                if s>=128 then
                                    sign,p=1.0,s-128-64
                                else
                                    sign,p=-1.0,127-s-64
                                end
                            end
                            return s1
                        end)
                        if sign==-1 then sets[#sets]=nil end
                        b[1]=tostring(math.round(sign*math.pow(100,p)*tonumber(table.concat(sets)),4))
                    elseif b[1] and (att.dty=='12' or att.dty=='179' or att.dty=='180' or att.dty=='181' or att.dty=='231') then
                        local sets,idx,s={},0
                        b[1]:gsub('..',function(s1)
                            s,sep=tonumber(s1,16)
                            idx=idx+1
                            if idx<=2 then
                                s,sep=s-100,'/'
                            elseif idx>=5 then
                                s,sep=s-1,':'
                            end
                            sep=idx==1 and '' or idx==2 and '/' or idx==3 and '/' or idx==4 and ' ' or idx==7 and '' or ':'
                            sets[idx*2-1],sets[idx*2]=tostring(s),sep
                            return s1
                        end,7)
                        
                        while b[1]:find('00$') do b[1]=b[1]:sub(1,-3) end
                        if #b[1]>14 then
                            sets[#sets]='.'
                            sets[#sets+1]=(''..tonumber(b[1]:sub(15,22),16)):gsub('^(..-)0+$','%1')
                        end
                        if #b[1]>22 then
                            sets[#sets+1]=' '
                            sets[#sets+1]=tostring(tonumber(b[1]:sub(22,23),16)-20)
                        end
                        if #b[1]>23 then
                            sets[#sets+1]=':'
                            sets[#sets+1]=tostring(tonumber(b[1]:sub(24,25),16)-60)
                        end
                        b[1]=table.concat(sets,''):gsub('(%d+)/(%d+)/(%d+)',function(y,m,d) return m..'/'..d..'/'..y end)
                        att.dtystr=dty
                        att.format=nil
                    end
                    row[2]=dty
                end
            end
            row[4]=math.min(tonumber(att.pos) or 9999,row[4] or 9999)
            row[5]=positions[nam].c
            if b[1] then
                row[5+i]=(att.dtystr and att.format~='hexdump' and '' or '(0x)')..b[1]
            else
                row[5+i]='<Unknown>'
            end
            if not rows._names[nam] then
                rows._names[nam]=row
                rows[#rows+1]=row
            end
        end
    end
    table.sort(rows,function(a,b) return a[4]<b[4] end)
    table.insert(rows,1,{'Name','Data Type','Max Len','Position','Occurrence','Peeked Bind','Cursor Bind'})
    rows.topic,rows.colsep='Peeked/Cursor Binds','|'
    return rows
end

local function print_suffix(preds,qbs,qb_transforms,outlines,pr,xid)
    local function title(msg)
        pr('\n'..msg..':')
        pr(string.rep('=',#msg:strip_ansi()+1))
    end

    if #preds>0 then
        env.var.define_column('id','break')
        table.sort(preds,function(a,b) 
            if a[1]~=b[1] then return a[1]<b[1] end
            if a[2]~=b[2] then return a[2]<b[2] end
            return a[3]:gsub('^.-%-> *','')<b[3]:gsub('^.-%-> *','')
        end)
        table.insert(preds,1,{'Id','Type','Content'})
        title('Predicates/Line Stats')
        pr(grid.tostring(preds))
        env.var.define_column('id','clear')
    end
    
    local qb_hiers=unwrap.print_qb_registry(qb_transforms,qbs)
    if #outlines>0 then
        title('Optimizer Environments & Outlines')
        table.sort(outlines,function(a,b)
            for _,c in ipairs{a,b} do
                if c[1]=='' and c[2]:find('"') then
                    local hint=(' '..c[2]..' '):gsub('([^'..object_pattern..'"@%.])','%1%1')
                    local list={}
                    local objs=0
                    hint:gsub('([^%."@])(@?"['..object_pattern..'"@%.]+")([^%."@])',function(p,c,s)
                        local pos=c:find('@',1,true)
                        if not pos then return p..c..s end
                        local n=pos>1 and ('"'..c:gsub('"',''):gsub('@','"@"')..'"') or qb_name(c)
                        local qb=qbs[n] 
                        if not qb then
                            qb=qb_transforms[n]
                            if qb and qb.parents[1] and qb.parents[1].min then 
                                qb=qb.parents[1]
                            end
                        end
                        if pos>1 then objs=objs+1 end
                        if type(qb)=='table' then
                            if qb.line then
                                if not list[1] then list[1]={} end
                                list[1][#list[1]+1]=qb.line
                            else
                                list[2]=qb
                            end
                        elseif qb then
                            if not list[1] then list[1]={} end
                            list[1][#list[1]+1]=qb
                        else
                            list.missing=true
                        end
                        return p..c..s
                    end)
                    if list[1] and objs==1 then 
                        c[1]=xid:format(list[1][1])
                    elseif list[2] and list[2].min then
                        if not list[1] or list[2].min==list[2].max then
                            c[1]=xid:format(list[2].min)
                        else
                            c[1]=xid:format(list[2].min)..' - '..xid:format(list[2].max)
                        end
                    elseif list[1] and #list[1]>1 then
                        table.sort(list[1])
                        c[1]=xid:format(list[1][1])..' - '..xid:format(list[1][#list[1]])
                        --TODO
                    end
                    c[2]=c[3] or strip_quote(c[2])
                end
            end
            if a[1]~=b[1] then
                if a[1]=='Env' then 
                    return true;
                elseif b[1]=='Env' then
                    return false
                else
                    local l1,l2=tonumber(a[1]:match('%d+')) or 9999,tonumber(b[1]:match('%d+')) or 9999
                    if l1~=l2 then return l1<l2 end
                    return a[1]<b[1]
                end
            else
                return a[2]<b[2]
            end
        end)

        table.insert(outlines,1,{'Scope','Content'})
        pr(grid.tostring(outlines))
    end

    if #qb_hiers>0 then
        title('Query Block Hierachies')
        pr(grid.tostring(qb_hiers))
    end
end

local colors={'$COMMANDCOLOR$','$PROMPTCOLOR$','$HIB$','$PROMPTSUBCOLOR$'}
local sqlmon_pattern='<report [^%>]+>%s*<report_id><?[^<]*</report_id>%s*<sql_monitor_report .-</sql_monitor_report>%s*</report>'
function unwrap.analyze_sqlmon(text,file,seq)
    local content=handler:new()
    local parser =xml2lua.parser(content)
    local xml,hd,db_version,start_clock
    local xml=text:match(sqlmon_pattern)
    if not xml then
        xml=text:match('<sql_monitor_report .-</sql_monitor_report>')
        if not xml then return end
    end

    --handle line-split of SQL fulltext
    load_xml(parser,xml)
    if content.root.report then
        content=content.root.report
        hd=content.sql_monitor_report
        db_version=content._attr.db_version
    else
        hd=content.root.sql_monitor_report
        content=nil
    end
    if not db_version then
        db_version=xml:match('db_version="([^"]+)"') or '12.2'
    end
    local number_fmt=env.var.format_function('auto2','desc')
    local instance_id,session_id=tonumber(hd.target._attr.instance_id),tonumber(hd.target._attr.session_id)
    local error_msg=hd.error and hd.error[1]:trim():match('[^\n]+') or nil
    local default_dop,px_alloc,sql_id,status,plsql,interval,phv=0,0
    
    --from x$qksxa_reason
    local reasons={
        ['352']="DOP downgrade due to adaptive DOP",
        ['353']="DOP downgrade due to resource manager max DOP",
        ['354']="DOP downgrade due to insufficient number of processes",
        ['355']="DOP downgrade because slaves failed to join"
    }
    local dist_methods={
        ["5"]="ROUND-ROBIN",
        ["6"]="BROADCAST",
        ["16"]="HASH"
    }
    local kv_types={
        ['1']='[NUMBER]',
        ['2']='[BINARY_FLOAT]',
        ['3']='[BINARY]',
        ['4']='[PACKED_BINARY]',
        ['5']='[PACKED_NUMBER]', 
        ['6']='[PACKED_DATE]', 
        ['8']='[BINARY_DOUBLE]',
        ['9']='[PACKED_HOUR]', 
        ['10']='[PACKED_MINUTE]', 
        ['11']='[PACKED_SECOND]'
    }
    env.var.define_column('max_io_reqs,IM|DS,Est|Cost,Est|I/O,Est|Rows,Act|Rows,Skew|Rows,Read|Reqs,Write|Reqs,Start|Count,Buff|Gets,Disk|Read,Direx|Write,Fetch|Count','for','tmb1')
    env.var.define_column('max_aas,max_cpu,max_waits,max_other_sql_count,max_imq_count,1st|Row,From|Start,From|End,Active|Clock,Ref|AAS,ASH|AAS,CPU|AAS,Wait|AAS,IMQ|AAS,Other|SQL,resp,aas,clock','for','smhd2')
    env.var.define_column('duration,bucket_duration,Wall|Time,Elap|Time,Avg|Buff,Avg|I/O','for','usmhd2')
    env.var.define_column('max_io_bytes,max_buffer_gets,I/O|Bytes,Mem|Bytes,Max|Mem,Temp|Bytes,Max|Temp,Inter|Connc,Avg|Read,Avg|Write,Unzip|Bytes,Elig|Bytes,Return|Bytes,Saved|Bytes,Flash|Cache,Slow|Meta,Read|Bytes,Write|Bytes,Avg|Read,Avg|Write','for','kmg1')
    env.var.define_column('pct','for','pct')
    env.var.define_column('Id<0%,cpu%,wait%,sql%,imq%,aas%,aas %|event','for','pct0')
    env.set.set('autohide','col')
    text,file={},file:gsub('%.[^\\/%.]+$','')..(seq and ('_'..seq) or '')
    
    local plan,stats
    local attrs,infos={top_event={},dist_methods={},lines={}},{}
    local plsqls,stacks={},{}
    local events={}
    if db_version<'12.2' then
        for i=352,355 do
            reasons[tostring(i-2)]=reasons[tostring(i)]
        end
    end

    local function time2num(d)
        if not d then return end
        local m,d,y,h,mi,s=d:match('(%d+)/(%d+)/%d%d(%d+) (%d+):(%d+):(%d+)')
        if not d then return end
        return (y*365+m*30+d)*86400+h*3600+mi*60+s
    end

    local print_grid=env.printer.print_grid
    local function pr(msg,shadow)
        --store rowset instead of screen output to avoid line chopping
        if type(shadow)=='table' then
            shadow=grid.format_output(shadow)
        end

        text[#text+1]=type(shadow)=='string' and shadow or msg
        if not seq then
            if type(shadow)=='string' then
                print_grid(msg)
            else
                print(msg)
            end
        end
    end

    local function title(msg)
        pr('\n'..msg..':')
        pr(string.rep('=',#msg:strip_ansi()+1))
    end

    --build PX process name <sid>@<inst_id>
    local function insid(sid,inst_id)
        sid=(sid or session_id)..'@'..(tonumber(inst_id) or instance_id)
        return sid
    end
    sql_id=hd.report_parameters.sql_id or hd.target._attr.sql_id
    load_sql_text(hd.target.sql_fulltext,pr,title,sql_id)

    local iostat,buffer_bytes
    local function load_iostats()
        stats=hd.stattype
        local map={}
        local title={_seqs={}}
        if stats then
            for k,v in pair(stats.stat_info.stat) do
                local att=v._attr
                map[att.id]={name=att.name,factor=tonumber(att.factor),unit=att.unit}
                title._seqs[att.name],title[tonumber(att.id)]=tonumber(att.id),att.name
            end
            interval=tonumber(stats.buckets._attr.bucket_interval) or interval
            stats=stats.buckets.bucket
        elseif hd.metrics then
            interval=tonumber(hd.metrics._attr.bucket_interval) or interval
            stats=hd.metrics.bucket
        end
        if not stats then return end
        local rows={}  --name,avg,mid,min,max,total,buckets
        local avgs={{'reads','read_kb','Avg Read Bytes'},{'writes','write_kb','Avg Write Bytes'},{'reads','read_kb','Avg Read Bytes'},{'reads','interc_kb','Avg Interconnect Bytes'}}
        local function set_stats(bucket,name,value)
            if value>0 then
                local r=title._seqs[name]
                if not r then
                    r=#title+1
                    title._seqs[name],title[r]=r,name
                end
                if not rows[r] then rows[r]={name,values={}} end
                rows[r].values[bucket]=value
            end
        end
        for k,b in pair(stats) do
            local bucket=tonumber(b._attr.bucket_id or b._attr.number)
            for j,s in pair(b.stat or b.val or nil) do
                local att=s._attr
                local name=att.l or map[att.id].name
                local value=tonumber(att.value or s[1])*(name:find('_kb$') and 1024 or 1)
                set_stats(bucket,name,value)
            end
            local io_reqs
            for i,v in ipairs(avgs) do
                local r,r1=title._seqs[v[1]],title._seqs[v[2]]
                if r and r1 and rows[r] and rows[r1] then
                    local v1,v2=rows[r].values[bucket],rows[r1].values[bucket]
                    if v[2]~='interc_kb' then
                        if v1 then io_reqs=(io_reqs or 0)+v1 end
                    else
                        v1=io_reqs
                    end
                    if v1 and v2 then
                        set_stats(bucket,v[3],math.round(v2/v1,2))
                    end
                end
            end
        end
        local min,max,avg,mid,sum,count
        local no_sums={
            pga_kb=1,
            tmp_kb=1,
            ['Avg Read Bytes']=1,
            ['Avg Interconnect Bytes']=1,
            ['Avg Write Bytes']=1
        }
        map={
            nb_cpu='CPU Used Secs',
            nb_sess='PX Sessions',
            pga_kb='PGA Bytes',
            tmp_kb='Temp Bytes',
            reads='Read Reqs',
            read_kb='Read Bytes',
            writes='Write Reqs',
            write_kb='Write Bytes',
            interc_kb='Interconnect Bytes',
            cache_kb='Logical Bytes'
        }
        local result={{"Name","Median","Avg","Min","Max","Sum","Buckets"}}

        for i=#title,1,-1 do
            local s=rows[i]
            if s then
                avg,sum,count=table.avgsum(s.values)
                max,min=table.maxmin(s.values)
                mid=table.median(s.values)
                if no_sums[s[1]] then 
                    sum=nil 
                else
                    sum=sum*interval
                end
                if s[1]=='cache_kb' then buffer_bytes=sum end
                result[#result+1]={map[s[1]] or s[1],mid,avg,min,max,sum,count}
            end
        end
        if #result>1 then
            env.var.define_column('Median,avg,min,max,sum','for','auto2','name') 
            iostat=result
            iostat.topic="I/O Metrics"
        end
    end
    load_iostats()

    local headers,titles,dur1,dur2={},{[0]={}}
    local default_titles={
        servers_allocated='px_alloc',
        servers_requested='px_reqs',
        plsql_entry_object_id='plsql_entry_obj#',
        plsql_entry_subprogram_id='plsql_entry_sub#',
        plsql_object_id='plsql_obj#',
        plsql_subprogram_id='plsql_sub#',
        bucket_count='buckets',
        instance_id='inst_id',
        session_id='sid',
        session_serial='serial#',
        refresh_count='refreshes',
        dynamic_sampling='dyn_sample',
        optimizer_use_stats_on_conventional_dml='use_stats_conv_dml',
        gather_stats_on_conventional_dml='ga_stats_conv_dml',
        cbqt_star_transformation='cbqt_star_trans',
        max_activity_count='max_aas',
        max_cpu_count='max_cpu',
        max_wait_count='max_waits',
        max_other_sql_count='max_other_sql',
        max_buffer_gets='max_buffs',
        max_elapsed_time='max_elap',
        px_in_memory='px_imq',
        px_in_memory_imc='px_imc',
        derived_cpu_dop='auto_cpu_dop',
        derived_io_dop='auto_io_dop',
        cardinality_feedback='card_feedback'
    }
    local time_fmt='%d+/%d+/%d+'
    local function add_header(k,v,display)
        if not v or v:trim()=='' or titles[0][k] then return end
        titles[0][k]=v
        if k=='sql_id' then
            if not sql_id then sql_id=v end
            return
        elseif k=='duration' then
            v=tonumber(v)*1e6
            if not dur2 then dur2=v end
        elseif k=='bucket_duration' then
            v=tonumber(v)*1e6
            if not dur1 then dur1=v end
        elseif k=='sql_exec_start' then
            start_clock=time2num(v)
        elseif (k=='plsql_entry_name' or k=='plsql_name') and v~='Unavailable' then
            plsql=v:gsub('"','')
            return
        elseif k=='status' then
            if v:lower():find('error') then
                v=v:to_ansi('$HIR$','$NOR$')
                status='error'
            elseif v:lower():find('executing') then
                v=v:to_ansi('$PROMPTCOLOR$','$NOR$')
                status='running'
            else
                status='done'
            end
        elseif k=='servers_allocated' then
            px_alloc=tonumber(v)
        elseif k=='bucket_interval' then
            interval=tonumber(v)
        elseif k=='dop' then
            default_dop=tonumber(v)
        elseif k=='plan_hash_value' or k=='sql_plan_hash' then
            phv=tonumber(v)
        elseif type(v)=="string" then
            v=v:gsub('[^%g%s]+','')
            if #v>=30 then v=v:sub(1,25):rtrim('.')..'..' end
        end
        k=default_titles[k] or k
        titles[#titles+1]={k,v,tostring(v):find(time_fmt) and 91 or
                               k:find('^report_') and 999 or
                               k=='duration' and -10 or
                               k=='bucket_duration' and -9 or
                               k:find('^bucket') and -8 or
                               k:find('_time$') and tonumber(v) and -2 or
                               (k=='parse_schema' or k=='user') and -1 or
                               k:find('^plan') and 1 or 
                               k:find('^sql') and 2 or
                               (k:find('cpu') or k=='hyperthread') and 3 or
                               k:find('^dop') and 4 or
                               k:find('^px') and 5 or
                               k:find('^servers') and 6 or
                               tonumber(display) or
                               display and 90 or
                               tonumber(v)==0 and 99 or
                               v=='no' and 99 or
                               98}
    end

    local function print_header(topic,is_print)
        if #titles==0 then return end
        table.sort(titles,function(a,b)
            if a[3]~=b[3] then
                return a[3]<b[3]
            elseif a[2]~=b[2] and tostring(a[2]):find(time_fmt) and tostring(b[2]):find(time_fmt) then
                return a[2]<b[2]
            end
            return a[1]<b[1]
        end)

        headers={{},{}}
        for k,v in ipairs(titles) do
            headers[1][k],headers[2][k]=v[1],tonumber(v[2]) or strip_quote(v[2])
        end
        titles={[0]={}}

        if is_print~=false then
            if topic then title(topic) end
            pr(grid.tostring(headers,true,'|'))
        else
            headers.topic=topic
            return headers
        end
    end

    local report_header
    local function load_header()
        if content then
            for k,v in pairs(content._attr or {}) do
                local v1=tonumber(v)
                if k:find('_time$') and v1 then
                    k='report_'..k
                end
                if type(v)=='string' then add_header(k,v) end
            end
        end
        local sample=hd.activity_sampled
        if type(sample)=='table' and sample[1] then sample=sample[1] end

        for _,attr in ipairs{hd._attr or {},
                             hd.report_parameters or {},
                             (hd.activity_detail or sample or {})._attr or {},
                             hd.target._attr or {},
                             hd.target or {},
                             hd.parallel_info and hd.parallel_info._attr or {}} do
            for k,v in pairs(attr) do
                if type(v)=='string' and k~='sql_fulltext' then
                    add_header(k,v) 
                elseif k=='rminfo' then
                    add_header(k,v._attr.rmcg) 
                end
            end
        end

        if default_dop==0 then
            for _,o in pair(hd.target and hd.target.optimizer_env and hd.target.optimizer_env.param) do
                if o._attr and o._attr.name=='parallel_degree' then
                    add_header('dop',o[1])
                end                
            end
            if default_dop==0 then
                for _,o in pair(hd.plan and hd.plan.operation or {}) do
                    if o.other_xml then
                        for _,i in pair(o.other_xml.info) do
                            if i._attr and i._attr.type=='dop' then
                                add_header('dop',i[1])
                            end
                        end
                    end
                end
            end
        end
    end
    load_header()
    if phv==0 and type(seq)=='number' and seq>1 then return end

    local skews={ids={},sids={}}
    local skew_list={
        {nil,'Id'},
        {nil,'Skewed|PX#'},
        {nil,'Row|DoP'},
        {'cardinality','Skew|Rows','Ref|Rows','max_card'},
        {'starts','Start|Count','Ref|Starts','max_starts','execs'},
        {'io_inter_bytes','Inter|Connc','Ref|Inter','max_io_inter_bytes','ikb',1024},
        {'read_reqs','Read|Reqs','Ref|Reads','max_read_reqs','rreqs'},
        {'read_bytes','Read|Bytes','Ref|rBytes','max_read_bytes','rkb',1024},
        {'write_reqs','Write|Reqs','Ref|Writes','max_write_reqs','wreqs'},
        {'write_bytes','Write|Bytes','Ref|wBytes','max_write_bytes','wkb',1024},
        {'max_memory','Mem|Bytes','Ref|Mem','min_max_mem','mem',1024},
        {'max_temp','Max|Temp','Ref|Temp','max_max_temp','temp',1024},
        {'aas','ASH|AAS','Ref|AAS'},
        {nil,'Top|Event'},
        {nil,'AAS %|Event'}
    }
    local skew_aas_index,skew_event_index
    local max_skews,detail_skews,total_skews={},{},{}
    local function add_skew_line(id,sid,inst_id,idx,value,multiplex,is_append)
        id,sid=tonumber(id),insid(sid,inst_id)
        if not skews.ids[id] then skews.ids[id]={} end
        local row=skews.ids[id][sid]
        if not row then
            row={id,sid,[skew_event_index+2]={}}
            skews.sids[sid],skews.ids[id][sid],skews[#skews+1]=row,row,row
        end
        value=tonumber(value)*(multiplex or 1)
        if value<=0 then return end
        if not total_skews[id] then total_skews[id]={n={}} end
        local total=total_skews[id]
        if is_append then
            row[idx]=(row[idx] or 0)+value
        else
            if row[idx] then
                total[idx]=total[idx]-row[idx]
                total.n[idx]=total.n[idx]-1
            end
            value=math.max(row[idx] or 0,value)
            row[idx]=value
        end
        total[idx]=(total[idx] or 0)+value
        total.n[idx]=(total.n[idx] or 0)+1
    end

    local function load_skew()
        skew_event_index=#skew_list-1
        for k,v in pairs(skew_list) do
            if v[1]=='aas' then skew_aas_index=k end
            if v[4] then max_skews[v[4]]=k end
            if v[5] then detail_skews[v[5]]={k,v[6]} end
        end

        if hd.plan_skew_detail then
            for i,s in pair(hd.plan_skew_detail.session) do
                local sid,inst_id=s._attr.sid,s._attr.iid
                for _,l in pair(s.line) do
                    local id=l._attr.id
                    add_skew_line(id,sid,inst_id,4,l[1])
                    for n,v in pairs(l._attr) do
                        if detail_skews[n] then
                            add_skew_line(id,sid,inst_id,detail_skews[n][1],v,detail_skews[n][2])
                        end
                    end
                end
            end
        end
    end
    load_skew()

    local statset={
        {'main_','Proc'},
        {'duration_','Wall|Time'},
        {'from_start','From|Start'},
        {'aas_','ASH|AAS'},
        {'cpu_aas','CPU|AAS'},
        {'wait_aas_','Wait|AAS'},
        {'imq_aas_','IMQ|AAS'},
        {'sql_aas_','Other|SQL'},
        {'is_skew_','Is|Skew'},
        {'user_fetch_count','Fetch|Count'},
        {'|','|'},
        {'elapsed_time','Elap|Time'},
        {'queuing_time','Queue|Time'},
        {'cpu_time','CPU|Time'},
        {'user_io_wait_time','IO|Time'},
        {'application_wait_time','App|Time'},
        {'concurrency_wait_time','CC|Time'},
        {'cluster_wait_time','CL|Time'},
        {'plsql_exec_time','PLSQL|Time'},
        {'java_exec_time','JAVA|Time'},
        {'other_wait_time','OTH|Time'},
        {'time_per_buffer_get','Avg|Buff'},
        {'time_per_io_req','Avg|I/O'},
        {'|','|'},
        {'buffer_gets','Buff|Gets'},
        {'disk_reads','Disk|Read'},
        {'read_reqs','Avg|Read'},
        {'read_bytes','Read|Bytes'},
        {'direct_writes','Direx|Write'},
        {'write_reqs','Avg|Write'},
        {'write_bytes','Write|Bytes'},
        {'|','|'},
        {'io_inter_bytes','Inter|Connc'},
        {'unc_bytes','Unzip|Bytes'},
        {'elig_bytes','Elig|Bytes'},
        {'ret_bytes','Return|Bytes'},
        {'cell_offload_efficiency2','Eff|Rate2'},
        {'cell_offload_efficiency','Eff|Rate'},
        {'|','|'},
        {'top_event','Top Event'},
        {'aas_rate','AAS%'},
        seqs={}
    }
    
    local sqlstat={topic='SQL and Process Summary',footprint=error_msg and '$HIR$\\ '..error_msg..' /' or nil,
                   {},
                   {}}--'Main',dur1 or dur2,nil,nil,nil,nil,nil,nil,nil
    local aas_idx,sql_start_idx,from_start_idx

    local px_sets,px_stats={},{}
    local function gs_color(g,s)
        return colors[math.fmod((s-1)*2+g-1,#colors)+1]
    end

    local slaves
    local function load_sqlstats()
        local thresholds_highlights={}
        env.var.define_column('Queue|Time,CPU|Time,IO|Time,App|Time,CC|Time,CL|Time,PLSQL|Time,JAVA|Time,OTH|Time','for','pct1')
        for k,v in ipairs(statset) do
            statset.seqs[v[1]]=k
            thresholds_highlights[k]=thresholds.sqlstat_warm[v[1]]
            sqlstat[1][k]=v[2]
            sqlstat[2][k]=k==1 and 'Main' or k==2 and (dur1 or dur2) or nil
            if not sqlstat.timer_start and v[1]:find('_time$') then
                sqlstat.timer_start=k
            elseif v[1]:find('_time$') then
                sqlstat.timer_end=k
            end
        end
        aas_idx=statset.seqs.aas_
        from_start_idx=statset.seqs.from_start
        sql_start_idx=statset.seqs.is_skew_
        local function add_aas(idx,value)
            value=tonumber(value)
            if value and value>0 then
                sqlstat[2][aas_idx+idx]=(sqlstat[2][aas_idx+idx] or 0)+value
            end
        end
        
        local function get_attr(att,name,plex,max_stats) 
            if not att or not att[name] then return nil end
            local value=tonumber(att[name])
            if value==0 then return nil end
            value=value and value*(plex or 1) or att[name]
            if type(value)=='number' and value>thresholds.sqlstat_aas_min/(plex or 1) and type(max_stats)=='table' 
                and max_stats[name] and max_stats.childs>=thresholds.px_process_count and value>=max_stats[name] then
                return '$PROMPTCOLOR$'..value..'$NOR$'
            end
            return value
        end

        local sample=hd.activity_sampled
        if type(sample)=='table' and sample[1] then sample=sample[1] end
        scan_events(sample,sqlstat[2])
        for k,v in pair(sample and sample.activity or nil) do
            local idx=0
            add_aas(idx,v[1])
            local clz=v._attr.class
            if v._attr.event=='in memory' then
                idx=idx+3
            elseif clz=='Cpu' then
                idx=idx+1
            elseif clz=='Non SQL' or clz=='Other SQL Execution' then
                idx=idx+4
            else
                idx=idx+2
            end
            add_aas(idx,v[1])
        end
        

        local function add_sqlstat(row,stat,max_stats)
            local stats={}
            local buff_idx=statset.seqs.buffer_gets
            for k,v in pair(stat) do
                local att=v._attr
                local idx=statset.seqs[att.name]
                if att and att.name and idx and v[1]~='0' then
                    local v1=tonumber(v[1])
                    if v1 then
                        if row==sqlstat[2] and idx==buff_idx and buffer_bytes then
                            add_header('avg_buffer_size','$COMMANDCOLOR$'..math.round(buffer_bytes/v1/1024,2)..' KB$NOR$')
                        end
                        if v1>(idx==buff_idx and thresholds.buff_gets_min or thresholds.sqlstat_min) and max_stats 
                            and max_stats.childs>=thresholds.px_process_count
                            and max_stats[att.name] and max_stats[att.name]<=v1 then
                            v1=string.to_ansi(v1,'$PROMPTCOLOR$','$NOR$')
                        end
                        row[idx]=v1
                    end
                end
            end
            
            if slaves and row.px_set then
                for i=aas_idx,statset.seqs.cell_offload_efficiency-1 do --exclude offload efficiency
                    local v=row[i]
                    if type(v)=='string' then v=tonumber(v:strip_ansi()) end
                    if v then
                        slaves[i]=(slaves[i] or 0)+v
                    end
                end
            end
        end
        
        add_sqlstat(sqlstat[2],hd.stats.stat)
        local sessions=hd.parallel_info and hd.parallel_info.sessions
        if sessions then
            local prev,px_set,color1,color2
            local set_list,max_stats={},{}
            
            for k,v in pairs(sessions._attr or {}) do
                max_stats[k:gsub('max_','')]=tonumber(v)
            end
            max_stats.count=max_stats.count or max_stats.activity_count
            max_stats.childs=#(sessions.session or {})
            max_stats.max_count,max_stats.max_count_idx=0,0
            for k,s in pair(sessions.session) do
                local px_set,px_name,skew,color1,color2=nil,nil,nil,'',''
                local att=s._attr
                local pname=insid(att.process_name=='PX Coordinator' and 'PX Coord ' or att.process_name,att.inst_id)
                local grp,set=tonumber(att.server_group),tonumber(att.server_set)
                local g,stat
                if set then
                    px_set='G'..grp..'S'..set..' - '
                    color1,color2=gs_color(grp,set),'$NOR$'
                    pname=px_set..pname
                    px_name=insid(att.session_id,att.inst_id)
                    if not px_sets[px_name] then px_sets[px_name]={} end
                    g={g=grp,s=set,name=pname,set=px_set,color=color1,values={}}
                    px_sets[px_name][#px_sets[px_name]+1]=g
                    if not set_list[px_set] then
                        px_sets[#px_sets+1]=g
                        set_list[px_set]=1
                        stat={}
                        px_stats[grp..'.'..set]=stat
                    else
                        stat=px_stats[grp..'.'..set]
                    end
                    if max_stats.childs>=thresholds.px_process_count-1 and not slaves then
                        slaves={"$UDL$PX Slaves"}
                        sqlstat[#sqlstat+1]=slaves
                    end
                end
                
                if px_set and px_set==prev then
                    pname=pname:gsub('.',' ',#px_set-2)
                else
                    prev=px_set
                end
                att=s.activity_sampled and s.activity_sampled._attr or {}
                local start_at=get_attr(att,'first_sample_time');
                local end_at=get_attr(att,'last_sample_time');
                local duration=get_attr(att,'duration',1e6,max_stats)
                local dur=type(duration)=='string' and tonumber(duration:strip_ansi()) or duration
                if start_at then
                    start_at=time2num(start_at)-start_clock
                    end_at=time2num(end_at)-start_clock
                    if slaves then
                        if (not slaves[3] or slaves[3]>start_at) then slaves[3]=start_at end
                        if (not slaves.end_at or slaves.end_at<end_at) then slaves.end_at=end_at end
                        slaves[2]=math.max(slaves[2] or 0,math.max((slaves.end_at-slaves[3]+1)*1e6,dur))
                    end
                end

                sqlstat[#sqlstat+1]={color1..pname..color2,
                                     duration,
                                     start_at,
                                     get_attr(att,'count',nil,max_stats),
                                     get_attr(att,'cpu_count',nil,max_stats),
                                     get_attr(att,'wait_count',nil,max_stats),
                                     get_attr(att,'imq_count',nil,max_stats),
                                     get_attr(att,'other_sql_count',nil,max_stats),
                                     skew and 'Yes' or nil,
                                     px_set=px_set,
                                     class='PX'}
                scan_events(s.activity_sampled,sqlstat[#sqlstat])
                if px_set and slaves then
                    scan_events(s.activity_sampled,slaves)
                end
                if g then 
                    g.data=sqlstat[#sqlstat]
                    local aas=g.data[aas_idx]
                    if aas then
                        if type(aas)=='string' then
                            stat[#stat+1]=tonumber(aas:strip_ansi())
                        else
                            stat[#stat+1]=aas
                        end
                    end
                end
                add_sqlstat(sqlstat[#sqlstat],s.stats and s.stats.stat,max_stats)
                if dur and max_stats.max_count<dur then
                    max_stats.max_count,max_stats.max_count_idx=dur,#sqlstat
                end
            end

            for k,v in pairs(px_stats) do
                local avg,sum,cnt=table.avgsum(v)
                local std=table.stddev(v)
                v.cnt,v.std=cnt,math.max(cnt/2,math.round(cnt-cnt*std/avg,4))
            end

            if max_stats.childs>=thresholds.px_process_count and max_stats.max_count>1e6*thresholds.sqlstat_aas_min then
                sqlstat[max_stats.max_count_idx][2]=string.to_ansi(sqlstat[max_stats.max_count_idx][2],'$PROMPTCOLOR$','$NOR$')
            end

            local instances=hd.parallel_info.instances
            if instances then
                max_stats={}
                for k,v in pairs(instances._attr or {}) do
                    max_stats[k:gsub('max_','')]=tonumber(v)
                end
                max_stats.count=max_stats.count or max_stats.activity_count
                max_stats.childs=#(instances.instance or {})
                for k,s in pair(instances.instance) do
                    local att=s.activity_sampled and s.activity_sampled._attr or {}
                    local start_at=get_attr(att,'first_sample_time');
                    sqlstat[#sqlstat+1]={'Inst #'..s._attr.inst_id,
                                         get_attr(att,'duration',1e6,max_stats),
                                         start_at and time2num(start_at)-start_clock or nil,
                                         get_attr(att,'count',nil,max_stats),
                                         get_attr(att,'cpu_count',nil,max_stats),
                                         get_attr(att,'wait_count',nil,max_stats),
                                         get_attr(att,'imq_count',nil,max_stats),
                                         get_attr(att,'other_sql_count',nil,max_stats),
                                         class='INST'}
                    scan_events(s.activity_sampled,sqlstat[#sqlstat])
                    add_sqlstat(sqlstat[#sqlstat],s.stats and s.stats.stat,max_stats)
                end
            end
        end
        local elapsed_time=statset.seqs.elapsed_time
        local cpu_time=statset.seqs.cpu_time
        local buffer_gets=statset.seqs.buffer_gets
        local io_time=statset.seqs.user_io_wait_time
        local disk_reads=statset.seqs.read_reqs
        local disk_writes=statset.seqs.write_reqs
        local buff_avg=statset.seqs.time_per_buffer_get
        local io_avg=statset.seqs.time_per_io_req
        local ic_idx,elig_idx,rtn_idx=statset.seqs.io_inter_bytes,statset.seqs.elig_bytes,statset.seqs.ret_bytes
        local io_idx={disk_reads,disk_writes}
        local max_io,max_io_idx,io_cnt=0,0,0
        local function num(val)
            return type(val)=='string' and tonumber(val:strip_ansi()) or val or 0
        end
        local threshold_idx={}
        local event_idx=statset.seqs.top_event
        for i=2,#sqlstat do
            local stat=sqlstat[i]
            local intercc=0
            
            stat[event_idx],stat[event_idx+1]=get_top_events(stat.events,tonumber((string.from_ansi(stat[aas_idx]))),nil,1)

            if stat[io_time] and (stat[disk_reads] or stat[disk_writes]) then
                stat[io_avg]=math.round(num(stat[io_time])/(num(stat[disk_reads])+num(stat[disk_writes])),2)
            end
            --if not stat[2] then stat[2]=stat[elapsed_time] end
            if stat[elapsed_time] and stat[cpu_time] and stat[buffer_gets] then
                local buffs=num(stat[buffer_gets])
                if buffs>thresholds.buff_gets_min then
                    local cpu=num(stat[cpu_time])
                    local rate=cpu/num(stat[elapsed_time])
                    rate=rate*(rate+(1-rate)*rate)
                    rate=math.round(cpu*rate/buffs,2)
                    if rate>=thresholds.sqlstat_aas_min*(1-rate) then stat[buff_avg]=rate end
                end
            end

            for j,idx in ipairs(io_idx) do
                if stat[idx] and stat[idx+1] then
                    intercc=intercc+stat[idx+1]
                    stat[idx]=math.round(stat[idx+1]/stat[idx],1)
                end
            end

            if stat[elig_idx] then intercc=intercc-stat[elig_idx] end
            if stat[rtn_idx]  then intercc=intercc+stat[rtn_idx] end
            if not stat[ic_idx] and intercc>0 then 
                stat[ic_idx]=intercc
                if stat.class=='PX' then
                    io_cnt=io_cnt + 1
                    if max_io<intercc then
                        max_io=intercc
                        max_io_idx=i
                    end
                end
            end

            local ela=stat[sqlstat.timer_start]
            if type(ela)=='string' then ela=tonumber(ela:strip_ansi()) end
            for j=sqlstat.timer_start+1,sqlstat.timer_end do
                if stat[j] then
                    local st,ed
                    if type(stat[j])=='string' then
                        stat[j],st,ed=stat[j]:from_ansi()
                    end
                    local pct=math.round(stat[j]/ela,3)
                    stat[j]=pct>0 and string.to_ansi(pct,st,ed) or nil
                end
            end

            for idx, config in pairs(thresholds_highlights) do
                local current=stat[idx]
                if type(current)=='number' and (type(config)~='table' or config[1]==i-1) then
                    local threshold=type(config)~='table' and config or config[2]
                    if current>threshold then
                        stat[idx]=string.to_ansi(current,'$HIR$','$NOR$')
                        if i==4 then --PX Slaves
                            stat[idx]=stat[idx]..'$UDL$'
                        end
                    end
                end
            end
        end
        if io_cnt>=thresholds.px_process_count and max_io>thresholds.sqlstat_min then
            sqlstat[max_io_idx][ic_idx]=string.to_ansi(sqlstat[max_io_idx][ic_idx],'$PROMPTCOLOR$','$NOR$')
        end
    end
    load_sqlstats()

    local line_events
    local total_aas=tonumber(sqlstat[2][aas_idx]) or 1

    local outlines,preds={},{ids={}}
    local nid,xid=9999,0

    report_header=print_header("Summary"..(sql_id and (' (SQL Id: '..sql_id..')') or ''),false)
    report_header.pivot,report_header.pivotsort=1,'off'
    report_header.footprint=plsql and ('[PL/SQL: '..plsql..']') or ''
    local gs={list={},g=0,s=2}
    local runtime_stats={
        ['Min DOP after downgrade']='dop',
        ['DOP downgrade']='dop',
        ['Distribution method']='distrib',
        ['Key Data Type']='kv_type',
        ['Eligible bytes']='elig_bytes',
        ['Filtered bytes']='ret_bytes',
        ['SI saved bytes']='saved_bytes',
        ['Columnar cache saved bytes']='saved_bytes',
        ['Slow metadata bytes']='slow_meta',
        ['Dynamic Scan Tasks on Thread']='imds',
        ['Metadata bytes']='slow_meta',
        ['Flash cache bytes']='flash_cache_bytes'
    }
    
    local px_group={}
    local function load_plan_px_group()
        for _,b in pair(hd.activity_detail and hd.activity_detail.bucket) do
            for _,a in pair(b.activity) do
                local att=a._attr
                if att and att.line and att.px then
                    local line,g=tonumber(att.line),tonumber(att.px)
                    local rt,as=tonumber(att.rt) or 0,tonumber(a[1]) or 0
                    if not px_group[line] then px_group[line]={} end
                    if not px_group[line][g] then px_group[line][g]={} end
                    px_group[line][g].as=(px_group[line][g].as or 0)+as
                    px_group[line][g].rt=(px_group[line][g].rt or 0)+rt
                end
            end
        end

        for line,grps in pairs(px_group) do
            local cnt,as,rt,g=0,0,0
            for grp,o in pairs(grps) do
                if as<o.as or as==o.as and rt<o.rt then
                    as,rt,g=o.as,o.rt,grp
                end
                if o.as>=1 then cnt=cnt+1 end
            end
            px_group[line].g,px_group[line].c=g,cnt
        end
    end
    load_plan_px_group()

    local plan_stats
    local function load_plan_monitor()
        local rwstats={}
        local function process_rwstat(id,stat)
            local meta=rwstats[stat._attr.group_id]
            if not meta then 
                meta={ids={}}
                rwstats[stat._attr.group_id]=meta 
            end
            
            local function process_rw(mt)
                if meta[mt._attr.id] then
                    local lid=mt.id or id
                    local name=(meta[mt._attr.id].name):trim('.')
                    local col_name=runtime_stats[name]
                    if col_name then
                        if col_name=='distrib' and dist_methods[mt[1]] then
                            infos[id][col_name]=dist_methods[mt[1]]
                        elseif col_name=='kv_type' and kv_types[mt[1]] then
                            infos[id]['distrib']=kv_types[mt[1]]
                        elseif col_name=='dop' then
                            infos[id][col_name]=mt[1]
                        elseif tonumber(mt[1]) then
                            if tonumber(mt[1])>0 then
                                infos[id][col_name]=(mt[col_name] or 0)+tonumber(mt[1])
                            end
                        else
                            infos[id][col_name]=mt[1]
                        end
                    else
                        local desc=(meta[mt._attr.id].desc or name)
                        local num=number_fmt(mt[1],desc)
                        if 'downgrade reason'==name:lower() and reasons[mt[1]] then
                            num,desc=mt[1],reasons[mt[1]]
                        end
                        process_pred(preds,lid,'Other',num:rpad(10)..' -> '..desc)
                        if name=='Total User Rows' then
                            preds.ids[lid].rows=tonumber(mt[1])
                        elseif name=='Total Bloom Filtered Rows' or name=='Total Min/Max Filtered Rows' then
                            preds.ids[lid].saved=(preds.ids[lid].saved or 0)+tonumber(mt[1])
                        elseif name=='Total Number of Rowsets' then
                            infos[id].rowsets=tonumber(mt[1])
                        elseif name=='Total Spilled Probe Rows' then
                            infos[id].spills=tonumber(mt[1])
                        end
                    end
                    mt.id=nil
                else
                    mt.id=id
                    local sets=meta.ids[mt._attr.id]
                    if not sets then
                        sets={}
                        meta.ids[mt._attr.id]=sets
                    end
                    sets[#sets+1]=mt
                end
            end

            local function process_meta(mt)
                meta[mt._attr.id]=mt._attr
                local sets=meta.ids[mt._attr.id]
                if sets then
                    for k,v in ipairs(sets) do
                        process_rw(v)
                    end
                    meta.ids[mt._attr.id]=nil   
                end
            end

            if stat.metadata then
                for k,v in pair(stat.metadata.stat) do process_meta(v) end
            end
            if stat.stat then
                for k,v in pair(stat.stat) do process_rw(v) end
            end
        end

        if hd.plan_monitor then
            for k,v in pairs(hd.plan_monitor._attr or {}) do
                add_header(k,v)
            end
        end
        plan_stats=hd.plan_monitor and hd.plan_monitor.operation or nil
        if not plan_stats then 
            plan_stats={}
            return
        end
        table.sort(plan_stats,function(a,b) return tonumber(a._attr.id)<tonumber(b._attr.id) end)
        
        local lvs={}
        
        local function build_gs(g,s,id,depth,color)
            local stat=px_stats[g..'.'..s]
            local px={depth=depth,id=id,g=g,s=s,color=color or gs_color(g,s),loc=#gs.list+1,cnt=stat and stat.cnt or nil}
            gs[#gs+1],gs.list[#gs.list+1]=px,px
            return gs[#gs]
        end

        for n,p in ipairs(plan_stats) do
            local info,pid=p._attr
            local id,depth,position=tonumber(info.id),tonumber(info.depth),tonumber(info.position) or id
            info.id,infos[id]=id,info
            xid=xid<id and id or xid
            nid=nid>id and id or nid
            info._cid={id=id,position=position}
            lvs[depth]=info._cid
            if depth>0 then
                if lvs[depth-1][position] then
                    position=position-1
                    position=(not lvs[depth-1][position] and position) or 1+#lvs[depth-1]
                    info._cid.position=position
                end
                lvs[depth-1][position]=id
                pid=lvs[depth-1]
                info._pid=pid
            end
            
            --[[first_active/first_row/last_active/duration/from_most_recent/from_sql_exec_start/percent_complete/time_left/
                starts/max_starts/dop/cardinality/max_card/memory/max_memory/min_max_mem/temp/max_temp/spill_count/max_max_temp
                read_reqs/max_read_reqs/read_bytes/max_read_bytes/write_reqs/max_write_reqs/write_bytes/max_write_bytes/
                io_inter_bytes/max_io_inter_bytes/cell_offload_efficiency/rwsstats--]]
            for k,s in pair(p.stats.stat) do
                local att=s._attr
                local name=att.name
                info[name]=s[1]
                if max_skews[name] then
                    --print(id,att.sid,att.iid,name,s[1])
                    add_skew_line(id,att.sid,att.iid,max_skews[name],s[1])
                end
            end
            if info.first_row and info.first_active then info.first_row=time2num(info.first_row)-start_clock end
            local st,ed=info.first_row or tonumber(info.from_sql_exec_start) or 1e9,tonumber(info.from_most_recent) or 1e9
            info._cid.st,info._cid.ed=st,ed

            while true do
                if not pid then
                    break
                end
                local parent=infos[pid.id]
                local c=parent._cid
                if c.st>st then c.st=st end
                if c.ed>ed then c.ed=ed end
                pid=parent._pid
            end
            
            for k,s in pairs(p.optimizer or {}) do
                if k=='cardinality' then k='card' end
                info[k]=s
            end

            for k,s in pairs(p) do
                if type(s) ~='table' then 
                    info[k]=s
                end
            end
            if p.rwsstats then process_rwstat(id,p.rwsstats) end
            local obj=p.object or {}
            info.object,info.owner=obj.name,obj.owner
        end

        local curr=xid+1

        local function sort_ord(a,b)
            local n1,n2=infos[a]._cid,infos[b]._cid
            if n1.st==1e9 or n2.st==1e9 then return n1.position<n2.position end
            local st1,st2=n1.st,n2.st
            local ed1,ed2=n1.ed,n2.ed
            local diff=1+math.ceil(math.log(math.abs(b-a),2))
            if n1.position<n2.position then 
                ed1=ed1+diff
                st1=st1-diff
            else
                ed2=ed2+diff
                st2=st2-diff
            end
            if st1~=st2 then return st1<st2 end
            if ed1~=ed2 then return ed1>ed2 end
            return n1.position<n2.position
        end

        local function process_ord(node,parent)
            node.ord=curr
            curr=curr-1
            if parent and (parent.gs==node.gs or not parent.gs) then
                parent.child_dop=node.dop or node.child_dop
                node.parent_dop=parent.dop or parent.parent_dop
            end
            local cid={}
            for k,v in pairs(node._cid) do
                if type(k)=='number' then
                    cid[#cid+1]=v
                else
                    cid[k]=v
                end
            end
            if #cid>0 then
                table.clear(node._cid)
                for k,v in pairs(cid) do
                    node._cid[k]=v
                end
            end
            table.sort(node._cid,sort_ord)
            
            for i=#node._cid,1,-1 do
                process_ord(infos[node._cid[i]],node)
            end
        end
        process_ord(infos[nid])

        local function process_gs(node,parent)
            local id,depth=tonumber(node.id),tonumber(node.depth)
            local g1,s1=px_group[id] and px_group[id].g or nil,tonumber(node.px_type)

            if node.name=='PX SEND' then
                while #gs>0 and depth<=gs[#gs].depth do
                    gs[#gs]=nil
                end

                if not gs[#gs] then
                    gs.g,gs.s=gs.g+1,1
                else
                    gs.s=gs[#gs].s==1 and 2 or 1
                end

                g1,s1=g1 or gs.g,s1 or gs.s
                if g1~=gs.g then
                    local r1,r2=px_group[id][g1],px_group[id][gs.g]
                    if r2 and r1.as==r2.as then
                        g1=gs.g
                        px_group[id].g=g1
                    end
                end
                node.gs=build_gs(g1 or gs.g,s1 or gs.s,id,depth)
            elseif depth>0 then
                node.gs=infos[node._pid.id].gs
                local c=px_group[id] and px_group[id].c or 1
                if node.gs then
                    local g1,s1=g1 or node.gs.g,s1 or node.gs.s
                    if g1~=node.gs.g then
                        local r1,r2=px_group[id][g1],px_group[id][node.gs.g]
                        if r2 and r1.as==r2.as then
                            g1=node.gs.g
                            px_group[id].g=g1
                        end
                    end
                    if g1~=node.gs.g or s1~=node.gs.s then
                        node.gs=build_gs(g1,s1,id,depth)
                    end
                elseif g1 and s1 then
                    node.gs=build_gs(g1,s1,id,depth)
                end
            end
            
            if gs[#gs] and not gs[#gs].dop then gs[#gs].dop=node.dop end

            if parent then
                if node.gs and node.gs==parent.gs then
                    if not node.px_type and parent.dop then
                        node.px_type=parent.px_type
                    end
                end
            end

            for _,n in ipairs(node._cid) do process_gs(infos[n],node) end

            local px_type,g=tonumber(node.px_type),px_group[id] and px_group[id].g or 1
            if px_type and not node.gs then
                for i,l in ipairs(gs.list) do
                    if g==l.g and px_type==l.s then
                        node.gs=l
                        if l.id>node.id then l.id=node.id end
                        --if not node.dop and l.dop then node.dop=math.min(l.dop,node.starts or l.dop)  end
                        break
                    end
                end
            end
        end
        process_gs(infos[nid])
    end
    load_plan_monitor()

    local sec2num=env.var.format_function("smhd1")
    local clock_diffs=0
    local function load_activity_detail()
        local stats=hd.activity_detail
        if stats then stats=stats.bucket end
        local cl,ev,rt,as,pct,top,bk=1,2,4,5,6,7,8
        local max_event_len=#('cell single block physical read')
        local total_clock=0
        if not stats then return end
        --process line level events:  report/sql_monitor_report/activity_detail/bucket
        local ids=attrs.top_event
        local function add_id_class(id,clz,v)
            ids[id].class[clz]=(ids[id].class[clz] or 0)+v
        end
        local step_rep={
            Executing='Exec',
            Sampling='Sample',
            Joining='Join',
            Scheduling='Schedule',
            Initializing='Init',
            Flushing='Flush',
            Allocating='Alloc',
            Parsing='Parse',
            Preparing='Prep',
            Aborting='Abort'
        }
        local function process_stats(s,clock)
            local attr=s._attr
            local id=tonumber(attr.line) or 0
            local info=infos[id]
            if not ids[id] then ids[id]={-1,nil,events={}} end
            if attr.plsql_name and attr.plsql_name~='Unavailable' then
                attr.plsql_name=attr.plsql_name:gsub('^.-%.','')
            else
                attr.plsql_name=nil
            end
            if attr.plsql_id and attr.plsql_name then plsqls[attr.plsql_id]=attr.plsql_name end
            if attr.step then
                attr.step=attr.step:gsub('PX Server%(s%) %- ','[PX] ')
                attr.step=attr.step:gsub('QC %- ','[QC] ')
                attr.step=attr.step:gsub('%w+ing',step_rep)
            end
            local grp={
                attr.class or attr.other_sql_class, --wait class
                attr.event or --event
                    attr.sql and ('SQL: '..attr.sql) or 
                    attr.none_sql and ('SQL: '..attr.none_sql) or
                    attr.plsql_name and ('PLSQL: '..attr.plsql_name) or 
                    attr.plsql_id and ('PLSQL: '..(plsqls[attr.plsql_id] or attr.plsql_id)) or 
                    attr.top_sql_id and ('Top-SQL: ' .. attr.top_sql_id) or
                    attr.step or nil,
                '|',
                nil,nil,nil,nil,0, --buckets
                lines={}
            }
            if attr.step then
                if grp[ev]~=attr.step and not attr.step:find('[PX] Exec',1,true) and grp[ev]~=attr.step then 
                    grp[ev]=grp[ev]..' ('..attr.step..')' 
                end
            end
            --group by class+event
            local event=grp[ev] or grp[cl] or ' '
            if #event>max_event_len+3 then 
                event=event:sub(1,max_event_len):rtrim('.')..'..' 
            elseif event:lower()=='cpu' then
                event='ON CPU'
            end
            if not ids[id].events[event] then ids[id].events[event]={} end
            local stack=(grp[ev] or '')..'\1'..(grp[cl] or '')
            if not stacks[stack] then
                events[#events+1]=grp
                stacks[stack]=#events
            end
            grp=events[stacks[stack]]
            grp[bk]=grp[bk]+1
            --rt(response time) and aas
            if not grp.lines[id] then grp.lines[id]={} end
            if not clock[id] then clock[id]={} end
            if not ids[id].clock then ids[id].clock,ids[id].class={},{} end
            for k,v in pairs{[rt]=tonumber(attr.rt),[as]=tonumber(s[1])} do
                grp[k]=(grp[k] or 0)+v
                --aggregate line level events: {max,max_event,total_rt,total_aas}
                local i=k==rt and 1 or 2
                ids[id][2+i]=(ids[id][2+i] or 0)+v
                --aggregate line level events: {rt,aas}
                grp.lines[id][i]=(grp.lines[id][i] or 0)+v
                ids[id].events[event][i]=(ids[id].events[event][i] or 0)+v
                if i>1 and not attr.skew_count or i==1 and attr.line then
                    if attr.dop then
                        clock[id][4]=(clock[id][4] or 0)+v/math.max(tonumber(attr.dop),1)
                    elseif default_dop>1 and not attr.line then
                        clock[id][4]=(clock[id][4] or 0)+v/default_dop
                    elseif default_dop>1 and not (infos[id] and infos[id].dop) and (attr.step or ''):find('[PX]',1,true) then
                        clock[id][4]=(clock[id][4] or 0)+v/(default_dop)
                    elseif infos[id] and infos[id].px_type=='QC' then
                        local dop=infos[id].dop or default_dop
                        clock[id][4]=(clock[id][4] or 0)+v/((attr.px or (attr.step or ''):find('[PX]',1,true)) and dop or 1)
                    elseif default_dop>1 and attr.step and not infos[id].dop and not(infos[id].gs and infos[id].gs.cnt) then
                        clock[id][4]=(clock[id][4] or 0)+v/default_dop
                    elseif event=='Parallel Skew' and infos[id] and not infos[id].dop then
                        clock[id][4]=(clock[id][4] or 0)+v/(infos[id].gs and infos[id].gs.cnt or default_dop)
                    else
                        clock[id][i]=(clock[id][i] or 0)+v
                    end
                end
                if v>0 then
                    local w
                    if i==2 then
                        if grp[cl]=='Cpu' then w=1;add_id_class(id,'cpu',v) end
                        if grp[ev] and grp[ev]:find('SQL:',1,true) then w=1;add_id_class(id,'sql',v) end
                        if grp[ev]=='in memory' then w=1;add_id_class(id,'imq',v) end
                        if not w then add_id_class(id,'wait',v) end
                        if not attr.line then add_id_class(id,'no_line',v) end
                    end
                end
            end
            
            if attr.skew_count then
                local sid=insid(attr.skew_sid,attr.skew_iid)
                local aas=tonumber(attr.skew_count)
                clock[id][3]=(clock[id][3] or 0)+aas
                add_skew_line(id,attr.skew_sid,attr.skew_iid,skew_aas_index,aas,nil,true)
                local skew=skews.ids[id][sid]
                skew[skew_event_index+2][event]=(skew[skew_event_index+2][event] or 0)+aas
            end
        end
        local clock,list={},{}
        for k,v in pair(stats) do
            table.clear(clock)
            table.clear(list)
            for k1,v1 in pair(v.activity) do 
                process_stats(v1,clock)
            end
            local itv,total,sum=interval,0,0
            for id,aas in pairs(clock) do
                local g=infos[id] and infos[id].gs or nil
                local dop=tonumber(infos[id] and infos[id].dop) or 1
                local dop1=dop
                if dop1 and g and g.cnt and dop1>g.cnt then 
                    dop1=g.cnt
                end

                for i=4,1,-1 do
                    local c=aas[i]
                    if c and c>0 then
                        if dop<2 or i>2 then
                            ids[id].clock[2]=(ids[id].clock[2] or 0)+c
                            total_clock=total_clock+c 
                            itv=itv-c
                            aas[i]=0
                        elseif i==2 then
                            list[id]=(list[id] or 0)+c
                            sum=sum+c
                            c=c/dop1
                            aas[2],total=c,total+c
                        else
                            list[id]=(list[id] or 0)+c
                            sum=sum+c
                            c=c/dop --for resp, devide with dop first
                            aas[2],total=(aas[2] or 0)+c,total+c
                        end
                    end
                end
            end
            total=math.max(0,math.min(itv,sum)/total)
            for id,c in pairs(list) do
                local ela=math.min(c,math.round(clock[id][2]*total,5))
                ids[id].clock[2]=(ids[id].clock[2] or 0)+ela
                total_clock=total_clock+ela
            end
        end

        for k,c in pairs(events) do
            c[top]=get_top_events(c.lines,c[as],c[rt],5)
            if c[as] then c[pct]=math.round(c[as]/total_aas,4) end
        end

        table.sort(events, function(a,b) return (a[as] or 0)>(b[as] or 0) end)
        table.insert(events,1,{'Class','Event','|','Resp','AAS','Pct','Top Lines','Buckets'})
        local top_lines={}
        for id,v in pairs(ids) do
            v[2],v[1]=get_top_events(v.events,v[4],v[3])
            for e,aas in pairs(v.events) do
                if e:lower():find('skew') and infos[id] then
                    infos[id].skew=sec2num(math.max(aas[1] or 0,aas[2] or 0))
                end
            end
            for clz,num in pairs(v.class) do
                if v[4] and v[4]>0 then
                    v.class[clz]=math.round(num/v[4],2)
                else
                    v.class[clz]=sec2num(num)
                end
            end
            if v.clock[2] then v[5]=math.round(v.clock[2]/total_clock,4) end
            if v.clock[2]~=v[4] then clock_diffs=clock_diffs+1 end
            top_lines[#top_lines+1]={id,'|',v.clock[2],v[5],'|',v[3],v[4],'|',v[2],v[1],v.clock[1]}
        end
        env.var.define_column('AAS1','noprint')
        env.var.define_column('Clock','for','smhd2')
        table.sort(top_lines,function(a,b)
            if not a[3] then return false end
            if not b[3] then return true end
            return a[3] > b[3]
        end)
        table.insert(top_lines,1,{'Id','|','Clock','Pct','|','Resp',clock_diffs==0 and 'AAS1' or 'AAS','|','Top Event','AAS%'})
        for i=#top_lines,math.max(7,#events+1),-1 do
            top_lines[i]=nil
        end
        top_lines.topic,events.topic='Top Lines (Clock='..sec2num(total_clock)..')','Wait Events (AAS='..sec2num(total_aas)..')'
        line_events={top_lines,'|',events}
    end
    load_activity_detail()
    local binds,qbs,lines={nil,hd.binds},{},{}
    local first_start
    local qb_transforms={}
    
    local function load_plan()
        local op_fmt,space='%s%s%s%s%s%s',' '
        local child_fmt,child_color,child_sep='%s%s$NOR$'
        local ord_fmt='%'..(#(tostring(xid+1)))..'s'
        local skps={}
        xid='%'..(#(tostring(xid)))..'d'
        local id_fmt='%s%s%s'
        local function format_operation(pad,operation,options,color)
            local st=color or ''
            local ed=color and '$NOR$' or ''
            return op_fmt:format(pad,st,operation,options and (' '..options) or '','',ed)
        end

        local lvs,nodes={colors={},nodes={}},{}

        local function format_id(id,skp,color,pred,most_recent)
            local st=color or ''
            local ed=color and '$NOR$' or ''
            local stat
            if most_recent==0 then 
                if status=='error' and error_msg then 
                    stat='$HIR$X$NOR$'
                    lines.status=stat..': Error'
                elseif status=='running' then
                    stat='$PROMPTCOLOR$O$NOR$'
                    lines.status=stat..': Running'
                end
            end
            id=xid:format(id)
            if st~='' then id=id:gsub('%d+',function(s) return st..s end) end
            return id_fmt:format(stat or skp>0 and '-' or pred and '*' or ' ',id,ed)
        end

        local envs={}

        local env_fmt='OPT_PARAM: %s = %s'
        if hd.target and hd.target.optimizer_env then
            for k,v in pair(hd.target.optimizer_env.param) do
                add_hint(envs,outlines,env_fmt:format(v._attr.name,v[1]))
            end
        end

        plan={}
        local ops=hd.plan and hd.plan.operation or nil
        if ops then
            for n,p in ipairs(ops) do 
                if p._attr.id then plan[tonumber(p._attr.id)]=p end
            end
        end
        
        local function get_interconn(s)
            local intercc=tonumber(s.io_inter_bytes)
            if not intercc or intercc==0 then
                intercc=(tonumber(s.read_bytes) or 0) + (tonumber(s.write_bytes) or 0)
            end
            s.io_inter_bytes=intercc>0 and intercc or nil
            return s.io_inter_bytes
        end
        local g,prev_ord=nil,'-1'
        for n,m in ipairs(plan_stats) do
            local id=tonumber(m._attr.id)
            local s=infos[id]
            local p=plan[id] or {}
            local color,id_color
            local e=attrs.top_event[id] or {clock={},class={}}
            local depth,child=tonumber(s.depth)

            if p.node and not nodes[p.node] then
                nodes[p.node]={p.object,name=p.node}
                --if p.object:sub(1,1)==':' then nodes[p.object]=nodes[p.node] end
            end

            s.skp=tonumber(s.skp) or skps[id] or 0
            if s._cid and #s._cid>1 then
                if s.skp==0 then
                    color=colors[math.fmod(#lvs.colors,#colors)+1]
                    s._cid.nodetag,s._cid.sep,s._cid.color,lvs.colors[#lvs.colors+1]='+','|',color,color
                else
                    color='$GRY$'
                    s._cid.nodetag,s._cid.sep,s._cid.color='-',':',color
                end
            end

            if s._pid then
                if #s._pid<2 then 
                    lvs[depth]=' '
                elseif s._pid[#s._pid]==id then
                    child=3
                elseif s._pid[1]<id then
                    child=2
                else
                    child=1
                end
                if child then
                    lvs[depth]=s._pid.nodetag
                    child_color,child_sep=s._pid.color,s._pid.sep
                    lvs[depth]=child_fmt:format(child_color,lvs[depth])
                end
            else
                lvs[depth]=''
            end
            local avg_bytes=s.bytes and (tonumber(s.card) or 0)>0 and s.bytes/s.card or nil
            p.proj={'','','',avg_bytes and ('B'..math.round(avg_bytes)) or ''}
            if p.project then
                process_pred(preds,id,'proj',p.project,p)
            end
            if p.proj[2]=='' and infos[id-1] and infos[id-1].rowsets and s.cardinality then
                p.proj[2]='R'..math.round(s.cardinality/infos[id-1].rowsets)..','
            end
            if p.proj[2] and p.proj[2]:match('R[0-4],') then
                p.proj[2]='$HIR$'..p.proj[2]:sub(1,2)..'$NOR$,'
            end
            for k,v in pair(p.predicates) do
                process_pred(preds,id,v._attr.type,v[1],p,p.object_alias)
            end
            local alias,qb=(p.object_alias or ''):gsub('"',''),p.qblock
            local obj=s.object or s.name:find('^VIEW') and alias~='' and ('$REV$'..alias:gsub('@.*','$NOR$')) or p.node and nodes[p.node][1] or nil
            if obj and obj:sub(1,1)~=':' then obj=' '..obj end
            process_qb(qbs,qb,alias,id,depth)
            
            local px_color=s.gs and s.gs.color or nil
            local px_type=s.px_type
            if px_type=='QC' then px_color=nil end
            if tonumber(px_type) then px_type='S'..px_type end
            if px_type and px_color and s.gs then
                g=s.gs.g
                px_type=px_color..px_type..'$NOR$'
            end
            local start_at=tonumber(s.from_sql_exec_start)
            if start_at and (first_start==nil or first_start>start_at) then first_start=start_at end
            s.aas=e[4]
            table.sort(s._cid)
            local ord=ord_fmt:format((color or child or #s._cid==0 or not s._pid) and s.ord or (prev_ord:find('%d') and '^') or ':')
            if s.ord==1 then
                ord=colors[2]..ord..'$NOR$'
            end
            prev_ord=ord
            local most_recent=tonumber(s.from_most_recent)
            local coord_color=s.name=='PX COORDINATOR' and '$UDL$' or nil
            if coord_color and px_color then
                coord_color=coord_color..'$HEADCOLOR$'
            elseif s.name=='JOIN FILTER' and s.options=='USE' and not preds.ids[id] then
                obj='$HIR$'..obj..'$NOR$'
            elseif preds.ids[id] and preds.ids[id].rows and preds.ids[id].saved then --calc bloom filter efficiency
                local row_len=avg_bytes or 8
                local target_line=infos[id+2]
                if target_line and target_line.options and target_line.options:find('FULL') then
                    local inter_bytes=get_interconn(target_line)
                    if inter_bytes and inter_bytes>0 and target_line.cardinality then
                        row_len=math.max(row_len,inter_bytes/target_line.cardinality)
                    end
                end
                s.elig_bytes=math.round(row_len*preds.ids[id].rows)
                s.ret_bytes=math.round(row_len*(preds.ids[id].rows-preds.ids[id].saved))
            end

            if s.elig_bytes and s.ret_bytes then
                s.cell_offload_efficiency=math.round(100*(s.elig_bytes-s.ret_bytes)/s.elig_bytes,2)
            end

            local options=s.options
            if s.spills and #s._cid>0 then
                local probe=infos[s._cid[#s._cid]]
                if probe and probe.cardinality then
                    options=(options and (options..' ') or '')..'[Spills='..math.round(s.spills*100/probe.cardinality,2)..'%]'
                end
            end
            local percent=tonumber(s.percent_complete)
            if percent and percent<100 then
                percent='['..percent..'%]'
            end
            lines[#lines+1]={
                id=id,
                format_id(id,s.skp, px_group[id] and px_group[id].c>1 and ('$HEADCOLOR$'..(px_color or '')) or px_color,preds.ids[id],most_recent),
                percent or ord,
                '|',
                px_type,
                tonumber(s.dop),
                s.skew,
                '|',
                e.clock[2],
                e[5],
                '|',
                e[3],
                s.aas,
                '|',e.class.no_line,e.class.cpu,e.class.wait,e.class.sql,e.class.imq,
                '|',
                e[2],
                e[1],
                '|',
                format_operation(table.concat(lvs,'',1,depth),s.name,options,s.skp>0 and '$GRY$' or color or coord_color),
                '|',
                obj,
                '|',
                type(p.pred)=='table' and table.concat(p.pred,'') or nil,
                '|',
                table.concat(p.proj,''):gsub(',$',''),
                '|',
                s.distrib or p.distrib or s.partition_start and (
                    s.partition_start==s.partition_stop and s.partition_start
                    or (s.partition_start..' - '..s.partition_stop)
                ) or nil,
                '|',
                tonumber(s.starts),
                tonumber(s.cardinality),
                tonumber(s.card),
                tonumber(s.io_cost),
                '|',
                tonumber(s.duration),
                start_at,
                s.first_row,
                most_recent,
                '|',
                tonumber(s.max_memory),
                tonumber(s.max_temp),
                '|',
                s.imds,
                get_interconn(s),
                tonumber(s.read_reqs),
                s.read_reqs and math.ceil(tonumber(s.read_bytes)/tonumber(s.read_reqs)) or nil,
                tonumber(s.write_reqs),
                s.write_reqs and math.ceil(tonumber(s.write_bytes)/tonumber(s.write_reqs)) or nil,
                '|',
                s.elig_bytes,
                s.ret_bytes,
                s.saved_bytes,
                s.flash_cache_bytes,
                s.slow_meta,
                s.cell_offload_efficiency,
                '|',
                strip_quote(p.object_alias),
                '|',
                strip_quote(qb and qb:gsub('^@','') or nil),
            }
            attrs.lines[id]=lines[#lines]
            if child then lvs[depth]=child==3 and ' ' or child_fmt:format(child_color,child_sep) end
            if p.rwsstats then process_rwstat(id,p.rwsstats) end
            local xml=p.other_xml
            if xml then
                binds[1]=xml.peeked_binds
                parse_other_xml(xml,add_header,envs,outlines,qb_transforms,skps)
            end
        end
    end
    load_plan()

    binds=load_binds(binds)

    local skew_outputs
    local function calc_skews()
        if #skews>0 then
            local rows={topic='Skew Info',footprint='[Ref = Avg value except skewed PX]',{}}
            local len=#skew_list
            env.var.define_column('Ref|Inter,Ref|rBytes,Ref|wBytes,Ref|Mem,Ref|Temp','for','kmg1')
            env.var.define_column('Ref|Rows,Ref|Starts,Ref|Reads,Ref|Writes','for','tmb1')
            table.sort(skews,function(a,b)
                if a[1]~=b[1] then 
                    return a[1]<b[1]
                else
                    return a[2]<b[2]
                end
            end)
            local header=rows[1]
            for j,col in ipairs(skew_list) do
                header[#header+1],header[#header+2]=col[2],col[3]
                if j<len then header[#header+1]='|' end
            end
            local gs_idx=1

            for i,c in ipairs(skews) do
                local t=c[skew_aas_index]
                if t then
                    c[skew_event_index],c[skew_event_index+1]=get_top_events(c[skew_event_index+2],t) 
                end
                local id=c[1]
                local row,pxstat={}
                local info=infos[id]

                while gs.list[gs_idx+1] and gs.list[gs_idx+1].id<=id do
                    gs_idx=gs_idx+1
                end
                --print(id,gs_idx,gs.list[gs_idx].g,gs.list[gs_idx].s,c[2],table.dump(px_sets[c[2]]))
                
                if gs.list[gs_idx] then
                    local rank,name,color=-1
                    local function get_px_name(g,idx)
                        local rnk=0
                        if g.s==gs.list[gs_idx].s then
                            rnk=rnk+2000-g.s*2
                        end
                        if g.g==gs.list[gs_idx].g then
                            rnk=rnk+1000-g.g*2
                        end
                        if rnk>=rank then name,rank,color,pxstat=idx==2 and g.set or g.name,rnk,g.color,g.data end
                    end
                    if px_sets[c[2]] then
                        for _,g in ipairs(px_sets[c[2]] or {}) do
                            get_px_name(g)
                        end
                    else
                        for _,g in ipairs(px_sets) do
                            get_px_name(g,2)
                        end
                        name,pxstat=(name or '')..c[2]
                    end
                    c[2]=name
                    c[2]=(color or '')..c[2]..'$NOR$'
                end
                local dop=info and tonumber(info.dop or info.gs and info.gs.dop or info.child_dop or info.parent_dop or 0) or 0
                local dop_pos=3
                c[dop_pos]=dop>0 and dop or nil
                local idx,counter=0,0
                local function add_column(value, is_compare)
                    idx=idx+1
                    row[idx]=value
                    if is_compare and tonumber(value) then 
                        counter=counter+1
                    end
                end
                
                for j=1,len do
                    local is_compare=j>dop_pos and j<skew_aas_index
                    add_column(c[j],is_compare)
                    local s=skew_list[j][1]
                    if s then
                        local val
                        if dop>0 and c[j] then
                            val=tonumber(info[s])
                            if val then
                                if total_skews[id] and (total_skews[id].n[j] or dop)<dop then
                                    val=math.round((val-total_skews[id][j])/math.max(1,dop-total_skews[id].n[j]),4)
                                else
                                    val=math.round((val-c[j])/math.max(1,dop-1),4)
                                end
                                if is_compare then
                                    if math.abs(c[j]-val)<thresholds.skew_min_diff then
                                        row[idx],val=nil
                                        counter=counter-1
                                    elseif dop==1 and px_alloc<2 and math.round(val)==0 then
                                        row[idx],val=nil
                                        counter=counter-1
                                    elseif val~=0 then
                                        local pct=c[j]/val
                                        if pct>thresholds.skew_rate and pct<1/thresholds.skew_rate then
                                            row[idx],val=nil
                                            counter=counter-1
                                        end
                                    end
                                end
                            end
                        end
                        add_column(val,is_compare)
                    end
                    add_column('|')
                end
                if counter>0 then
                    rows[#rows+1]=row
                    attrs.lines[id][6]=attrs.lines[id][6] or 'Yes'
                    if pxstat then pxstat[sql_start_idx]='Yes' end
                    if slaves then slaves[sql_start_idx]='$PROMPTCOLOR$Yes$NOR$$UDL$' end
                end
            end
            
            if #rows>1 then skew_outputs=rows end
        end
    end  

    local function print_report()
        pr('\n')
        pr(grid.merge({report_header,'|',{binds,'-',iostat}},'plain'))

        if #sqlstat<3 then
            env.var.define_column('Proc','noprint')
        end

        calc_skews()
        if sqlstat then
            if first_start and first_start> thresholds.sqlstat_warm.from_start[2] then
                sqlstat[2][from_start_idx]=string.to_ansi(first_start,'$HIR$','$NOR$')
            else
                sqlstat[2][from_start_idx]=first_start
            end
            pr(grid.merge({sqlstat},'plain'))
            env.var.define_column('Proc','clear')
        end

        local summary=print_header('Execution Plan Notes & Summary',false)
        if summary then
            summary.colsep='|'
            pr(grid.merge({summary},'plain'))
        end

        if line_events then 
            pr(grid.merge(line_events,'plain')) 
        end

        if lines and #lines>0 then
            table.insert(lines,1,{'Id','Ord','|','PX','DoP','Skew','|','Clock','Pct','|','Resp',clock_diffs==0 and 'AAS1' or 'AAS',
                                  '|','Id<0%','CPU%','Wait%','SQL%','IMQ%',
                                  '|','Top Event','AAS%','|','Operation','|','Object Name','|','Pred','|','Proj','|',
                                  'Distrib|Partition','|',--'Est|Cost',
                                  'Start|Count','Act|Rows','Est|Rows','Est|I/O','|',
                                  'Active|Clock','From|Start','1st|Row','From|End','|','Max|Mem','Max|Temp','|',
                                  'IM|DS','Inter|Connc','Read|Reqs','Avg|Read','Write|Reqs','Avg|Write','|',
                                  'Elig|Bytes','Return|Bytes','Saved|Bytes','Flash|Cache','Slow|Meta','Offload|Effi(%)','|',
                                  'Object|Alias','|','Query|Block'})
            
            lines.topic='Execution Plan Lines'
            lines.footprint='$HIB$[ '..(lines.status and (lines.status..' | ') or '')..'Pred: A=Access-cols, F=Filter-cols | Proj: B=Proj-avg-bytes, C=Proj-cols, K=Keys, R=Proj-rowsets ]$NOR$'
            pr(grid.merge({lines},'plain'))
            env.set.set('colsep','default')
        end
        
        if skew_outputs then
            env.var.define_column('id','break')
            pr(grid.merge({skew_outputs},'plain'))
            env.var.define_column('id','clear')
        end

        print_suffix(preds,qbs,qb_transforms,outlines,pr,xid)
    end
    print_report()
    text=table.concat(text,'\n')..'\n'
    if seq and sql_id then
        file=file..'_'..sql_id
    end
    print("\nSQL Monitor report in text  written to "..env.save_data(file..'.txt',text:strip_ansi()))
    print("SQL Monitor report in color written to "..env.save_data(file..'.ans',text:convert_ansi()))
    if seq then
        if sqlstat[2] then 
            sqlstat[2][1]=tostring(seq):lpad(3)..': '..sql_id
            --table.insert(sqlstat[2][1],1,seq)
        end
        if seq==1 then
            sqlstat[1][1]="SQL Id"
            --table.insert(sqlstat[1][1],1,"#")
            return {sqlstat[1],sqlstat[2]}
        else
            return sqlstat[2]
        end
    end
end

local sqldetail_pattern='<report [^%>]+>%s*<report_id><?[^<]*/orarep/sql_detail.-</sql_details>%s*</report>'
function unwrap.analyze_sqldetail(text,file,seq)
    local content,sql_id=handler:new()
    local parser =xml2lua.parser(content)
    local xml,hd,db_version,start_clock
    local xml=text:match(sqldetail_pattern)
    local sec2num=env.var.format_function("smhd2")
    env.var.define_column('aas,duration','for','smhd2')
    env.var.define_column("pct,aas%",'for','pct2')
    if not xml then
        xml=text:match('<sql_details>.-</sql_details>')
        if not xml then return end
    end

    --handle line-split of SQL fulltext
    load_xml(parser,xml)
    if content.root.report then
        content=content.root.report
        hd=content.sql_details
    else
        hd=content.root.sql_details
        content={}
    end

    text,file={},file:gsub('%.[^\\/%.]+$','')..'_sqld'..(seq and ('_'..seq) or '')
    local print_grid=env.printer.print_grid
    local function pr(msg,shadow)
        --store rowset instead of screen output to avoid line chopping
        if type(shadow)=='table' then
            shadow=grid.format_output(shadow)
        end

        text[#text+1]=type(shadow)=='string' and shadow or msg
        if not seq then
            if type(shadow)=='string' then
                print_grid(msg)
            else
                print(msg)
            end
        end
    end

    local titles={{},{}}
    local function add_header(n,v)
        local idx=#titles[1]+1
        titles[1][idx],titles[2][idx]=(n:gsub('"','')),tonumber(v) or v
    end

    local function title(msg)
        pr('\n'..msg..':')
        pr(string.rep('=',#msg:strip_ansi()+1))
    end

    pr('$COMMANDCOLOR$'..string.rep("=",120)..'$NOR$')
    if hd.sql_attributes.text and hd.sql_attributes.text[1] and hd.sql_attributes.sql_id then
        load_sql_text(hd.sql_attributes.text[1],pr,title,hd.sql_attributes.sql_id)
    end

    local function detail_report_parameters()
        local names,cnt={},0
        for _,n in ipairs{'db_version','timezone_offset','cpu_cores','hyperthread'} do
            if content._attr and content._attr[n] then
                add_header(n,content._attr[n])
                cnt=cnt+1
                names[n]=1
            end
        end
        for _,params in pairs{content.report_parameters,content.target and content.target._attr or nil,hd.sql_attributes} do
            if type(params) =='table' then
                for n,v in pairs(params) do
                    if not names[n] and type(v)~="table" then
                        names[n]=v
                        if n=='sql_id' then 
                            sql_id=v
                            file=file..'_'..sql_id
                        end
                        add_header(n,v)
                        cnt=cnt+1
                    end
                end
            end
        end
        if cnt>0 then
            titles.topic='SQL DETAIL REPORT PARAMETERS'
            titles.pivot,titles.pivotsort=1,'off'
            pr(grid.merge({titles},'plain'))
        end
    end
    detail_report_parameters()

    local function detail_activity_histogram()
        local names={}
        local rows={}
        local aas=0
        for _,bucket in pair(hd.activity_histogram and hd.activity_histogram.bucket) do
            for _,e in pair(bucket.activity) do
                local att=e._attr
                local key=table.concat({att.plan_hash_value or att.rpi or (att.other_activity and 'Other Activity') or '',att.event or (att.class and 'ON CPU') or ''},'\1')
                local row=names[key]
                if not row then 
                    row=key:split('\1')
                    names[key]=row
                    rows[#rows+1]=row
                end
                row[3]=(row[3] or 0)+1
                row[4]=(row[4] or 0)+tonumber(e[1])

                aas=aas+tonumber(e[1])
            end
        end
        if #rows>1 then
            rows.topic="Stats ("..sec2num(aas)..')'
            table.sort(rows,function(a,b) return a[4]>b[4] end)
            for _,row in ipairs(rows) do
                row[5]=math.round(row[4]/aas,4)
            end
            table.insert(rows,1,{'Plan Hash/Other','Event/Class','Buckets','AAS','AAS%'})

            local attr=hd.activity_histogram._attr
            local infos={{'Attribute','Value'},topic='Info'}
            local idx=1
            for k,v in pairs(hd.activity_histogram._attr) do
                idx=idx+1
                infos[idx]={k,tonumber(v) and math.round(tonumber(v),2) or v}
            end
            title('$PROMPTCOLOR$Activity Histogram$NOR$')
            pr(grid.merge({rows,'|',infos},'plain'))
        end
    end
    detail_activity_histogram()

    local function detail_top_activity()
        local dims,dim={},{}
        for i,d in pair(hd.top_activity and hd.top_activity.dim) do
            local id=d._attr.id
            if id and d.top_members and d.top_members.member then
                local row=id:split(',')
                if id:find('session_serial#',1,true) and #row<=3 then
                    row={id:find('blocking',1,true) and 'Blocking_Session#' or 'Session#'}
                end
                local cols=#row
                row[cols+1]='AAS'
                local rows={row}
                local aas=0

                for _,m in pair(d.top_members.member) do
                    row=m._attr.id:split(',')
                    if cols==1 and id:find('session_serial#',1,true) then
                        if #row<=2 then
                            row={m._attr.id}
                        else
                            row={row[2]..','..row[3]..',@'..row[1]}
                        end
                    end
                    for j=1,cols do 
                        row[j]=tonumber(row[j]) or row[j] or '' 
                    end
                    row[cols+1]=tonumber(m._attr.count)
                    rows[#rows+1]=row
                    aas=aas+row[cols+1]
                end
                if #rows>2 then rows.footprint=sec2num(aas) end
                if id:find('plan_hash',1,true) then
                    rows.seq=1
                elseif id:find('sql_id',1,true) then
                    rows.seq=2
                else
                    rows.seq=10
                end
                dim[#dim+1]=rows
            end
        end
        if #dim>0 then
            table.sort(dim,function(a,b)
                if a.seq~=b.seq then
                    return a.seq<b.seq
                end
                return #a<#b 
            end)
            
            title("$PROMPTCOLOR$TOP ACTIVITIES$NOR$")
            for i,row in ipairs(dim) do
                dims[#dims+1]=row
                if math.fmod(i,3)==0 then
                    pr(grid.merge(dims,'plain'))
                    dims={}
                else
                    dims[#dims+1]='|'
                end
            end
            if #dims>0 then 
                dims[#dims]=nil
                pr(grid.merge(dims,'plain'))
            end
        end
    end

    detail_top_activity()

    local function detail_spm()
        local header={'Type','Name'}
        local rows={header}

        for _,profs in pairs{hd.sql_profiles and hd.sql_profiles.sql_profile,
                             hd.sql_plan_baselines and hd.sql_plan_baselines.sql_plan_baseline,
                             hd.sql_patches and hd.sql_patches.sql_patch} do
            for _,prof in pair(profs) do
                if prof.info_group then
                    local row={prof.info_group._attr.name,prof._attr.name}
                    for _,info in pair(prof.info_group.info) do
                        local n=info._attr.name
                        local idx=header[n]
                        if not idx then
                            idx=#header+1
                            header[n],header[idx]=idx,n
                        end
                        row[idx]=tonumber(info[1]) or info[1]
                    end
                    rows[#rows+1]=row
                end
            end
        end
        if #rows>1 then
            title("$PROMPTCOLOR$SQL Profiles/SPM/Patches$NOR$")
            pr(grid.merge({rows},'plain'))
        end
    end
    detail_spm()

    local function detail_plan_summary()
        local names,idx={'PLAN HASH VALUE'},1
        local header,rows,execs={'Stats'},{},{}
        local info_head={'Plan Hash'}
        local infos={topic='Execution Plan List',info_head}
        for i,p in pair(hd.sql_plans and hd.sql_plans.sql_plan) do
            local phv=p._attr.plan_hash_value
            for _,grp in pair(p.info_group) do
                local row={phv}
                for _,info in pair(grp.info) do
                    local n,v=info._attr.name,info[1]
                    local idx=info_head[n]
                    if not idx then
                        idx=#info_head+1
                        info_head[n],info_head[idx]=idx,n
                    end
                    row[idx]=v
                end
                infos[#infos+1]=row
            end

            local stats={['PLAN HASH VALUE']=''..phv}
            for _,p1 in pairs{p,p.sql_plan_statistics_history} do
                for _,p2 in pair(p1 and p1.stats) do
                    local exec=0
                    for j,s in pair(p2 and p2.stat) do
                        local n=s._attr.name
                        local v=tonumber(s[1])
                        if n and v then
                            if n:find('_time',1,true) then 
                                v=v*1e6
                            end
                            if v>0 and (n=='parse_calls' and exec==0 or n=='executions') then
                                exec=v
                            end
                            stats[n]=(stats[n] or 0) + v
                            if not names[n] then
                                idx=idx+1
                                names[n],names[idx]=0,n
                                if n:find('_time',1,true) then 
                                    env.var.define_column(n,'for','usmhd2')
                                elseif n:find('_mem',1,true) or n:find('_bytes') then
                                    env.var.define_column(n,'for','kmg2')
                                else
                                    env.var.define_column(n,'for','tmb2')
                                end
                            end
                            names[n]=names[n]+v
                        end
                    end
                    execs[i]=(execs[i] or 0) + exec
                end
            end
            rows[#rows+1]=stats
        end
        local total,avg={pivot=#rows,pivotsort='head',topic='Plan Stats for All Executions',names},{pivot=#rows,pivotsort='head',topic='Plan Stats for Per Execution',names}
        
        for i,stats in ipairs(rows) do
            local row1,row2={},{}
            if execs[i] then
                local exec=execs[i]>0 and execs[i] or 1
                for idx,n in ipairs(names) do
                    local v=stats[n]
                    row1[idx]=v
                    if v and idx>1 and n~='executions' and n~='sharable_mem' then
                        row2[idx]=math.round(v/exec,2)
                    else
                        row2[idx]=v
                    end
                end
                total[#total+1]=row1
                avg[#avg+1]=row2
            end
        end

        header={'Plan Hash','SQL Exec ID','SQL Exec Start','|'}
        local sqlmons={topic='SQL Monitor List',header}
        local function set_mon_row(mon,row)
            if type(mon)~='table' then return end
            for n,v in pairs(mon) do
                if type(n)=='number' then
                    if type(v)~='table' then return end
                    n,v=v._attr.name,v[1]
                end
                if n=='type' then return end
                if type(v)=='table' then
                    set_mon_row(v,row)
                else
                    local idx=header[n]
                    local v1=tonumber(v)
                    if not idx then
                        idx=#header+1
                        header[n],header[idx]=idx,n
                    end
                    if v1 and n:find('_time',1,true) then
                        env.var.define_column(n,'for','usmhd2')
                    elseif v1 and n:find('_byte',1,true) then
                        env.var.define_column(n,'for','kmg2')
                    elseif v1 and n:find('_reqs',1,true) then
                        env.var.define_column(n,'for','tmb2')
                    end
                    row[idx]=v1 or v
                end
            end
        end
        for _,mon in pair(hd.report and hd.report.sql_monitor_list_report and hd.report.sql_monitor_list_report.sql) do
            local row={tostring(mon.plan_hash) or '',mon._attr.sql_exec_id or '',mon._attr.sql_exec_start or '','|'}
            set_mon_row(mon.stats,row)
            mon._attr,mon.plan_hash,mon.stats=nil
            set_mon_row(mon,row)
            sqlmons[#sqlmons+1]=row
        end
        if #infos<2 then return end
        title("$PROMPTCOLOR$EXECUTION PLAN SUMMARY$NOR$")
        pr(grid.merge({infos},'plain'))
        if #sqlmons>1 then
            pr(grid.merge({sqlmons},'plain'))
        end
        pr(grid.merge({avg,'|',total},'plain'))
    end
    detail_plan_summary()

    local line_aas={}
    local function detail_plan_activity()
        for i,act in pair(hd.plan_activities and hd.plan_activities.activities) do
            local phv=act._attr.plan_hash_value
            local aas=tonumber(act.plan_activity._attr.count)
            local events={}
            local lines={}
            for j,op in pair(act.plan_line_activity and act.plan_line_activity.operation) do
                local attr=op._attr
                local cnt=tonumber(attr.count)
                local id=tonumber(attr.id or '0')
                if not lines[id] then
                    lines[id]={id,(attr.name or '')..' '..(attr.options or ''),'|',0,0,'|',0,''}
                end
                scan_events(op,lines[id],4)
            end
            local top_ids={topic='Top Plan Lines (Total: '..sec2num(aas)..')',{'Id','Operation','|','AAS','Pct','|','Top Event','AAS%'}}
            for id,line in pairs(lines) do
                line[5]=math.round(line[4]/aas,4)
                line[7],line[8]=get_top_events(line.events,line[4])
                for event,cnt in pairs(line.events) do
                    if not events[event] then 
                        events[event]={event,'|',0,0,'|','',ids={}} 
                    end
                    events[event][3]=events[event][3]+cnt
                    events[event].ids[id]=cnt
                end
                top_ids[#top_ids+1]=line
            end
            local top_events={topic='Top Events (Total: '..sec2num(aas)..')',{'Event','|','AAS','Pct','|','Top Ids'}}
            for event,line in pairs(events) do
                line[4]=math.round(line[3]/aas,4)
                line[6]=get_top_events(line.ids,line[3],nil,5)
                top_events[#top_events+1]=line
            end
            top_ids.max_rows=math.max(5,#top_events-1)
            grid.sort(top_ids,'-4',true)
            grid.sort(top_events,'-3',true)
            line_aas[phv]={lines=lines,top_ids=top_ids,top_events=top_events}
            
        end
    end
    detail_plan_activity()

    local function detail_plan_lines()
        local header={'Id','Ord','|','AAS','Pct','|','Top Event','AAS%','|','Operation','|','Object','|','Distrib','|','Pred','|','Est|Card','Est|Cost','IO|Cost','Avg|Bytes','|','Query|Block','|','Alias|Name'}
        local cols={}
        for c,v in ipairs(header) do
            if v:find('^%u') then
                cols[v:lower():gsub('[ %|]+','_')]=c
            end
        end

        for i,p in pair(hd.sql_plans and hd.sql_plans.sql_plan) do
            local phv=p._attr.plan_hash_value
            local rows,hier,hier_idx,tier,ids={header},{},0,{},{}
            local aas,envs,outlines,preds,qbs,qb_transforms,skps,binds={},{},{},{ids={}},{},{},{},{}
            local aas_func
            titles={{},{}}
            
            local plan_lines=p.plan and p.plan.operation or nil
            if not plan_lines then return end

            for _,cursor_binds in pair(p.cursor_binds and p.cursor_binds.binds) do
                binds[2]=cursor_binds
            end

            local sep='          EXECUTION PLAN HASH VALUE: '..phv..'          '
            pr('\n'..("="):rep(#sep:strip_ansi()+2))
            pr('|$REV$'..sep..'$NOR$|')
            pr(("="):rep(#sep:strip_ansi()+2))

            if line_aas[phv] then
                aas=line_aas[phv].lines
                pr(grid.merge({line_aas[phv].top_ids,'|',line_aas[phv].top_events},'plain'))
                line_aas[phv]=nil
            end

            table.sort(plan_lines,function(a,b) return tonumber(a._attr.id)<tonumber(b._attr.id) end)
            local id_fmt='%1s%'..#tostring(#plan_lines)..'s'
            for _,op in ipairs(plan_lines) do
                local attr=op._attr
                local id=tonumber(attr.id)
                local row={}
                local depth=tonumber(attr.depth) or 0
                local pos=tonumber(attr.pos)
                local qb,alias=op.qblock,strip_quote(op.object_alias)
                for c,v in ipairs(header) do
                    row[c]=v=='|' and v or ' '
                end
                local node={id=id,pos=pos,_cid={},depth=depth}
                if depth==0 then
                    hier[#hier+1]=node
                    hier.last=id
                else
                    local pid=tier[depth-1]
                    node._pid=pid.id
                    pid._cid[1+#pid._cid]=node
                    pid._cid.last=id
                end
                tier[depth],hier_idx=node,depth

                local object= op.object or (alias and ('$REV$'..alias:gsub('@.*',''):gsub('"','')..'$NOR$')) or op.node or ''
                row[cols.id]=id_fmt:format(' ',id)
                row[cols.operation]=(attr.name or '')..' '..(attr.options or '')
                row[cols.object]=(object:sub(1,1)==':' and '' or ' ')..object
                row[cols.est_card]=op.card
                row[cols.io_cost]=op.io_cost
                row[cols.est_cost]=op.cost
                row[cols.avg_bytes]=op.bytes and math.round(op.bytes/(op.card or 1)) or nil
                row[cols.query_block]=qb
                row[cols.alias_name]=alias
                process_qb(qbs,qb,alias,id,depth)
                if op.predicates then
                    row[cols.id]=id_fmt:format('*',id)
                    for k,v in pair(op.predicates) do
                        process_pred(preds,id,v._attr.type,v[1],op,op.object_alias)
                    end
                    row[cols.pred]=table.concat(op.pred,'')
                end

                row[cols.distrib]= p.distrib or op.partition and (
                    op.partition._attr.start==op.partition._attr.stop and op.partition._attr.start
                    or (op.partition._attr.start..' - '..op.partition._attr.stop)
                ) or nil
                
                if aas[id] then
                    row[cols.aas]=aas[id][4]
                    row[cols.pct]=aas[id][5]
                    row[cols.top_event]=aas[id][7]
                    row[cols.top_event+1]=aas[id][8]  
                end
                rows[#rows+1]=row
                ids[id]=row
                if op.other_xml then
                    binds[1]=op.other_xml.peeked_binds
                    parse_other_xml(op.other_xml,add_header,envs,outlines,qb_transforms,skps)
                end
            end

            local seq,ord=#rows,cols.ord
            local xid='%'..(#(tostring(seq)))..'d'
            local cids={}
            local function parse_hier(childs,color_idx,indent,prefix)
                local len=#childs
                if len>1 then 
                    table.sort(childs,function(a,b) 
                        if a.pos==b.pos then return a.id<b.id end
                        return a.pos<b.pos 
                    end) 
                end
                local ind=' '..indent..(prefix:find('$') and prefix:gsub('[|:]','+') or prefix)
                for i,node in ipairs(childs) do
                    seq=seq-1
                    node.seq=seq
                    local id=node.id
                    local row=ids[id]
                    row[ord]=seq
                    local cid=node._cid
                    local skp=tonumber(skps[id]) or 0
                    if skp>0 then 
                        row[cols.operation]='$GRY$'..row[cols.operation]..'$NOR'
                        row[1]='-'
                    end
                    cids[id]=cid
                    if #cid>0 then
                        local sub_color,sub_ind,sub_prefix=color_idx
                        if childs.last~=id then
                            sub_ind=indent..prefix
                        else
                            sub_ind=indent..(prefix=='' and '' or ' ')
                        end
                        if #cid>1 then
                            if skp>0 then
                                sub_prefix='$GRY:$NOR$'
                            else
                                sub_color=color_idx+1
                                local color=colors[math.fmod(sub_color,#colors)+1]
                                row[cols.operation]=ind..color..row[cols.operation]..'$NOR$'
                                sub_prefix=color..'|$NOR$'
                            end
                        else
                            row[cols.operation]=ind..row[cols.operation]
                            sub_prefix=' '
                        end
                        parse_hier(cid,sub_color,sub_ind,sub_prefix)
                    else
                        row[cols.operation]=ind..row[cols.operation]
                    end
                end
            end
            parse_hier(hier,-1,'','')
            local p,c,n
            local pad=math.max(3,#tostring(#rows))
            for i=2,#rows do
                c=rows[i][ord]
                n=rows[i+1] and rows[i+1][ord]
                local id=tonumber(rows[i][cols.id]:match('%d+'))
                if p and n and n==c-1 and #cids[id]>0 then
                    if p==c+1 then
                        c='^'
                    elseif type(p)=='string' then
                        c=':'
                    end
                end
                rows[i][ord]=tostring(c):lpad(pad)
                p=c
            end

            var.define_column("Est|Card,Est|Cost,IO|Cost",'for','tmb2')
            pr(grid.merge({titles},'plain'))
            if aas_func then aas_func() end
            pr(grid.merge({rows},'plain'))
            binds=load_binds(binds)
            if binds then
                pr(grid.merge({binds},'plain'))
            end
            print_suffix(preds,qbs,qb_transforms,outlines,pr,xid)          
         end
    end
    detail_plan_lines()

    for phv,aas in pairs(line_aas) do
        local sep='          EXECUTION PLAN HASH VALUE: '..phv..'          '
        pr('\n'..("="):rep(#sep:strip_ansi()+2))
        pr('|$REV$'..sep..'$NOR$|')
        pr(("="):rep(#sep:strip_ansi()+2))
        pr(grid.merge({aas.top_ids,'|',aas.top_events},'plain'))
    end

    text=table.concat(text,'\n')..'\n'
    print("\nSQL Detail report in text  written to "..env.save_data(file..'.txt',text:strip_ansi()))
    print("SQL Detail report in color written to "..env.save_data(file..'.ans',text:convert_ansi()))
end

local function unwrap_plsql(obj,rows,file)
    local header=table.remove(rows,1)[5]
    local txt,result,cache='','',{}
    for index,piece in ipairs(rows) do
        cache[#cache+1]=piece[1]
        if piece[5] then header=piece[5] end
        if piece[3]==piece[4] then
            txt,cache=table.concat(cache,''),{};
            if tonumber(piece[2])==1 then
                local cnt,lines=txt:match('\r?\n[0-9a-f]+ ([0-9a-f]+)\r?\n(.*)')
                env.checkerr(lines,'Cannot find matched text!')
                txt=decode_base64_package(lines:gsub('[\n\r]+',''))
            end
            txt=txt:sub(1,-100)..(txt:sub(-99):gsub('%s*;[^;]*$',';'))
            result=result..(header or 'CREATE OR REPLACE ')..txt..'\n/\n\n'
        end
    end    
    env.checkerr(result~="",'Cannot find targt object: '..obj)
    print("Result written to file "..env.write_cache(file,result))
end

function unwrap.unwrap(obj,ext,prefix)
    env.checkhelp(obj)
    local filename,org_ext=obj
    local typ1,f=os.exists(obj)
    if ext=='.' then 
        ext=nil
    elseif ext and ext:lower()=='18c' then
        ext,prefix=nil,'18c'
    end
    prefix=prefix or ''
    if typ1 then
        if typ1~="file" then return end
        obj=f
        filename,org_ext=f:match("(.*)%.(.-)$")
        if filename then
            filename=filename.."_unwrap."..org_ext
        else
            filename=f..'.unwrap'
        end

        f=io.open(f)
        env.checkerr(f,"Cannot open file "..obj)
        local found,stack,org,repidx=false,{},{}
        local is_wrap,is_plsql=false
        local line_idx,plsql_stack,typ,top_obj,start_idx=0
        local plsql_start='^%s*[cC][rR][eE][aA][tT][eE] .-(['..object_full_pattern..']+) (['..object_full_pattern..']+)'
        local plsql_pattern=plsql_start..' *$'
        local wrap_pattern=plsql_start..' +wrapped *$'
        for line in f:lines() do
            if not found and not is_wrap then
                local name
                if not is_plsql or not line_idx then
                    is_wrap,typ,name=1,line:match(wrap_pattern)
                    if not typ then
                        is_wrap,typ,name=0,line:match(plsql_pattern)
                    end
                    if typ and not (org_ext or ''):lower():find('htm',1,true) then
                        if name:upper()=='IS' or name:upper()=='AS' then name=typ end
                        top_obj=name:gsub('"','')
                        is_plsql=true
                        line_idx=0
                        plsql_stack=org
                        start_idx=#plsql_stack+1
                    else
                        is_wrap=false
                    end
                end
            end
            if is_plsql then
                if  line:match('^ */ *$') then
                    if start_idx then
                        for i=start_idx,#plsql_stack do
                            plsql_stack[i][4]=line_idx
                        end
                        start_idx=nil
                    end
                    line_idx=nil
                    is_wrap=false
                else
                    if line_idx then line_idx=line_idx+1 end
                    
                    plsql_stack[#plsql_stack+1]={line..'\n',is_wrap,line_idx}
                    if line_idx==1 then
                        plsql_stack[#plsql_stack][5]=line:gsub(' +wrapped *$','')
                    end
                end
            else
                local piece=line:match("^%s*([%w%+%/%=]+)%s*$")
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
                        is_wrap=true
                    end
                else
                    if line:match('encode=".-"') and line:match('compress=".-"') then
                        org[#org+1]=line:gsub('encode=".-"',''):gsub('compress=".-"','')
                    else
                        org[#org+1]=line
                    end
                end
            end
        end
        f:close()
        if is_plsql==true then
            if start_idx then
                for i=start_idx,line_idx do
                    plsql_stack[i][4]=line_idx
                end
                start_idx=nil
            end
            return unwrap_plsql(top_obj,plsql_stack,top_obj..'.'..(ext or 'sql'))
        end
        if #stack>0 then
            is_wrap=true
            org[#org+1]=loader:Base64ZlibToText({table.concat(stack,'')}) 
        end
        local text=table.concat(org,'\n')
        
        local function load_report(func,text,obj,ext)
            local done,err=pcall(func,text,obj,ext)
            if not done then
                env.warn(err)
            else
                return err
            end
        end

        for _,func in ipairs{{sqldetail_pattern,unwrap.analyze_sqldetail},
                             {sqlmon_pattern,unwrap.analyze_sqlmon}} do
            local sql_list={}
            local _,cnt=text:gsub(func[1],function(s) sql_list[#sql_list+1]=s;return '' end)
            if cnt>1 then
                local prefix=obj:gsub('[^\\/%w][^\\/]+$','')
                local result
                for i,sqlmon in ipairs(sql_list) do
                    local row=load_report(func[2],sqlmon,prefix,i)
                    if not result then 
                        result=row
                    else
                        result[#result+1]=row
                    end
                end
                grid.merge({result},true)
            else
                load_report(func[2],text,obj)
            end
        end

        if is_wrap then
            print("Decoded Base64 written to file "..env.save_data(filename,text))
        end
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
        local rows=db.resultset:rows(rs,-1)
        db.resultset:close(rs)
        unwrap_plsql(obj,rows,prefix..filename..'.'..(ext or 'sql'))
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
    env.set_command(nil,"unwrap",[[
        Decrypt wrapped object or compressed Active Report, type 'help @@NAME' for more detail. Usage: @@NAME {[<owner>.]<object_name> | <sql monitor filename>}
        
        1) @@NAME [<owner>.]<object_name> :  Unwrap a specific function/procedure/package/trigger/type/java_class
        2) @@NAME <schema_name>           :  Unwrap all functions/procedures/packages/triggers/types of a schema
        3) @@NAME <sql file>              :  Unwrap the file that stores the encrypted PL/SQL code
        4) @@NAME <SQL Monitor File>      :  Decrypt the active SQL Monitor Report and analyze the content
        5) @@NAME <Perfhub file>          :  Decrypt the Performance Hub Active Report and analyze all its active SQL Monitor reports
        6) @@NAME <file>                  :  Decrypt other kinds of file that have Based64+zlib compressed content, such as the SQL detail report.
    ]],
    unwrap.unwrap,false,4)
end

return unwrap