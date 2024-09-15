#!/usr/bin/env lua

--@Hyee, script to summarize Linux memory usages in process/database/global level

--run shell command get return output
--mode: parse=returns field array / true=returns the whole output / nil=returns line by line
local db_prefix={'db_','ora_','asm_'}
--Map users: {<usr1>={<inst1>={<group1>={<numeric fields>},<group2>=...},inst2=...,Others=...}, <usr2>=...}
local users,dbs={},{}

local function output(cmd,mode)
    local file=io.popen(cmd,'r')
    if not file then
        print("execute failed: "..cmd)
        os.exit(1)
    end
    file:flush()
    
    local txt=file:read('*a')
    file:close()
    if mode==true then
        return txt and txt:match('^%s*(.-)%s*$') or ''
    end
    
    local function next_line()
        while true do
            local start_,end_=txt:find('[\n\r]+',1)
            if not start_ then
                if #txt == 0 then
                    return nil
                else
                    start_=#txt+1
                end
            end
            local line=txt:sub(1,start_-1)
            txt=txt:sub(end_+1)
            if #line>0 then return line end
        end
    end
        
    local row,headers=0,{}
    if mode=='parse' then --parse: reads line by line and returns field array
        local line=next_line()
        if line then
            --build field names
            local last,cnt=1,0
            while true do
                --read next non-space string
                local start_,end_ = line:find('%S+',last)
                if not start_ then
                    break
                else
                    last= end_ + 1
                    cnt=cnt+1
                    headers[cnt]=line:sub(start_,end_)
                end
            end
        end
    end
    --returns a function that invoked by 'for .. do' statement
    return function()
        local line=next_line()
        if not line then
            return
        end
        row = row + 1
        --mode=nil: returns line and row index
        if not mode then
            return line, row
        end
        --build field values
        local cols={}
        local last,cnt=1,0
        while true do
            --read next non-space string
            local start_,end_ = line:find('%S+',last)
            if not start_ then
                --fill whitespace to the tailing fields in case of EOF
                for col=cnt+1,#headers do
                    cols[headers[col]:lower()]='' 
                end
                break
            else
                cnt=cnt+1
                local col=headers[cnt]:lower()
                if cnt==#headers then
                    --the last field will read until EOF
                    cols[col]=line:sub(start_):match('^%s*(.-)%s*$')
                    break
                else
                    cols[col]=line:sub(start_,end_)
                end
                last= end_ + 1
            end
        end
        --returns field array and the whole line
        return cols, line
    end
end


--find running db instances via smon/pmon
local find_instance="ps -ef|grep -E ' ("..table.concat(db_prefix,'|')..")(smon|pmon)_'"
local instances={}
for line in output(find_instance) do
    local user,pid,mon,instance = line:match('^%s*(%S+)%s+(%d+)%s+.* %S+_([sp]mon)_(%S+)%s*$')

    if not instances[user] then
        instances[user]={}
    end
    
    if not users[user] then
        users[user]={}
    end
    
    if not instances[user][instance] then
        instances[user][instance]={}
    else
        --copy to user list only when both SMON/PMON are found
        users[user][instance]=instances[user][instance]
    end
end

--analyze all processes
local pattern='('..table.concat(db_prefix,'|')..')'
local count=0
for cols,line in output('ps aux | grep -v grep','parse') do
    if not users[cols.user] then users[cols.user]={} end
    local cmd,instance,field=cols.command
    local p1,p2,p3,instance,group
    local function search(regexp)
        p1,p2=cmd:match(regexp)
        return p1
    end
    
    if search('^oracle([^_ ]+).*(LOCAL=[A-Z]+)') then --search process where LOCAL=YES|NO
        if users[cols.user][p1] then 
            instance,group=p1,p2
        end
    elseif search('^apx_.-_(.+)$') then --search Apex processes
        instance = "Apex: "..p1
    else --search Oracle background process
        for _,prefix in ipairs(db_prefix) do
            p1,p2=cmd:match('^'..prefix..'(%w+)_(%S+)$')
            if p1 then
                if users[cols.user][p2] then
                    instance,group=p2,'Others'
                    if p1=='smon' then
                        group='SMON'
                    elseif p1=='pmon' then
                        group='PMON'
                    elseif p1=='ckpt' then
                        group='CKPT'    
                    elseif p1:find('dbw',1,true)==1 or p1:find('bw',1,true)==1 then
                        group='DBWR'
                    elseif p1:find('lg',1,true)==1 then
                        group='LGWR'
                    elseif p1:find('lm',1,true)==1 then
                        group='LMxx'    
                    elseif p1:find('w0',1,true)==1 then
                        group='Wnnn'
                    end
                end
                break
            end
        end
    end
    local values={_rss=0,_pss=0,_page=0,_swap=0,_swap2=0,_count=0,_total=0,_file=0,_file2=0,_mga=0,_mga2=0,_shmem=0,_fpdm=0,_huge1=0,_huge2=0}
    
    if instance and group then -- in case of the process belongs to Oracle instance
        if not users[cols.user][instance][group] then
            users[cols.user][instance][group]=values
        end
        field=users[cols.user][instance][group]
        if not dbs[instance] then dbs[instance]={pga=0,sga=0,proc=0,hugepage=0} end
        dbs[instance].proc=dbs[instance].proc+1
        dbs[instance].pga=dbs[instance].pga+tonumber(cols.rss)
        if p1=='smon' then --try to read the HugePages usage
            local fname='/proc/'..cols.pid..'/smaps'
            local smap=[[grep -B 11 'KernelPageSize:     2048 kB' FNAME | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum}']]
            smap=smap:gsub('FNAME',fname)
            smap=output(smap,true)
            dbs[instance].hugepage=tonumber(smap) or 0
        end
    else --for non-instance process, do not build sub-categories
        instance=instance or 'Others'
        if not users[cols.user][instance] then
            users[cols.user][instance]={[""]=values}
        end
        field=users[cols.user][instance][""]
        p1,p2=nil,nil
    end
    field._rss=field._rss+tonumber(cols.rss)
    field._total=field._total+1

    --run pmap to get rss/pss/swap
    local pmap="pmap -Xp "..cols.pid..[[ 2>/dev/null | grep -E '^\s{0,10}(Address|\w{8,16})\s+']]
    local found
    
    for m,mem in output(pmap,'parse') do
        if not found then --if pmap has output
            found = true
            field._count=field._count+1
            field._rss=field._rss-tonumber(cols.rss)
            if p1 then dbs[instance].pga=dbs[instance].pga-tonumber(cols.rss) end
        end
            
        for n,v in pairs{
                    _rss   = tonumber(m.rss) or 0,
                    _pss   = tonumber(m.pss) or 0,
                    _page  = m.mapping:find('^/SYSV')  and tonumber(m.size) or 0, 
                    _file  = not m.mapping:find('KSIPC_MGA_NMSPC',1,true) and m.mapping:find('^/.+/') and tonumber(m.pss) or 0, --if target is a file path
                    _file2 = not m.mapping:find('KSIPC_MGA_NMSPC',1,true) and m.mapping:find('^/.+/') and tonumber(m.rss) or 0,
                    _mga   = m.mapping:find('KSIPC_MGA_NMSPC',1,true) and tonumber(m.pss) or 0,
                    _mga2  = m.mapping:find('KSIPC_MGA_NMSPC',1,true) and tonumber(m.rss) or 0,
                    _swap  = tonumber(m.swappss) or 0,
                    _swap2 = tonumber(m.swap) or 0,
                    _shmem = tonumber(m[('ShmemPmdMapped'):lower()]) or 0,
                    _fpdm  = tonumber(m[('FilePmdMapped'):lower()]) or 0,
                    _huge1 = tonumber(m[('Private_Hugetlb'):lower()]) or 0,
                    _huge2 = tonumber(m[('Shared_Hugetlb'):lower()]) or 0
                    } do
            field[n]=field[n]+v
        end
        
        --caculate PGA from Rss
        if p1 then 
            dbs[instance].pga=dbs[instance].pga+(tonumber(m.pss) or 0)
        end
        --SGA seems like starting with /SYSV, i.e.: /SYSV00000000
        if  p1=='smon' and m.mapping:find('^/SYSV000') then
            dbs[instance].sga=dbs[instance].sga+(tonumber(m.size) or 0)
        end
    end
end

local total,sizes,temp,rows={},{},{},{}
local titles={"Group","Pss","Rss","FilePss","FileRss","MGAPss","MGARss","SwapPss","SwapRss","ShmemMap","FileMap","PrivateHugeTlb","Processes","pmaps"}
--initiate field lengths, total, template
for index,name in ipairs(titles) do
    sizes[name]=name:len()
    total[index]=index==1 and '* TOTAL *' or 0
    temp[index]=0
end

--caculate output field max width
local function max_(a,b)
    return math.max(math.abs(a),tostring(b):len())
end

local unpack=table.unpack or unpack
local function new_row(group,name)
    sizes[titles[1]]=-1*max_(sizes[titles[1]],name)
    temp[1]=name
    group[#group+1]={unpack(temp)}
    rows[#rows+1]=group[#group]
end

--print output table
local function print_rows(idx)
    local fmt,seps={},{}
    --build headers, string format and row seperator
    for index,name in ipairs(titles) do
        fmt[index]='%'..sizes[name]..'s'
        seps[index]=string.rep('-',math.abs(sizes[name]))
    end
    fmt=table.concat(fmt,' ')
    print(string.format(fmt,unpack(titles)))
    table.insert(rows,1,seps)
    table.insert(rows,seps)
    table.insert(rows,total)
    table.insert(rows,seps)
    for _,row in ipairs(rows) do
        for i=2,#row-idx do
            local num=tonumber(row[i])
            if num then
                row[i]=tostring(math.ceil(num/1024))
            end
        end
        print(string.format(fmt,unpack(row)))
    end
end

print('==========================')
print('|   PROCESS MEMORY (MB)  |')
print('==========================')
--now build the column values and column widths
for user,instances in pairs(users) do
    --group: a group of rows to sum the values
    --name:  group name
    local group,name={}
    local index=#rows
    new_row(group,'User: '..user)
    for instance,types in pairs(instances) do
        if types[''] then
            name='  '..instance
        else
            name='  Database: '..instance
        end
        --push row
        new_row(group,name)
        for typ,data in pairs(types) do
            if typ~='' then --push row for db instance process group
                 new_row(group,'    '..typ)
            end
            --compute numeric fields
            for idx,value in ipairs{data._pss,data._rss, data._file,data._file2,data._mga,data._mga2,data._swap,data._swap2,data._shmem,data._fpdm,data._huge1, data._total,data._count} do
                local index=idx+1
                name=titles[index]
                for _,row in ipairs(group) do
                    row[index]=tostring(tonumber(row[index])+value)
                end
                total[index]=tostring(tonumber(total[index])+value)
                sizes[name]=max_(sizes[name],total[index])
            end
            
            if typ~='' then --pop row for db instance process group
                group[#group]=nil
            end
        end
        --pop row
        group[#group]=nil
    end
    --for non-instance process group, only keep one row
    if #rows-index==2 and rows[#rows][1]:find('Others') then rows[#rows]=nil end
end
print_rows(2)

print(' ')
print('==========================')
print('|  DATABASE MEMORY (MB)  |')
print('==========================')
total,sizes,temp,rows={},{},{},{}
titles={"Database","Processes","Non-SGA","SGA","HugePages_Used","HugePages_Total","Total Used"}
for index,name in ipairs(titles) do
    sizes[name]=name:len()
    total[index]=index==1 and 'TOTAL' or '0'
    temp[index]=0
end

--read /proc/meminfo
local mem={}
for line in output('cat /proc/meminfo 2>/dev/null') do
    local name,kb = line:match('(%S+):%s+(%d+)')
    mem[name]=kb
end
--read HugePages from /proc/meminfo
hugepage_total=math.ceil((tonumber(mem['HugePages_Total']) or 0)*(tonumber(mem['Hugepagesize']) or 0)/1024)
local remain=hugepage_total
for instance,info in pairs(dbs) do
    temp[1]=instance
    sizes[titles[1]]=-1* max_(sizes[titles[1]],instance)
    --build output row
    local row={unpack(temp)}
    --compute numeric fields
    for idx,value in ipairs{info.proc,info.pga,info.sga,info.hugepage,' ',math.max(info.sga,info.hugepage)+info.pga} do
        local index = idx +1
        if type(value)=='number' then
            local name=titles[index]
            if name~='Processes' then
                value = math.ceil(value/1024)
            end
            total[index]=tostring(tonumber(total[index])+value)
            row[index]=tostring(value)
            sizes[name]=max_(sizes[name],total[index])
        else
            row[index]=' '
        end
    end
    --if target db instance uses hugePages, then minus it from remaining
    remain=remain-math.ceil(info.hugepage/1024)
    rows[#rows+1]=row
end

--compute total used memory over all db instances
if hugepage_total>0 then
    total[#total-1]=tostring(hugepage_total)
    if remain > 0 then
        total[#total]=tostring(tonumber(total[#total])+remain)
    end
end
print_rows(9)

--print free -m
print(' ')
print('==========================')
print('|      OS MEMORY (MB)    |')
print('==========================')
local function mb(val)
    if type(val)=='number' then return tostring(math.ceil(val/1024)) end
    val = tonumber(mem[val]);
    if not val then return ' ' end
    return tostring(math.ceil(val/1024))
end

if not tonumber(mem['MemTotal']) then
    return print('free -m')
end

fmt='%-11s   %11s   %11s   %13s   %10s   %10s   %10s'
print(fmt:format('','Total','Used/Active','Free/Inactive','Available','Cached','Buffers'))
print(fmt:format('-----------','-----------','-----------','----------','----------','----------','----------'))
print(fmt:format('Mem',
                 mb('MemTotal'),
                 mb(tonumber(mem['MemTotal'])-tonumber(mem['MemFree'])),
                 mb('MemFree'),
                 mb('MemAvailable'),
                 mb('Cached'),
                 mb('Buffers')))
print(fmt:format('Slab',
                 mb('Slab'),
                 mb('SUnreclaim'),
                 mb('SReclaimable'),
                 mb('SReclaimable'),
                 mb('SReclaimable'),
                 ''))
print(fmt:format('PageCache',
                 mb(tonumber(mem['Active(file)'])+tonumber(mem['Inactive(file)'])),
                 mb('Active(file)'),
                 mb('Inactive(file)'),
                 mb(tonumber(mem['Active(file)'])+tonumber(mem['Inactive(file)'])),
                 mb(tonumber(mem['Active(file)'])+tonumber(mem['Inactive(file)'])),
                 ''))
print(fmt:format('Anon',
                 mb(tonumber(mem['Active(anon)'])+tonumber(mem['Inactive(anon)'])),
                 mb('Active(anon)'),
                 mb('Inactive(anon)'),
                 mb(tonumber(mem['Active(anon)'])+tonumber(mem['Inactive(anon)'])),
                 '',
                 ''))
print(fmt:format('Shared',
                 mb('Shmem'),
                 mb(tonumber(mem['Shmem'])-tonumber(mem['KReclaimable'] or mem['SReclaimable'])+tonumber(mem['SReclaimable'])),
                 '',
                 mb(tonumber(mem['KReclaimable'] or mem['SReclaimable'])-tonumber(mem['SReclaimable'])),
                 
                 '',
                 ''))                 
local tmpfs=output([[df -m 2>/dev/null | egrep '^tmpfs' | awk '{t+=$2;u+=$3;a+=$4}END{print t,u,a}']],true)
local t,u,a=(tmpfs or ''):match('(%d+)%s+(%d+)%s+(%d+)')
if t then
    print(fmt:format('tmpfs',
                     t,
                     u,
                     a,
                     a,
                     '',
                     ''))
end
print(fmt:format('Swap',
                 mb('SwapTotal'),
                 mb(tonumber(mem['SwapTotal'])-tonumber(mem['SwapFree'])),
                 mb('SwapFree'),
                 '',
                 mb('SwapCached'),
                 ''))    
print(fmt:format('Vmalloc',
                 mb('VmallocTotal'),
                 mb('VmallocUsed'),
                 mb(tonumber(mem['VmallocTotal'])-tonumber(mem['VmallocUsed'])),
                 '',
                 '',
                 ''))