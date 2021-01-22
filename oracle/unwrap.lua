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

function unwrap.analyze_sqlmon(text,file)
    local content=handler:new()
    local parser =xml2lua.parser(content)
    local xml,hd,db_version,start_clock
    local xml=text:match('<report [^%>]+>%s*<report_id><?[^<]*</report_id>%s*<sql_monitor_report .-</sql_monitor_report>%s*</report>')
    if not xml then
        xml=text:match('<sql_monitor_report .-</sql_monitor_report>')
        if not xml then return end
    end
    --handle line-split of SQL fulltext
    xml=xml:gsub('([^\n\r]+)(\r?\n\r?)(%S)',function(a,b,c)
            if #a<512 then return a..b..c end
            return a..c
        end)
    parser:parse(xml)
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
    local instance_id,session_id=tonumber(hd.target._attr.instance_id),tonumber(hd.target._attr.session_id)
    local colors={'$COMMANDCOLOR$','$PROMPTCOLOR$','$HIB$','$PROMPTSUBCOLOR$'}
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
    env.var.define_column('max_io_reqs,Est|Cost,Est|Rows,Act|Rows,Skew|Rows,Read|Reqs,Write|Reqs,Start|Count,Buff|Gets,Disk|Read,Direx|Write,Fetch|Count','for','tmb1')
    env.var.define_column('max_aas,max_cpu,max_waits,max_other_sql_count,max_imq_count,From|Start,From|End,Active|Clock,Resp|Time,Ref|AAS,ASH|AAS,CPU|AAS,Wait|AAS,IMQ|AAS,Other|SQL,resp,aas','for','smhd2')
    env.var.define_column('duration,bucket_duration,Wall|Time,Elap|Time','for','usmhd2')
    env.var.define_column('max_io_bytes,max_buffer_gets,I/O|Bytes,Mem|Bytes,Max|Mem,Temp|Bytes,Max|Temp,Inter|Connc,Avg|Read,Avg|Write,Unzip|Bytes,Elig|Bytes,Return|Bytes,Read|Bytes,Write|Bytes,Avg|Read,Avg|Write','for','kmg1')
    env.var.define_column('pct','for','pct')
    env.set.set('autohide','col')
    text,file={},file:gsub('%.[^\\/%.]+$','')
    
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

    local function pair(o)
        return ipairs(type(o)~='table' and {} or (type(o[1])=='table' or #o>1) and o or {o})
    end

    local function pr(msg,shadow)
        if type(shadow)=='table' then
            shadow=grid.format_output(shadow)
        end
        text[#text+1]=type(shadow)=='string' and shadow or msg
        print(msg)
    end

    local function title(msg)
        pr('\n'..msg..':')
        pr(string.rep('=',#msg+1))
    end

    local function strip_quote(str)
        if type(str)~='string' then return str end
        return str:gsub('"([%u%d_$#]+)"','%1')
    end

    local function insid(sid,inst_id,px_set)
        sid=(sid or session_id)..'@'..(tonumber(inst_id) or instance_id)
        if px_set then sid=sid..'#'..px_set end
        return sid
    end

    --sort the waits in desc
    local pct_fmt='%.1f%%'
    local function to_pct(a,b,c,quote)
        if b==0 then
            if c and c>0 then 
                b=c
            else
                return ''
            end
        end
        b=pct_fmt:format(100*a/b):gsub('%.0%%','%%')
        if b=='0%' then return '' end
        if quote~=false then
            return '('..b..')'
        else
            return ' '..b
        end
    end

    local function load_sql_text()
        local sql_text=hd.target.sql_fulltext
        if sql_text then
            title('SQL '..(hd.report_parameters.sql_id or hd.target._attr.sql_id))
            sql_text=type(sql_text)=='table' and sql_text[1] or sql_text
            if #sql_text>512 and not sql_text:sub(1,512):find('\n') then
                local width=console:getScreenWidth()-50
                local len,result,pos,pos1,c,p=#sql_text,{},1
                local pt="[|'\"),%] =]"
                while true do
                    result[#result+1]=sql_text:sub(pos,pos+width-1)
                    pos=pos+width
                    pos1=pos
                    while true do
                        pos1=pos1+1
                        c=p or sql_text:sub(pos1,pos1)
                        p=sql_text:sub(pos1+1,pos1+1)
                        if c=='' or (c:find(pt) and not p:find(pt)) then
                            result[#result+1]=sql_text:sub(pos,pos1)..'\n'
                            pos=pos1+1
                            break
                        end
                    end
                    if len<pos then break end
                end
                sql_text=table.concat(result,'')
            end
            pr(grid.tostring({{sql_text}},false,'',''))
        end
    end
    load_sql_text()

    local iostat
    local function load_iostats()
        stats=hd.stattype
        local map={}
        local title={_seqs={}}
        local interval=1
        if stats then
            for k,v in pair(stats.stat_info.stat) do
                local att=v._attr
                map[att.id]={name=att.name,factor=tonumber(att.factor),unit=att.unit}
                title._seqs[att.name],title[tonumber(att.id)]=tonumber(att.id),att.name
            end
            interval=tonumber(stats.buckets._attr.bucket_interval) or interval
            stats=stats.buckets.bucket
        elseif hd.metrics then
            stats=hd.metrics.bucket
            interval=tonumber(hd.metrics._attr.bucket_interval) or interval
        end
        if not stats then return end
        local rows={}  --name,avg,mid,min,max,total,buckets
        local avgs={{'reads','read_kb','Avg Read Bytes'},{'writes','write_kb','Avg Write Bytes'}}
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
            for i,v in ipairs(avgs) do
                local r,r1=title._seqs[v[1]],title._seqs[v[2]]
                if r and r1 and rows[r] and rows[r1] then
                    local v1,v2=rows[r].values[bucket],rows[r1].values[bucket]
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
            interc_kb='Physical Bytes',
            cache_kb='Logical  Bytes'
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
        px_in_memory='px_im',
        px_in_memory_imc='px_imc',
        derived_cpu_dop='cpu_dop',
        derived_io_dop='io_dop'
    }
    local time_fmt='%d+/%d+/%d+'
    local function add_header(k,v,display)
        if not v or v:trim()=='' or titles[0][k] then return end
        titles[0][k]=v
        if k=='duration' then
            v=tonumber(v)*1e6
            if not dur2 then dur2=v end
        elseif k=='bucket_duration' then
            v=tonumber(v)*1e6
            if not dur1 then dur1=v end
        elseif k=='sql_exec_start' then
            start_clock=time2num(v)
        end
        k=default_titles[k] or k
        if type(v)=='string' then v=v:sub(1,25) end
        titles[#titles+1]={k,v,tostring(v):find(time_fmt) and 91 or
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
                    --if (k:find('elapsed_time',1,true) or k:find('cpu_time',1,true)) or v:find('.',1,true) then v1=v1*3600 end
                    --v=''..v1*1e6
                    k='report_'..k
                    --env.var.define_column(k,'for','usmhd2')
                end
                if type(v)=='string' then add_header(k,v) end
            end
        end
        for k,v in pairs(hd.report_parameters or {}) do
            if type(v)=='string' then add_header(k,v) end
        end
        for k,v in pairs((hd.activity_detail or hd.activity_sampled or {})._attr or {}) do
            if type(v)=='string' then add_header(k,v) end
        end
        for k,v in pairs(hd.target._attr or {}) do
            if type(v)=='string' then add_header(k,v) end
        end
        for k,v in pairs(hd.target or {}) do
            if type(v)=='string' and k~='sql_fulltext' then 
                add_header(k,v) 
            elseif k=='rminfo' then
                add_header(k,v._attr.rmcg) 
            end
        end
        
        report_header=print_header("Summary",false)
        report_header.pivot,report_header.pivotsort=1,'off'
        if hd.plan_monitor then
            for k,v in pairs(hd.plan_monitor._attr or {}) do
                add_header(k,v)
            end
        end
    end
    load_header()

    local skews={ids={},sids={}}
    local skew_list={
        [1]={nil,'Id'},
        [2]={nil,'Skew|Proc'},
        [3]={'cardinality','Skew|Rows','Ref|Rows','max_card'},
        [4]={'starts','Start|Count','Ref|Starts','max_starts','execs'},
        [5]={'io_inter_bytes','Inter|Connc','Ref|Inter','max_io_inter_bytes','ikb',1024},
        [6]={'read_reqs','Read|Reqs','Ref|Reads','max_read_reqs','rreqs'},
        [7]={'read_bytes','Read|Bytes','Ref|rBytes','max_read_bytes','rkb',1024},
        [8]={'write_reqs','Write|Reqs','Ref|Writes','max_write_reqs','wreqs'},
        [9]={'write_bytes','Write|Bytes','Ref|wBytes','max_write_bytes','wkb',1024},
        [10]={'max_memory','Mem|Bytes','Ref|Mem','min_max_mem','mem',1024},
        [11]={'max_temp','Ref|Temp','max_max_temp','temp',1024},
        [12]={'aas','ASH|AAS','Ref|AAS'},
        [13]={nil,'Top|Event'}
    }
    local skew_aas_index,skew_event_index
    local max_skews,detail_skews={},{}
    local function add_skew_line(id,sid,inst_id,idx,value,multiplex,is_append)
        id,sid=tonumber(id),insid(sid,inst_id)
        if not skews.ids[id] then skews.ids[id]={} end
        local row=skews.ids[id][sid]
        if not row then
            row={id,sid,[skew_event_index+1]={}}
            skews.sids[sid],skews.ids[id][sid],skews[#skews+1]=row,row,row
        end
        value=tonumber(value)*(multiplex or 1)
        if value<=0 then return end
        if is_append then
            row[idx]=(row[idx] or 0)+value
        else
            row[idx]=math.max(row[idx] or 0,value)
        end
    end

    local function load_skew()
        skew_event_index=#skew_list
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
                    add_skew_line(id,sid,inst_id,3,l[1])
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
        {'cell_offload_efficiency','Eff|Rate'},
        {'cell_offload_efficiency2','Eff2|Rate'},
        seqs={}
    }
    
    local sqlstat={topic='SQL and Process Summary',
                   {'Proc','Wall|Time','From|Start','ASH|AAS','CPU|AAS','Wait|AAS','IMQ|AAS','Other|SQL','Is|Skew'},
                   {'Main',dur1 or dur2,nil,nil,nil,nil,nil,nil,#skews>0 and 'Yes' or nil}}
    local aas_idx,sql_start_idx=4,#sqlstat[1]

    local px_sets={}
    local function gs_color(g,s)
        return colors[math.fmod((s-1)*2+g-1,#colors)+1]
    end

    local function load_sqlstats()
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
            if type(value)=='number' and value>10 and type(max_stats)=='table' and max_stats[name] and max_stats.childs>=4 and value>=max_stats[name] then
                return '$HIR$'..value..'$NOR$'
            end
            return value
        end
        for k,v in pair(hd.activity_sampled and hd.activity_sampled.activity or nil) do
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
        for k,v in ipairs(statset) do
            local idx=k+sql_start_idx
            statset.seqs[v[1]]=idx
            sqlstat[1][idx]=v[2]
            if not sqlstat.timer_start and v[1]:find('_time$') then
                sqlstat.timer_start=idx
            elseif v[1]:find('_time$') then
                sqlstat.timer_end=idx
            end
        end

        local function add_sqlstat(row,stat)
            for k,v in pair(stat) do
                local att=v._attr
                if att and att.name and statset.seqs[att.name] and v[1]~='0' then
                    row[statset.seqs[att.name]]=tonumber(v[1])
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
            for k,s in pair(sessions.session) do
                local px_set,px_name,skew,color1,color2=nil,nil,nil,'',''
                local att=s._attr
                local pname=insid(att.process_name=='PX Coordinator' and 'Coord' or att.process_name,att.inst_id)
                local grp,set=tonumber(att.server_group),tonumber(att.server_set)
                local g
                if set then
                    px_set='G'..grp..'S'..set..' - '
                    color1,color2=gs_color(grp,set),'$NOR$'
                    pname=px_set..pname
                    px_name=insid(att.session_id,att.inst_id)
                    if not px_sets[px_name] then px_sets[px_name]={} end
                    g={g=grp,s=set,name=pname,set=px_set,color=color1}
                    px_sets[px_name][#px_sets[px_name]+1]=g
                    if not set_list[px_set] then
                        px_sets[#px_sets+1]=g
                        set_list[px_set]=1
                    end
                end
                
                if px_set and px_set==prev then
                    pname=pname:gsub('.',' ',#px_set-2)
                else
                    prev=px_set
                end
                att=s.activity_sampled and s.activity_sampled._attr or {}
                local start_at=get_attr(att,'first_sample_time');
                sqlstat[#sqlstat+1]={color1..pname..color2,
                                     get_attr(att,'duration',1e6,max_stats),
                                     start_at and time2num(start_at)-start_clock or nil,
                                     get_attr(att,'count',nil,max_stats),
                                     get_attr(att,'cpu_count',nil,max_stats),
                                     get_attr(att,'wait_count',nil,max_stats),
                                     get_attr(att,'imq_count',nil,max_stats),
                                     get_attr(att,'other_sql_count',nil,max_stats),
                                     skew and 'Yes' or nil}
                if g then g.data=sqlstat[#sqlstat] end
                add_sqlstat(sqlstat[#sqlstat],s.stats and s.stats.stat)
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
                                         get_attr(att,'duration',nil,max_stats),
                                         start_at and time2num(start_at)-start_clock or nil,
                                         get_attr(att,'count',nil,max_stats),
                                         get_attr(att,'cpu_count',nil,max_stats),
                                         get_attr(att,'wait_count',nil,max_stats),
                                         get_attr(att,'imq_count',nil,max_stats),
                                         get_attr(att,'other_sql_count',nil,max_stats),}
                    add_sqlstat(sqlstat[#sqlstat],s.stats and s.stats.stat)
                end
            end
        end
        local ic_idx,elig_idx,rtn_idx=statset.seqs.io_inter_bytes,statset.seqs.elig_bytes,statset.seqs.ret_bytes
        local io_idx={statset.seqs.read_reqs,statset.seqs.write_reqs}
        for i=2,#sqlstat do
            local stat=sqlstat[i]
            local intercc=0
            for j,idx in ipairs(io_idx) do
                if stat[idx] and stat[idx+1] then
                    intercc=intercc+stat[idx+1]
                    stat[idx]=math.round(stat[idx+1]/stat[idx],1)
                end
            end
            if stat[elig_idx] then 
                intercc=intercc-stat[elig_idx]
                if stat[rtn_idx] then intercc=intercc+stat[rtn_idx] end
             end
            if not stat[ic_idx] and intercc>0 then stat[ic_idx]=intercc end

            local ela=stat[sqlstat.timer_start]
            for j=sqlstat.timer_start+1,sqlstat.timer_end do
                if stat[j] then
                    stat[j]=to_pct(stat[j],ela,nil,false)
                end
            end
        end
    end
    load_sqlstats()

    local line_events
    local total_aas=tonumber(sqlstat[2][aas_idx]) or 1
    local function load_activity_detail()
        stats=hd.activity_detail
        if stats then stats=stats.bucket end
        local cl,ev,rt,as,pct,top,bk=1,2,4,5,6,7,8
        if stats then
            --process line level events:  report/sql_monitor_report/activity_detail/bucket
            local ids=attrs.top_event
            local function process_stats(s)
                local attr=s._attr
                local id=tonumber(attr.line) or 0
                if not ids[id] then ids[id]={-1,''} end
                if attr.plsql_id and attr.plsql_name and attr.plsql_name~='Unavailable' then plsqls[attr.plsql_id]=attr.plsql_name end
                local grp={
                    attr.class or attr.other_sql_class, --wait class
                    attr.event or --event
                        attr.sql and ('SQL: '..attr.sql) or 
                        attr.none_sql and ('SQL: '..attr.none_sql) or 
                        attr.plsql_id and ('PLSQL: '..(plsqls[attr.plsql_id] or attr.plsql_id)) or 
                        attr.top_sql_id and ('Top-SQL: ' .. attr.top_sql_id) or
                        attr.step or nil,
                    '|',
                    nil,nil,nil,nil,0, --buckets
                    lines={}
                }
                --group by class+event
                local stack=(grp[ev] or '')..','..(grp[cl] or '')
                if not stacks[stack] then
                    events[#events+1]=grp
                    stacks[stack]=#events
                end
                local e=events[stacks[stack]]
                e[bk]=e[bk]+1
                --rt(response time) and aas
                local values={[rt]=tonumber(attr.rt),[as]=tonumber(s[1])}
                if not e.lines[id] then e.lines[id]={} end
                for k,v in pairs(values) do
                    local i=k==rt and 1 or 2
                    e[k]=(e[k] or 0)+v
                    --aggregate line level events: {max,max_event,total_rt,total_aas}
                    ids[id][2+i]=(ids[id][2+i] or 0)+v
                    --aggregate line level events: {rt,aas}
                    e.lines[id][i]=(e.lines[id][i] or 0)+v
                end

                if attr.skew_count then
                    local sid=insid(attr.skew_sid,attr.skew_iid)
                    local aas=tonumber(attr.skew_count)
                    add_skew_line(id,attr.skew_sid,attr.skew_iid,skew_aas_index,aas,nil,true)
                    local skew=skews.ids[id][sid]
                    local event=grp[ev] or grp[cl]
                    skew[skew_event_index+1][event]=(skew[skew_event_index+1][event] or 0)+aas
                end
            end

            for k,v in pair(stats) do
                for k1,v1 in pair(v.activity) do 
                    process_stats(v1)
                end
            end
            
            table.sort(events,
                function(a,b)
                    for _,c in ipairs{a,b} do
                        if not c[top] then
                            local lines,l={},{}
                            for id,aas in pairs(c.lines) do
                                --aas: {rt,aas}
                                local v=aas[2]==0 and aas[1] or aas[2]
                                lines[#lines+1]={id,v}
                                --adjust line level max_event/aas
                                local line=ids[id]
                                if v and line[1]<v then
                                    line[1],line[2]=v,(a[2] or a[1] or '')..' '..to_pct(v,line[4],line[3])
                                end
                            end
                            table.sort(lines,function(o1,o2) return o1[2]>o2[2] end)
                            for i=1,math.min(5,#lines) do
                                l[i]=lines[i][1]..to_pct(lines[i][2],c[as],c[rt])
                            end
                            c[top]=table.concat(l,', ')
                            if c[as] then c[pct]=math.round(c[as]/total_aas,4) end
                        end
                    end

                    return (a[as] or 0)>(b[as] or 0) 
                end)
            table.insert(events,1,{'Class','Event','|','Resp','AAS','Pct','Top Lines','Buckets'})

            local top_lines={}
            for k,v in pairs(ids) do
                top_lines[#top_lines+1]={k,v[3],v[4],math.round(v[4]/total_aas,4),v[2]}
            end
            table.sort(top_lines,function(o1,o2) return o1[4]>o2[4] end)
            table.insert(top_lines,1,{'Id','Resp','AAS','Pct','Top Event'})
            for i=#top_lines,math.max(4,#events+1),-1 do
                top_lines[i]=nil
            end
            top_lines.topic,top_lines.colsep,events.topic='Top Lines','|','Wait Events'
            line_events={top_lines,'|',events}
        end
    end
    load_activity_detail()

    local outlines,preds={},{ids={}}
    local nid,xid=9999,0

    local seqs='%d%a#$_'
    local cp='"(['..seqs..']+)"'
    local function process_pred(id,type,pred,node,alias)
        if type:lower()~='proj' then
            preds[#preds+1]={tonumber(id),type:initcap(),strip_quote(pred)}
            preds.ids[id]=(preds.ids[id] or 0)+1
            if node then
                if not node.pred then node.pred={'',''} end
                local df='__DEFAULT__'
                local sets={[df]={0}}
                pred=(' '..pred..' '):gsub('([^'..seqs..'"%.])','%1%1')
                if alias then 
                    alias='"'..alias:gsub('@.*',''):gsub('"',''):escape()..'"'
                    pred=pred:gsub('([^%."])'..alias..'."','%1"')
                end
                pred=pred:gsub('([^%."])("['..seqs..'"%.]+")([^%."])',function(p,c,s)
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
            if keys then node.proj[2]='R'..keys..',' end
            c,keys=(pred..', '):gsub('], ','')
            if keys>0 then node.proj[3]='C'..keys..',' end
        end
    end

    local gs={list={},g=0,s=2}
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
                    if 'downgrade reason'==meta[mt._attr.id].name and reasons[mt[1]] then
                        process_pred(lid,'Other',reasons[mt[1]])
                    elseif "distribution method"==meta[mt._attr.id].name:lower() and dist_methods[mt[1]] then
                        attrs.dist_methods[lid]=dist_methods[mt[1]]
                    else
                        process_pred(lid,'Other',mt[1]:lpad(10)..' -> '..meta[mt._attr.id].desc)
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

        stats=hd.plan_monitor and hd.plan_monitor.operation or nil
        if not stats then 
            stats={}
            return
        end
        table.sort(stats,function(a,b) return tonumber(a._attr.id)<tonumber(b._attr.id) end)
        local lvs={}
        for n,p in ipairs(stats) do
            local info,pid=p._attr
            local id,depth=tonumber(info.id),tonumber(info.depth)
            xid=xid<id and id or xid
            nid=nid>id and id or nid
            info._cid={id=id}
            lvs[depth]=info._cid
            if depth>0 then
                lvs[depth-1][#lvs[depth-1]+1]=id
                pid=lvs[depth-1]
                info._pid=pid
                while #gs>0 and depth<=gs[#gs].depth do
                    gs[#gs]=nil
                end
            end
            
            for k,s in pair(p.stats.stat) do
                local att=s._attr
                local name=att.name
                info[name]=s[1]
                if max_skews[name] then
                    --print(id,att.sid,att.iid,name,s[1])
                    add_skew_line(id,att.sid,att.iid,max_skews[name],s[1])
                end
            end

            for k,s in pairs(p.optimizer or {}) do
                if k=='cardinality' then k='card' end
                info[k]=s
            end

            if p._attr.name=='PX SEND' then
                if not gs[#gs] then 
                    gs.g,gs.s=gs.g+1,1
                else
                    gs.s=gs[#gs].s==1 and 2 or 1
                end
                local px={depth=depth,id=id,g=gs.g,s=gs.s,color=gs_color(gs.g,gs.s)}
                gs[#gs+1]=px
                gs.list[#gs.list+1]=px
            end
            info.gs=gs[#gs]
            if gs[#gs] and not gs[#gs].dop then gs[#gs].dop=info.dop end

            if pid then
                pid=infos[pid.id]
                if info.gs and info.gs==pid.gs then
                    if not info.px_type and pid.dop then
                        info.px_type=pid.px_type
                    end
                end
            end

            if pxname and info.px_type then
                info.pxname=pxname..'#'..info.px_type
            end

            local obj=p.object or {}
            info.object,info.owner=obj.name,obj.owner

            if p.rwsstats then process_rwstat(id,p.rwsstats) end
            infos[id]=info
        end
        local curr=xid+1
        local function process_ord(node,parent)
            node.ord=curr
            curr=curr-1
            if parent and (parent.gs==node.gs or not parent.gs) then
                parent.child_dop=node.dop or node.child_dop
                node.parent_dop=parent.dop or parent.parent_dop
            end
            for i=#node._cid,1,-1 do
                process_ord(infos[node._cid[i]],node)
            end
        end
        process_ord(infos[nid])
    end
    load_plan_monitor()

    local binds,qbs,lines={nil,hd.binds},{__qbs={}},{}
    local first_start
    local function load_plan()
        local op_fmt,space='%s%s%s%s%s%s',' '
        local child_fmt,child_color='%s%s$NOR$'
        xid='%'..(#(tostring(xid)))..'d'
        local id_fmt='%s%s'..xid..'%s'
        local function format_operation(pad,operation,options,color)
            local st=color or ''
            local ed=color and '$NOR$' or ''
            return op_fmt:format(pad,st,operation,options and (' '..options) or '','',ed)
        end
        local lvs,nodes={colors={},nodes={}},{}

        local function format_id(id,skp,color,pred)
            local st=color or ''
            local ed=color and '$NOR$' or ''
            return id_fmt:format(skp>0 and '-' or pred and '*' or ' ',st,id,ed)
        end

        local function add_hint(text)
            outlines[#outlines+1]={text:find('@') and '' or "Env",text}
        end

        local env_fmt='OPT_PARAM: %s = %s'
        if hd.target and hd.target.optimizer_env then
            for k,v in pair(hd.target.optimizer_env.param) do
                add_hint(env_fmt:format(v._attr.name,v[1]))
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
        local g
        for n,m in ipairs(stats) do
            local id=tonumber(m._attr.id)
            local s=infos[id]
            local p=plan[id] or {}
            local color,id_color
            local e=attrs.top_event[id] or {}
            local depth,child=tonumber(s.depth)

            if p.node and not nodes[p.node] then
                nodes[p.node]={p.object,name=p.node}
                --if p.object:sub(1,1)==':' then nodes[p.object]=nodes[p.node] end
            end

            if s._cid and #s._cid>1 then
                color=colors[math.fmod(#lvs.colors,#colors)+1]
                s._cid.color,lvs.colors[#lvs.colors+1]=color,color
            end
            if s._pid then
                if #s._pid<2 then 
                    lvs[depth]=' '
                elseif s._pid[#s._pid]==id then
                    child=3
                    lvs[depth]='+'
                elseif s._pid[1]<id then
                    child=2
                    lvs[depth]='+'
                else
                    child=1
                    lvs[depth]='+'
                end
                if child then
                    child_color=s._pid.color
                    lvs[depth]=child_fmt:format(child_color,lvs[depth])
                end
            else
                lvs[depth]=''
            end
            p.proj={'','','',s.bytes and (tonumber(s.card) or 0)>0 and ('B'..math.round(tonumber(s.bytes)/tonumber(s.card))) or ''}
            if p.project then
                process_pred(id,'proj',p.project,p)
            end

            for k,v in pair(p.predicates) do
                process_pred(id,v._attr.type,v[1],p,p.object_alias)
            end
            local alias,qb=(p.object_alias or ''):gsub('"',''),p.qblock
            local obj=s.object or s.name:find('^VIEW') and alias~='' and ('$REV$'..alias:gsub('@.*','$NOR$')) or p.node and nodes[p.node][1] or nil
            if obj and obj:sub(1,1)~=':' then obj=' '..obj end
            if p.object_alias then qbs['"'..alias:gsub('@','"@"')..'"']=id end
            if qb and qb~='' then
                qb='@"'..qb:gsub('"','')..'"'
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
            local px_color=s.gs and s.gs.color or nil
            local px_type=s.px_type
            if tonumber(px_type) then
                if not px_color then
                    g,px_type=g or 1,tonumber(px_type)
                    for i,l in ipairs(gs.list) do
                        if g==l.g and px_type==l.s then
                            s.gs=l
                            if l.id>id then l.id=id end
                            break
                        end
                    end
                    px_color=gs_color(g or 1,px_type)
                end
                px_type='S'..px_type 
            end
            if px_type and px_color and s.gs then
                g=s.gs.g
                px_type=px_color..px_type..'$NOR$'
            end
            local start_at=tonumber(s.from_sql_exec_start)
            if start_at and (first_start==nil or first_start>start_at) then first_start=start_at end
            s.aas=e[4]
            lines[#lines+1]={
                id=id,
                format_id(id,tonumber(s.skp) or 0,px_color,preds.ids[id]),
                (color or child or #s._cid==0 or not s._pid) and s.ord or nil,
                '|',
                px_type,
                tonumber(s.dop),
                nil,
                '|',
                format_operation(table.concat(lvs,'',1,depth),s.name,s.options,color),
                '|',
                obj,
                '|',
                type(p.pred)=='table' and table.concat(p.pred,'') or nil,
                '|',
                table.concat(p.proj,''):gsub(',$',''),
                '|',
                attrs.dist_methods[id] or p.distrib or p.partition and (
                    p.partition._attr.start==p.partition._attr.stop and p.partition._attr.start
                    or (p.partition._attr.start..' - '..p.partition._attr.stop)
                ) or nil,
                '|',
                tonumber(s.cost),
                tonumber(s.card),
                tonumber(s.cardinality),
                '|',
                tonumber(s.starts),
                start_at,
                tonumber(s.from_most_recent),
                tonumber(s.duration),
                '|',
                tonumber(s.max_memory),
                tonumber(s.max_temp),
                '|',
                get_interconn(s),
                tonumber(s.read_reqs),
                s.read_reqs and math.ceil(tonumber(s.read_bytes)/tonumber(s.read_reqs)) or nil,
                tonumber(s.write_reqs),
                s.write_reqs and math.ceil(tonumber(s.write_bytes)/tonumber(s.write_reqs)) or nil,
                s.cell_offload_efficiency,
                '|',
                e[3],
                s.aas,
                '|',
                e[2],
                '|',
                strip_quote(p.object_alias),
                '|',
                strip_quote(qb and qb:sub(2) or nil),
            }
            attrs.lines[id]=lines[#lines]
            if child then lvs[depth]=child==3 and ' ' or child_fmt:format(child_color,':') end
            if p.rwsstats then process_rwstat(id,p.rwsstats) end
            local xml=p.other_xml
            if xml then
                binds[1]=xml.peeked_binds
                for k,v in pair(xml.info) do
                    local typ=v._attr and v._attr.type or nil
                    if typ and typ~='nodeid/pflags' and typ~='px_ext_opns' and typ~='db_version' then
                        add_header(typ,v[1],v._attr.note)
                    end
                end

                if xml.stats then
                    local t=xml.stats._attr.type
                    for k,v in pair(xml.stats.stat) do
                        if t and v._attr.name then
                            add_header(t..'.'..v._attr.name,v[1],10)
                        end
                    end
                end

                if xml.outline_data then
                    for k,v in pair(xml.outline_data.hint) do
                        if not v:find('OPT_PARAM') and v~='IGNORE_OPTIM_EMBEDDED_HINTS' then
                            add_hint(v)
                        end
                    end
                end
            end
        end
    end
    load_plan()

    local function load_binds()
        if not binds[1] and not binds[2] then
            binds=nil
            return 
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
        for i=1,2 do
            for j,b in pair(binds[i] and binds[i].bind or nil) do
                local att=b._attr
                local nam=att.nam or att.name
                local row=rows._names[nam] or {nam}
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
                row[3]=math.min(tonumber(att.pos) or 9999,row[3] or 9999)
                if b[1] then
                    row[3+i]=(att.dtystr and att.format~='hexdump' and '' or '(0x)')..b[1]
                else
                    row[3+i]='<Unknown>'
                end
                if not rows._names[nam] then
                    rows._names[nam]=row
                    rows[#rows+1]=row
                end
            end
        end
        table.sort(rows,function(a,b) return a[3]<b[3] end)
        table.insert(rows,1,{'Name','Data Type','Position','Peek','Bind Value'})
        rows.topic,rows.colsep='Binds/Peek Binds','|'
        binds=rows
    end
    load_binds()

    local skew_outputs
    local function calc_skews()
        if #skews>0 then
            local rows={topic='Skew Info',{}}
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
                local t,aas,e=c[skew_aas_index],-1,''
                if t then
                    events={}
                    for k,v in pairs(c[skew_event_index+1]) do
                        if v>aas then
                            e=k..' '..to_pct(v,t)
                            aas=v
                        end
                    end
                end
                c[skew_event_index]=e
                local id=c[1]
                local row,pxstat={}
                local info=infos[id]

                while gs.list[gs_idx+1] and gs.list[gs_idx+1].id<=id do
                    gs_idx=gs_idx+1
                end
                
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
                    c[2]=color..c[2]..'$NOR$'
                end
                local dop=tonumber(info.dop or info.gs and info.gs.dop or info.child_dop or info.parent_dop or 0) or 0
                local idx,counter=0,0
                local function add_column(value)
                    idx=idx+1
                    row[idx]=value
                    if idx>2 and tonumber(value) then 
                        counter=counter+1
                    end
                end
                for j=1,len do
                    add_column(c[j])
                    local s=skew_list[j][1]
                    if s then
                        local val
                        if dop>1 and c[j] then
                            val=tonumber(info[s])
                            if val then
                                val=math.round((val-c[j])/(dop-1),4)
                                if j>2 and j<skew_aas_index then
                                    if math.abs(c[j]-val)<100 then
                                        row[idx],val=nil
                                        counter=counter-1
                                    elseif val~=0 then
                                        local pct=c[j]/val
                                        if pct>0.83 and pct<1.2 then
                                            row[idx],val=nil
                                            counter=counter-1
                                        end
                                    end
                                end
                            end
                        end
                        add_column(val)
                    end
                    add_column('|')
                end
                if counter>0 then 
                    rows[#rows+1]=row
                    attrs.lines[id][6]='Yes'
                    if pxstat then pxstat[sql_start_idx]='Yes' end
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
            sqlstat[2][3]=first_start
            pr(grid.merge({sqlstat},'plain'))
            env.var.define_column('Proc','clear')
        end

        local summary=print_header('Execution Plan Summary',false)
        if summary then
            summary.colsep='|'
            pr(grid.merge({summary},'plain'))
        end

        if line_events then 
            pr(grid.merge(line_events,'plain')) 
        end

        if lines and #lines>0 then
            table.insert(lines,1,{'Id','Ord','|','PX#','DoP','Skew','|','Operation','|','Object Name','|','Pred','|','Proj','|',
                                  'Distrib|Partition','|','Est|Cost','Est|Rows','Act|Rows','|',
                                  'Start|Count','From|Start','From|End','Active|Clock','|','Max|Mem','Max|Temp','|',
                                  'Inter|Connc','Read|Reqs','Avg|Read','Write|Reqs','Avg|Write','Offload|Effi(%)','|',
                                  'Resp|Time','ASH|AAS','|','Top|Event','|','Object|Alias','|','Query|Block'})
            
            lines.topic='Execution Plan Lines'
            pr(grid.merge({lines},'plain'))
            env.set.set('colsep','default')
        end

        
        if skew_outputs then
            env.var.define_column('id','break')
            pr(grid.merge({skew_outputs},'plain'))
            env.var.define_column('id','clear')
        end

        if #preds>0 then
            env.var.define_column('id','break')
            table.sort(preds,function(a,b) 
                if a[1]~=b[1] then return a[1]<b[1] end
                return a[2]<b[2]
            end)
            table.insert(preds,1,{'Id','Type','Content'})
            title('Predicates/Line Stats')
            pr(grid.tostring(preds))
        end

        if #outlines>0 then
            title('Opt Env / Outlines')
            table.sort(outlines,function(a,b)
                for _,c in ipairs{a,b} do
                    if c[1]=='' and c[2]:find('"') then
                        local hint=(' '..c[2]..' '):gsub('([^'..seqs..'"@%.])','%1%1')
                        local list={}
                        hint:gsub('([^%."@])(@?"['..seqs..'"@%.]+")([^%."@])',function(p,c,s)
                            if type(qbs[c])=='table' then
                                list[2]=qbs[c]
                            elseif qbs[c] then
                                if not list[1] then list[1]={} end
                                list[1][#list[1]+1]=qbs[c]
                            end
                            return p..c..s
                        end)
                        if list[1] and #list[1]==1 then 
                            c[1]=xid:format(list[1][1])
                        elseif list[2] then
                            if not list[1] or list[2].min==list[2].max then
                                c[1]=xid:format(list[2].min)
                            else
                                c[1]=xid:format(list[2].min)..' - '..xid:format(list[2].max)
                            end
                        end
                        c[2]=strip_quote(c[2])
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
    end
    print_report()
    text=table.concat(text,'\n')
    print("\nSQL Monitor report in text written to "..env.save_data(file..'.txt',text:strip_ansi()))
    print("SQL Monitor report in text written to "..env.save_data(file..'_colored.txt',text))
end

function unwrap.unwrap(obj,ext,prefix)
    env.checkhelp(obj)
    local filename,org_ext=obj
    local typ,f=os.exists(obj)
    if ext=='.' then 
        ext=nil
    elseif ext and ext:lower()=='18c' then
        ext,prefix=nil,'18c'
    end
    prefix=prefix or ''
    if typ then
        if typ~="file" then return end
        obj=f
        filename,org_ext=f:match("(.*)%.(.-)$")
        if filename then
            filename=filename.."_unwrap."..org_ext
        else
            filename=f..'.unwrap'
        end

        f=io.open(f)

        local found,stack,org,repidx=false,{},{}
        local is_wrap=false
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
        f:close()
        if #stack>0 then
            is_wrap=true
            org[#org+1]=loader:Base64ZlibToText({table.concat(stack,'')}) 
        end
        local text=table.concat(org,'\n')
        local done,err=pcall(unwrap.analyze_sqlmon,text,obj,ext)
        if not done then
            env.warn(err)
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
    env.set_command(nil,"unwrap",[[
        Decrypt wrapped object or compressed Active Report, type 'help @@NAME' for more detail. Usage: @@NAME {[<owner>.]<object_name> | <sql monitor filename>}
    ]],
    unwrap.unwrap,false,4)
end

return unwrap