local env=env
local sleep,math,cfg=env.sleep,env.math,env.set
local cfg_backup

local snapper=env.class(env.scripter)
function snapper:ctor()
    self.command="snap"
    self.ext_name='snap'
    self.help_title='Calculate a period of db/session performance/waits. '
    self.usage='[<interval>|begin|end> <name1[,name2...]] [args]'
end

function snapper:fetch(cmd,pos)
    local row
    local grp_idx,idx=cmd.grp_idx,{}
    local counter
    local rs=cmd['rs'..pos]
    while true do
        row=self.db.resultset:fetch(rs)
        if not row then
            cmd['rs'..pos]=nil
            return coroutine.yield(cmd.name,0)
        end
        counter=0
        for k,_ in pairs(grp_idx) do
            counter=counter+1
            idx[counter]=row[k] or ""
        end
        coroutine.yield(cmd.name,pos,table.concat(idx,'\1'),row)
    end
end

function snapper:parse(name,args)
    local txt,print_args,file
    txt,args,print_args,file=self:get_script(name,args)
    txt=loadstring(('return '..txt):gsub(self.comment,"",1))

    if not txt then
       return print("Invalid syntax in "..file)
    end

    local cmd={}
    for k,v in pairs(txt()) do
        cmd[tostring(k):lower()]=v
    end

    for _,k in ipairs({"sql","agg_cols"}) do
        if not cmd[k] then
            return print("Cannot find key '"..k.."'' in "..file)
        end
    end

    cmd.grp_cols=cmd.grp_cols and (','..cmd.grp_cols:upper()..',') or nil
    cmd.agg_cols=','..cmd.agg_cols:upper()..','
    cmd.name=name

    return cmd,args
end

function snapper:after_exec()
    self.db:commit()
    cfg.restore(cfg_backup)
    self:trigger('after_exec_action')
end

function snapper:get_time()
    return self:trigger('get_db_time') or "unknown"
end

function snapper:exec(interval,typ,...)
    local db,print_args=self.db
    cfg_backup=cfg.backup()
    cfg.set("feed","off")
    cfg.set("autocommit","off")
    cfg.set("digits",2)

    if not self.cmdlist then
        self.cmdlist=self:rehash(self.script_dir,'snap')
    end

    if not interval then
        return env.helper.helper(self.command)
    end

    interval=interval:upper()

    if interval:sub(1,1)=="-" then
        return self:get_script(interval,{typ,...})
    end

    local begin_flag
    if interval=="END" and snapper.start_time then
        self:next_exec()
        return;
    elseif interval=="BEGIN" then
        begin_flag=true
    end

    if not (begin_flag or tonumber(interval)) or not typ then
        return print("please set the interval and names.")
    end

    if not db:is_connect() then
        env.raise("database is not connected!")
    end

    local args={...}
    for i=1,9 do
        args["V"..i]=args[i] or ""
    end

    local cmds,cmd={}

    for v in typ:gmatch("([^\n\t%s,]+)") do
        v=v:upper()
        if not self.cmdlist[v] then
            return print("Error: Cannot find command :" .. v)
        end
        cmd,args=self:parse(v,args)
        if not cmd then return end
        cmds[v]=cmd
    end


    local start_time=self:get_time()
    self:trigger('before_exec_action')
    local clock=os.clock()
    for _,cmd in pairs(cmds) do cmd.rs2=db:exec(cmd.sql,args) end
    db:commit()
    self.cmds,self.start_time,self.args=cmds,start_time,args

    if not begin_flag then
        sleep(interval+clock-os.clock()-0.1)
        self:next_exec()
    end
end

function snapper:next_exec()
    local cmds,args,start_time,db=self.cmds,self.args,self.start_time,self.db
    self.start_time=nil

    local end_time=self:get_time()
    for _,cmd in pairs(cmds) do
        cmd.rs1=db:exec(cmd.sql,args)
    end
    db:commit()
    self:trigger('after_exec_action')
    local result={}
    local cos={}
    for name,cmd in pairs(cmds) do
        cmd.agg_idx,cmd.grp_idx={},{}
        cmd.title=db.resultset:fetch(cmd.rs1),db.resultset:fetch(cmd.rs2)
        for i,k in ipairs(cmd.title) do
            if cmd.agg_cols:find(','..k:upper()..',',1,true) then
                cmd.agg_idx[i]=true
                cmd.title[i]='*'..k
            elseif not cmd.grp_cols or cmd.grp_cols:find(','..k:upper()..',',1,true) then
                cmd.grp_idx[i]=true
            end
        end
        result[name]={}
        cmd.grid=grid.new()
        cmd.grid:add(cmd.title)
        table.insert(cos,coroutine.create(function() self:fetch(cmd,1) end))
        table.insert(cos,coroutine.create(function() self:fetch(cmd,2) end))
    end

    while #cos>0 do
        local succ,rtn,pos,key,value
        for k=#cos,1,-1 do
            succ,name,pos,key,row=coroutine.resume(cos[k])

            local agg_idx=name and cmds[name].agg_idx
            if not row then
                --print(succ,name,pos,key,row,cmds.rs1,cmds.rs2)
                table.remove(cos,k)
            else
                if not result[name][key] then result[name][key]={} end
                value=result[name][key]
                if not value[pos] then
                    value[pos]=row
                    if pos==1 then
                        cmds[name].grid:add(row)
                        value.indx=#cmds[name].grid.data
                    end
                else
                    for k,_ in pairs(agg_idx) do
                        if tonumber(value[pos][k]) or tonumber(row[k]) then
                            value[pos][k]= math.round((tonumber(value[pos][k]) or 0)+(tonumber(row[k]) or 0),2)
                        end
                    end
                end
                if value[1] and value[2] then
                    local counter=0
                    for k,_ in pairs(agg_idx) do
                        if tonumber(value[1][k]) and value[2][k] then
                            value[1][k]=math.round(value[1][k]-value[2][k],2)
                            if value[1][k]>0 then counter=1 end
                        end
                    end

                    --if counter==0 then cmds[name].grid.data[value.indx]=nil end
                    result[name][key][2]=nil
                end
            end
        end
    end


    for name,cmd in pairs(cmds) do
        local idx=""

        local counter
        local data=cmd.grid.data

        for i=#data,2,-1 do
            counter=0
            for j,_ in pairs(cmd.agg_idx) do
                if data[i][j]>0 then
                    counter=1
                    break
                end
            end
            --if dalta value is 0, then remove the data
            --if counter==0 then table.remove(data,i) end
        end


        for i,_ in pairs(cmd.agg_idx) do
            idx=idx..(-i)..','
            if cmd.set_ratio~='off' then cmd.grid:add_calc_ratio(i) end
        end
        cmd.grid:sort(idx,true)
        local title=("\n"..name..": From "..start_time.." to "..end_time..":\n"):format(name)
        print(title..string.rep("=",title:len()-2))
        cmd.grid:print(nil,nil,nil,cmd.max_rows or cfg.get(self.command.."rows"))
    end
end


function snapper:__onload()
    cfg.init(self.command.."rows","50",nil,"db.core","Number of max records for the '"..self.command.."' command result","5 - 3000")
    env.remove_command(self.command)
    env.set_command(self,self.command,self.helper,{self.exec,self.after_exec},false,21)
end

return snapper