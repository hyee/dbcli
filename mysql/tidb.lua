local db=env.getdb()
local tidb=env.class(db.C.sql)
local parser=env.json_plan
local access='access object'
local config={
    root='Plan',
    child='Plans',
    processor=function(name,value,row,node)
        --if not name and node then end
        return value
    end,
    keep_indent=true,
    columns={
            {'id','Operation'},'|',
            {access,'Access Info'},'|',
            {'task',"Task|Name"},'|',
            {'estCost',"Est|Cost",format='TMB2'},'|',
            {'estRows',"Est|Rows",format='TMB2'},{'actRows',"Act|Rows",format='TMB2'},'|',
            {parser.leaf,"Leaf|Time",format='usmhd2'},'|',
            {'time',"Act|Time",format='usmhd2'},'|',
            {'loops',"Act|Loops",format='TMB2'},'|',
            {'concurrency',"Act|Conc",format='TMB2'},'|',
            {'memory','Memory',format='KMG2'},{'disk','Disk',format='KMG2'},'|',
            {'operator info',"Operator Info"},'|'
            },
    --sorts=false,
    leaf_time_based="time",
    percents={parser.leaf},
    title='Plan Tree | Conc: Concurrency',
    projection='[PROJ]'
}
function tidb:ctor()
    self.db=env.getdb()
    self.command="ti"
    self.help_title='Run SQL script on TiDB under the "ti" directory.'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."ti",{}
end

function tidb:run_sql(sql,args,cmds,files)
    env.checkerr(db.props.tidb,"Command 'ti' is used on TiDB only!")
    return self.super.run_sql(self,sql,args,cmds,files)
end

local units={{
    KB=1024,
    MB=1024^2,
    GB=1024^3,
    TB=1024^4,
    BYTES=1,
    BYTE=1,
    K=1000,
    M=1000^2,
    B=1000^3,
    T=1000^4
},{
    MS=1000,
    ['µs']=1,
    US=1,
    S=1000000,
    SECS=1000000,
    SEC=1000000,
    M=60*1000000,
    MIN=60*1000000,
    MINUTE=60*1000000,
    MINUTES=60*1000000,
    H=3600*1000000,
    HOUR=3600*1000000,
    HOURS=3600*1000000,
    D=24*3600*1000000,
    DAY=24*3600*1000000,
    DAYS=24*3600*1000000
}}
local function extract_num(val,idx)
    if not val then return nil end
    if tostring(val):upper()=='N/A' then return 0 end
    local num,unit=tostring(val):match("^%s*(%-?[%.0-9]+)%s*(%S+)$")
    if not num then return tonumber(val) or val end
    idx=idx or 1
    unit=units[idx][unit:upper()] or units[idx][unit]
    if not unit then return val end
    return tonumber(num)*unit
end

function tidb:build_json(plan)
    local tree={[config.root]={[config.child]={}}}
    local maps={tree[config.root]}
    local headers=plan[1]
    
    --find access object field id
    local access_index
    for c,n in ipairs(headers) do
        if n==access then
            access_index=c
            break
        end
    end

    local patterns1={'^(%s*(%S[^:]+):%s*(%b{}),?)','^(%s*(%S[^:{}]+):%s*([^,:{}]+),?)'}
    local patterns2={'^(%s*([a-zA-Z0-9 ]+%s*:%s*%S[^,]*)%s*,)','^(%s*([%.a-zA-Z0-9_ ]+)%s*,)'}
    local node,depth,is_cte,spaces,id=maps[1],1,false
    for i=2,#plan do
        for j,col in ipairs(plan[i]) do
            local name=headers[j]
            local lname=name:lower()
            if lname=='id' then
                spaces,id=col:rtrim():match('^(.-)(%w%w%w.*)')
                if spaces then
                    local _,len=spaces:ulen()
                    depth=len/2+2
                    if spaces=='' and i>2 then
                        is_cte=id:rtrim():find('^CTE%_%d+$') and true or false
                    end
                    node={[config.child]={}}
                    if is_cte then
                        depth=depth+1
                    end
                    if depth>1 then
                        maps[depth]=node
                    else
                        node=maps[1]
                    end
                    for n=#maps,depth+1,-1 do maps[n]=nil end
                    if maps[depth-1] then
                        local childs=maps[depth-1][config.child]
                        table.insert(childs,#childs+(is_cte and depth==3 and 0 or 1),node)
                    end
                    if config.keep_indent~=true then 
                        col=id
                    elseif is_cte then
                        col=(depth==3 and '├─' or '│ ')..col
                    end
                end
            elseif lname:find('time',1,true) then
                col=extract_num(col,2)
            elseif lname=='execution info' then
                while true do
                    local piece,k,v=col:match(patterns1[1])
                    if not piece then piece,k,v=col:match(patterns1[2]) end
                    if not piece then break end
                    col=col:sub(#piece+1)
                    node[k]=extract_num(v,k:find('time') and 2 or 1)
                    if k:lower()=='concurrency' then 
                        node[k]=tonumber(node[k]) --set as nil in case of non-numeric
                    end
                end
                col=nil
            elseif lname=='operator info' and type(col)=='string' then
                if id:find('^Projection_%d+') or id:find('^Sort_%d+')  or id:find('^[SH][oa][rs][th]Agg_%d+') then
                    node['[PROJ]'],col=col,nil
                else
                    col=col:gsub(',%s*start_time:.*','')
                    if (plan[i][access_index or -1] or '')=='' then
                        local piece,v=(col..','):match(patterns2[1])
                        if not piece or v:find('group by') then
                            piece,v=(col..','):match(patterns2[2])
                        end
                        if piece then
                            local piece1,v1=piece:match('^((.-) %s+)%S.*$')
                            if piece1 then
                                piece,v=piece1,v1
                            end
                            col=col:sub(#piece+1):ltrim()
                            node[access]=v
                        end
                    end
                end
            end
            node[name]=extract_num(col)
        end
    end
    --print(table.dump(tree))
    parser.parse_json_plan(env.json.encode(tree),config)
end

function tidb:parse_cursor(plan)
    local header=plan[1]
    if #header==1 and #plan==2 then return false end
    local adjust,adjust_list=false,{}
    local cols=#header
    for i=1,cols do
        local found=header[i]:find(' info',1,true)
        if i==cols and not found then
            adjust=true
        end
        if found then
            adjust_list[#adjust_list+1] = i
        end
    end
    if #adjust_list>0 and adjust then
        for i,row in ipairs(plan) do
            for j,idx in ipairs(adjust_list) do
                col=table.remove(row,idx-j+1)
                table.insert(row,col)
                info=row.colinfo
                if i==1 and info then
                    col=table.remove(info,idx-j+1)
                    table.insert(info,col)
                end
            end
        end
    end
    self:build_json(plan)
end

function tidb:parse_plan(plan)
    env.checkhelp(plan,"Missing plan file or plan text.")
    if type(plan)=='table' then
        return self:parse_cursor(plan)
    end
    if #plan<128 and os.exists(plan) then
        plan=env.load_data(plan,false)
    elseif not plan:find('%s') and env.var.inputs[plan:upper()] then
        plan=env.var.inputs[plan:upper()]
    elseif env.var.outputs[plan:upper()] then
        return
    end
    local sub=plan:sub(1,4096):gsub('\r',''):gsub('\t','    ')
    local pattern,header=nil,{}
    local start_=sub:find(' *|? *id[ |][^\n\r]*[^\n\r]*estRows[ |]')
    if not start_ then
        pattern='^([^\n]-)%s+([0-9%.]+)%s+(%S+)%s+(%S*[^\n]*)'
        header={'id','estRows','task','operator info'}
        start_=sub:find('%w%w%w[^\n]+\n *└─'..pattern:sub(2))
    end
    if not start_ then return false end
    plan=plan:sub(start_)
    plan=plan:gsub('\r',''):gsub('\t','    '):gsub('\n[%- ]*\n','\n'):rtrim():split('\n')
    if plan[1]:trim()=='' then 
        table.remove(plan,1)
    end
    
    if not pattern then
        local curr,prev=nil
        local infos,ped={}
        for n,s,c,st,ed in (plan[1]:rtrim()..' '):gsplit('%s+') do
            if not ped then ped=ed end
            if n:lower():find('^info') or n:lower():find('^object') then
                prev.name=prev.name..' '..n
                prev.stop=ed
                infos[#infos+1]=#header
            elseif n:trim()=="|" then
                --skip
            elseif n:trim()~="" then
                header[#header+1]={name=n,start=st-#n,stop=ed}
                curr=header[#header]
                prev=curr
            end
        end
        if #header==0 then return end
        for i=#infos,1,-1 do 
            infos[i]=table.remove(header,infos[i])
            header[#header+1]=infos[i]
        end
        prev.stop=-1
    end
    local rows={pattern and header or {}}
    for i=pattern and 1 or 2,#plan do
        local row={}
        local line=plan[i]
        local bytes,chars
        if pattern then
            row={line:match(pattern)}
            --the time field
            --row[2]=tonumber(row[2]) and tonumber(row[2])*1000 or row[2]
        else
            for j,n in ipairs(header) do
                if i==2 then rows[1][j]=n.name end
                if j==1 then
                    bytes,chars=line:match('^.- %d+'):ulen()
                    bytes=bytes-chars
                    row[j]=line:sub(n.start,n.stop+bytes)
                else
                    row[j]=line:sub(n.start+bytes,n.stop+bytes)
                end
                row[j]=j==1 and row[j]:rtrim() or row[j]:trim()
                row[j]=tonumber(row[j]) or row[j]
                if type(row[j])=='string' and not n.name:lower():find(' info',1,true) then
                    row[j]=row[j]:gsub('%s*N/A%s*',''):gsub('^B$','')
                end
                if row[j]=='|' then
                    row[j]=''
                end
            end
        end
        rows[#rows+1]=row
    end
    --env.set.doset('colsep','|','rowsep','-')
    --grid.print(rows)
    self:build_json(rows)
    return true
end

function tidb.parse_explain_option(analyze,format)
    if analyze and analyze~='' then
        return 'analyze'
    elseif format then
        format=format:lower()
        if format=='row' then
            return "FORMAT='ROW'"
        else
            return ''
        end
    else
        return ''
    end
end

function tidb:onload()
    env.event.snoop('ON_PARSE_PLAN',function(self,data)
        if  type(data[2])=='string' and (data[2]:find('FORMAT=TREE',1,1) or data[2]:find('FORMAT=TRADITIONAL')) then
            return
        end
        if data[1] and self:parse_plan(data[1])~=false then data[1]=nil end 
    end,self)
end

function tidb:finalize()
    env.set_command(self,"tiplan",nil,self.parse_plan,false,2)
    for _,n in ipairs{'TRACE','MODIFY','ADMIN','BACKUP','RECOVER','RESTORE','FLASHBACK'} do
        env.set_command(db,n,"#TiDB command",db.command_call,true,1,true)
    end
end

return tidb.new()