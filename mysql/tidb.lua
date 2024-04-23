local db=env.getdb()
local tidb=env.class(db.C.sql)

local access='access object'
local config={
    root='Plan',
    child='Plans',
    processor=function(name,value,row,node)
        --if not name and node then end
        return value
    end,
    keep_indent=1,
    columns={
            {'id','Operation'},'|',
            {access,'Access Info'},'|',
            {'task',"Task|Name"},'|',
            {'estRows',"Est|Rows",format='TMB2'},{'actRows',"Act|Rows",format='TMB2'},'|',
            {'time',"Act|Time",format='msmhd2'},'|',
            {'loops',"Act|Loops",format='TMB2'},'|',
            {'concurrency',"Act|Conc",format='TMB2'},'|',
            {'memory','Memory',format='KMG2'},{'disk','Disk',format='KMG2'},'|',
            {'operator info',"Operator Info",format='TMB2'},'|'
            },
    sorts=false,        
    --percents={"time"},
    title='Plan Tree | Conc: Concurrency',
    --projection="operator info"
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

function tidb:build_json(plan)
    local nodes={}
    local json={[config.root]={[config.child]=nodes}}
    local headers=plan[1]
    local units={
        KB=1024,
        MB=1024^2,
        GB=1024^3,
        TB=1024^4,
        BYTES=1,
        BYTE=1,
        K=1000,
        M=1000^2,
        T=1000^3
    }
    local function extract_num(val)
        if not val then return nil end
        if tostring(val):upper()=='N/A' then return 0 end
        local num,unit=tostring(val):match("^%s*(%-?[%.0-9]+)%s*(%S+)$")
        if not num then return val end
        unit=unit:upper()
        if not units[unit] then return val end
        return tonumber(num)*units[unit]
    end

    --find access object field id
    local access_index
    for c,n in ipairs(headers) do
        if n==access then
            access_index=c
            break
        end
    end

    local patterns1={'^(%s*(%S[^:]+):%s*(%b{}),?)','^(%s*(%S[^:{}]+):%s*([^,:{}]+),?)'}
    local patterns2={'^(%s*([a-zA-Z0-9 ]+%s*:%s*%S[^,]+)%s*,)','^(%s*([%.a-zA-Z0-9_ ]+)%s*,)'}
    for i=2,#plan do
        local row={}
        for j,col in ipairs(plan[i]) do
            local name=headers[j]
            if name=='execution info' then
                while true do
                    local piece,k,v=col:match(patterns1[1])
                    if not piece then piece,k,v=col:match(patterns1[2]) end
                    if not piece then break end
                    col=col:sub(#piece+1)
                    row[k]=extract_num(v)
                end
                col=nil
            elseif name=='operator info' then
                if col:find('^Column#') then
                    col=nil
                else
                    col=col:gsub(',%s*start_time:.*','')
                    if (plan[i][access_index or -1] or '')=='' then
                        local piece,v=(col..','):match(patterns2[1])
                        if not piece or v:find('Column#',1,true) then
                            piece,v=(col..','):match(patterns2[2])
                        end
                        if piece then
                            col=col:sub(#piece+1):ltrim()
                            row[access]=v
                        end
                    end
                end
            end
            row[name]=extract_num(col)
        end
        nodes[i-1]=row
    end
    --print(table.dump(json))
    env.json_plan.parse_json_plan(env.json.encode(json),config)
end

function tidb:parse_cursor(plan)
    local header=plan[1]
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
    local start_=plan:sub(1,4096):find('%s*id%s[^\n\r]*task%s[^\n\r]*estRows%s')
    if not start_ then return false end
    plan=plan:sub(start_)
    plan=plan:gsub('\r',''):gsub('\t','    '):split('\n')
    local header={}
    local curr,prev=nil
    local infos,ped={}
    for n,s,c,st,ed in (plan[1]:rtrim()..' '):gsplit('%s+') do
        if not ped then ped=ed end
        if n:lower():find('^info') then
            prev.name=prev.name..' '..n
            prev.stop=ed
            
            --if prev.name~='operator info' then
                infos[#infos+1]=#header
            --else
            --    header[#header]=nil
            --end
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
    local rows={{}}
    for i=2,#plan do
        local row={}
        local line=plan[i]
        local bytes,chars,prefix=0
        for j,n in ipairs(header) do
            if i==2 then rows[1][j]=n.name end
            if j==1 then
                bytes,chars,prefix=line:match('^.- %d+'):ulen()
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

function tidb:finalize()
    env.set_command(self,"tiplan",nil,self.parse_plan,false,2)
    for _,n in ipairs{'TRACE','MODIFY','ADMIN','BACKUP','RECOVER','RESTORE','FLASHBACK'} do
        env.set_command(db,n,"#TiDB command",db.command_call,true,1,true)
    end
end

return tidb.new()