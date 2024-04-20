local db=env.getdb()

local tidb=env.class(db.C.sql)
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

function tidb:parse_plan(plan)
    env.checkhelp(plan,"Missing plan file or plan text.")
    if #plan<128 and os.exists(plan) then
        plan=env.load_data(plan,false)
    elseif not plan:find('%s') and env.var.inputs[plan:upper()] then
        plan=env.var.inputs[plan:upper()]
    elseif env.var.outputs[plan:upper()] then
        return
    end
    plan=plan:gsub('\r',''):gsub('\t','    '):split('\n')
    local header={}
    local curr,prev=nil
    local infos,ped={}
    for n,s,c,st,ed in (plan[1]:rtrim()..' '):gsplit('%s+') do
        if not ped then ped=ed end
        if n:lower():find('^info') then
            prev.name=prev.name..' '..n
            prev.stop=ed
            infos[#infos+1]=#header
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
        for j,n in ipairs(header) do
            if i==2 then rows[1][j]=n.name end
            row[j]=line:sub(n.start,n.stop)
            row[j]=j==1 and row[j]:rtrim() or row[j]:trim()
            row[j]=tonumber(row[j]) or row[j]
            if n.name:lower():find('^oper') then
                row[j]=row[j]:gsub('|','\n|')
            elseif n.name:lower():find('^exe') then
                row[j]=row[j]:gsub(',%s*',',\n')
            elseif row[j]=='N/A' then
                row[j]=''
            end
        end
        rows[#rows+1]=row
    end
    --env.set.doset('colsep','|','rowsep','-')
    grid.print(rows)
end

function tidb:finalize()
    env.set_command(self,"tiplan",nil,self.parse_plan,false,2)
    for _,n in ipairs{'TRACE','MODIFY','ADMIN','BACKUP','RECOVER','RESTORE','FLASHBACK'} do
        env.set_command(db,n,"#TiDB command",db.command_call,true,1,true)
    end
end

return tidb.new()