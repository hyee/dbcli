#!/usr/bin/env lua
--run shell command get return output
--mode: parse=return field array / true=return the whole output / nil=return line by line
local function output(cmd,mode)
    local file=io.popen(cmd,'r')
    if not file then
        print("execute failed: "..cmd)
        os.exit(1)
    end
    file:flush()
    
    local row,headers=0,{}
    if mode=='parse' then
        local line=file:read('*l')
        if not line then
            file:close()
            file=nil
        else
            local last,cnt=1,0
            while true do
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
    elseif mode then
        local txt=file:read('*a')
        file:close()
        return txt and txt:match('^%s*(.-)%s*$') or ''
    end
    
    return function()
        if not file then return end
        local line=file:read('*l')
        if not line then
            file:close()
            return
        end
        row = row + 1
        if not mode then
            return line, row
        end
        
        local cols={}
        local last,cnt=1,0
        while true do
            local start_,end_ = line:find('%S+',last)
            if not start_ then
                for col=cnt+1,#headers do
                    cols[headers[col]:lower()]='' 
                end
                break
            else
                cnt=cnt+1
                local col=headers[cnt]:lower()
                if cnt==#headers then
                    cols[col]=line:sub(start_):match('^%s*(.-)%s*$')
                    --print(col,cols[col])
                    break
                else
                    cols[col]=line:sub(start_,end_)
                    --print(col,cols[col])
                end
                last= end_ + 1
            end
        end
        return cols, line
    end
end

local users,instances={},{}
local db_prefix={'db_','ora_','asm_'}

--find running db instances
local find_instance="ps -ef|grep -E ' ("..table.concat(db_prefix,'|')..")(smon|pmon)_'"

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
local dbs={}
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
    elseif search('^apx_.-_(.+)$') then
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
    if instance and group then
        if not users[cols.user][instance][group] then
            users[cols.user][instance][group]=values
        end
        field=users[cols.user][instance][group]
        if not dbs[instance] then dbs[instance]={pga=0,sga=0,hugepage=0} end
        if p1=='smon' then
            local fname='/proc/'..cols.pid..'/smaps'
            local smap=[[grep -B 11 'KernelPageSize:     2048 kB' FNAME | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum}']]
            smap=smap:gsub('FNAME',fname)
            smap=output(smap,true)
            dbs[instance].hugepage=tonumber(smap) or 0
        end
    else
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
    local pmap="pmap -Xp "..cols.pid..[[ 2>/dev/null | grep -E '^\s*(Address|\w{8,16})\s+']]
    local found
    
    for m,mem in output(pmap,'parse') do
        if not found then
            found = true
            field._count=field._count+1
            field._rss=field._rss-tonumber(cols.rss)
        end
        
        for n,v in pairs{
                    _rss   = tonumber(m.rss),
                    _pss   = tonumber(m.pss) or 0,
                    _page  = m.mapping:find('^/SYSV')  and tonumber(m.size) or 0, 
                    _file  = m.mapping:find('^/.+/') and tonumber(m.pss) or 0,
                    _file2 = m.mapping:find('^/.+/') and tonumber(m.rss) or 0,
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
        
        if p1 then 
            dbs[instance].pga=dbs[instance].pga+(tonumber(m.rss) or 0)
        end
        if  p1=='smon' and m.mapping:find('^/SYSV') then
            dbs[instance].sga=dbs[instance].sga+(tonumber(m.size) or 0)
        end
    end
end

local total,sizes,temp={},{},{}
local titles={"Group","Pss","Rss","FilePss","FileRss","MGAPss","MGARss","SwapPss","SwapRss","ShmemMap","FileMap","PrivateHugeTlb","Processes","pmaps"}
for index,name in ipairs(titles) do
    sizes[name]=name:len()
    total[index]=index==1 and '* TOTAL *' or 0
    temp[index]=0
end

local rows={}
local function max_(a,b)
    return math.max(math.abs(a),tostring(b):len())
end

local function new_row(group,name)
    sizes[titles[1]]=-1*max_(sizes[titles[1]],name)
    temp[1]=name
    group[#group+1]={table.unpack(temp)}
    rows[#rows+1]=group[#group]
end


local function print_rows(idx)
    local fmt,seps={},{}
    for index,name in ipairs(titles) do
        fmt[index]='%'..sizes[name]..'s'
        seps[index]=string.rep('-',math.abs(sizes[name]))
    end
    fmt=table.concat(fmt,' ')
    print(string.format(fmt,table.unpack(titles)))
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
        print(string.format(fmt,table.unpack(row)))
    end
end

print('==========================')
print('|   PROCESS MEMORY (MB)  |')
print('==========================')
--now build the column values and column widths
for user,instances in pairs(users) do
    local group,name={}
    local index=#rows
    new_row(group,'User: '..user)
    for instance,types in pairs(instances) do
        if types[''] then
            name='  '..instance
        else
            name='  Database: '..instance
        end
        new_row(group,name)
        
        for typ,data in pairs(types) do
            if typ~='' then
                 new_row(group,'    '..typ)
            end
            for idx,value in ipairs{data._pss,data._rss, data._file,data._file2,data._mga,data._mga2,data._swap,data._swap2,data._shmem,data._fpdm,data._huge1, data._total,data._count} do
                local index=idx+1
                name=titles[index]
                for _,row in ipairs(group) do
                    row[index]=tostring(tonumber(row[index])+value)
                end
                total[index]=tostring(tonumber(total[index])+value)
                sizes[name]=max_(sizes[name],total[index])
            end
            
            if typ~='' then
                group[#group]=nil
            end
        end
        group[#group]=nil
    end
    if #rows-index==2 and rows[#rows][1]:find('Others') then rows[#rows]=nil end
end
print_rows(2)

print(' ')
print('==========================')
print('|   DATABASE MEMORY (MB) |')
print('==========================')
total,sizes,temp,rows={},{},{},{}
titles={"Database","Non-SGA","SGA","HugePage_Used","HugePages_Total","UsedMem"}
for index,name in ipairs(titles) do
    sizes[name]=name:len()
    total[index]=index==1 and 'TOTAL' or '0'
    temp[index]=0
end

hugepage_total=[[grep HugePages_Total /proc/meminfo 2>/dev/null | awk '{print $2*2}']]
hugepage_total=tonumber(output(hugepage_total,true)) or 0
local remain=hugepage_total
for instance,info in pairs(dbs) do
    temp[1]=instance
    sizes.Database=-1* max_(sizes.Database,instance)
    local row={table.unpack(temp)}
    for idx,value in ipairs{info.pga,info.sga,info.hugepage,' ',math.max(info.sga,info.hugepage)+info.pga} do
        local index = idx +1
        if type(value)=='number' then
            local name=titles[index]
            value = math.ceil(value/1024)
            total[index]=tostring(tonumber(total[index])+value)
            row[index]=tostring(value)
            sizes[name]=max_(sizes[name],total[index])
        else
            row[index]=' '
        end
    end
    remain=remain-math.ceil(info.hugepage/1024)
    rows[#rows+1]=row
end

if hugepage_total>0 then
    total[#total-1]=tostring(hugepage_total)
    if remain > 0 then
        total[#total]=tostring(tonumber(total[#total])+remain)
    end
end
print_rows(9)

print(' ')
print('==========================')
print('|      OS MEMORY (MB)    |')
print('==========================')
os.execute('free -m')
print(' ')