local env,pairs,ipairs,table,tonumber=env,pairs,ipairs,table,tonumber
local sleep,math,cfg=env.sleep,env.math,env.set

local snapper=env.class(env.scripter)
function snapper:ctor()
    self.command="snap"
    self.ext_name='snap'
    self.help_title='Calculate a period of db/session performance/waits. '
    self.usage='<name1>[,<name2>...] <interval>|BEGIN|END [args]'
end

function snapper:parse(name,txt,args,file)
    txt=loadstring(('return '..txt):gsub(self.comment,"",1))
    env.checkerr(txt,"Invalid syntax in "..file)

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
    cmd.top_grp_cols=cmd.top_grp_cols and (','..cmd.top_grp_cols:upper()..',')
    cmd.tops=tonumber(cmd.tops) or 1
    cmd.agg_cols=','..(cmd.agg_cols and cmd.agg_cols:upper() or '')..','
    cmd.name=name

    return cmd,args
end

function snapper:after_script()
    if self.start_flag then
        self.start_flag=false
        self:trigger('after_exec_action')
        self.db:commit()
        cfg.set("feed","back")
        cfg.set("digits","back")
        cfg.set("sep4k","back")
    end
end

function snapper:get_time()
    return self:trigger('get_db_time') or "unknown"
end

function snapper:run_sql(sql,main_args,cmds,files)
    local db,print_args=self.db
    cfg.set("feed","off")
    cfg.set("autocommit","off")
    cfg.set("digits",2)
    cfg.set("sep4k","on")
    
    local interval=main_args[1].V1
    local snap_cmd

    if interval~="END" then
        for i=20,1,-1 do
            local pos="V"..i
            local str=main_args[1][pos]
            if str and str ~= db_core.NOT_ASSIGNED then
                if str:find("%s") then
                    for k,v in pairs(main_args) do
                        main_args[k].V1="END"
                        if v[pos]==str then v[pos]=db_core.NOT_ASSIGNED end
                    end
                    snap_cmd=str 
                    interval="BEGIN"
                end
                break
            end
        end
    end

    local args={}
    for k,v in pairs(main_args) do
        if type(v)=="table" then
            args[k]={}
            for x,y in pairs(v) do args[k][x]=y end
        else
            args[k]=v
        end
    end

    local begin_flag
    if interval then
        interval=interval:upper()
        if interval=="END" then
            if self.start_time then self:next_exec() end
            return 
        elseif interval=="BEGIN" then
            begin_flag=true
        end
    end

    env.checkerr(begin_flag~=nil or tonumber(interval),'Uage: '..self.command..' <names> <interval>|BEGIN|END [args] ')
    
    self.db:assert_connect()
    
    self.cmds,self.args,self.start_time={},{},self:get_time()
    self.start_flag=true
    env.set.set("feed","off")
    self:trigger('before_exec_action')
    local clock=os.clock()
    
    for idx,text in ipairs(sql) do
        for i=1,20 do
            args[idx]['V'..i]=args[idx]['V'..(i+1)]
        end

        local cmd,arg=self:parse(cmds[idx],sql[idx],args[idx],files[idx])
        self.cmds[cmds[idx]],self.args[cmds[idx]]=cmd,arg
        if cmd.before_sql then
            env.eval_line(cmd.before_sql,true,true) 
        end
        local rs=db:exec(cmd.sql,arg)
        if type(rs)=="userdata" then
            cmd.rs2=self.db.resultset:rows(rs,-1)
            --grid.print(cmd.rs2)
        end
    end
    db:commit()

    if not begin_flag then
        sleep(interval+clock-os.clock()-0.1)
        self:next_exec()
    elseif snap_cmd then
        env.eval_line(snap_cmd,true,true)
        self:next_exec()
    end
end

function snapper:next_exec()
    local cmds,args,start_time,db=self.cmds,self.args,self.start_time,self.db
    self.start_time=nil
    --self:trigger('before_exec_action')
    db:commit()
    local end_time=self:get_time()
    for name,cmd in pairs(cmds) do
        local rs=db:exec(cmd.sql,args[name])
        if cmd.rs2 and type(rs)=="userdata" then
            cmd.rs1=self.db.resultset:rows(rs,-1)
            --grid.print(cmd.rs1)
        end
        if cmd.after_sql then
            env.eval_line(cmd.after_sql,true,true) 
        end 
    end


    local result,groups={}
    for name,cmd in pairs(cmds) do
        if cmd.rs1 and cmd.rs2 then
            local agg_idx,grp_idx,top_grp_idx,agg_model_idx={},{},{},{}
            local title=cmd.rs1[1]
            local min_agg_pos,top_agg_idx,top_agg=1e4
            for i,k in ipairs(title) do
                local idx=cmd.agg_cols:find(','..k:upper()..',',1,true)
                if idx then
                    if min_agg_pos> idx then
                        min_agg_pos,top_agg=idx,i
                    end
                    agg_idx[i],title[i]=idx,'*'..k
                else
                    if not cmd.grp_cols or cmd.grp_cols:find(','..k:upper()..',',1,true) then
                        grp_idx[i]=true
                    end

                    if cmd.top_grp_cols and cmd.top_grp_cols:find(','..k:upper()..',',1,true) then
                        top_grp_idx[i]=true
                    end
                end
            end

            if not cmd.top_grp_cols then top_grp_idx=grp_idx end

            result,groups=table.new(1,#cmd.rs1+10),{}
            cmd.grid=grid.new()
            cmd.grid:add(title)

            local idx,top_idx,counter={},{},0
            local function make_index(row)
                counter=0
                for k,_ in pairs(top_grp_idx) do
                    counter=counter+1
                    top_idx[counter]=row[k] or ""
                end

                counter=0        
                for k,_ in pairs(grp_idx) do
                    counter=counter+1
                    idx[counter]=row[k] or ""
                end
                return table.concat(idx,'\1\2\1'),table.concat(top_idx,'\1\2\1')
            end

            table.remove(cmd.rs1,1)
            table.remove(cmd.rs2,1)

            local top_data,r,d,data,index,top_index=table.new(1,#cmd.rs1+10)
            for _,row in ipairs(cmd.rs1) do
                index,top_index=make_index(row)
                data=result[index]
                if not top_data[top_index] then 
                    top_data[top_index]={}
                    groups[#groups+1]=top_index
                end
                if not data then
                    result[index],top_data[top_index][#top_data[top_index]+1]=row,row
                    data,row=row,{}
                end
                local sum=0
                for k,_ in pairs(agg_idx) do
                    r,d=tonumber(row[k]),tonumber(data[k])
                    if r or d then 
                        data[k]=math.round((d or 0)+(r or 0),2) 
                        sum=(sum==1 or data[k]>0) and 1 or 0
                    end
                end
                result[index]['_non_zero_']=sum>0
            end

            for _,row in ipairs(cmd.rs2) do
                index=make_index(row)
                data=result[index]
                if data then
                    local sum=0
                    for k,_ in pairs(agg_idx) do
                        r,d=tonumber(row[k]),tonumber(data[k])
                        if r and d then 
                            data[k]=d-math.round(r,2) 
                            sum=(sum==1 or data[k]>0) and 1 or 0
                        else
                            sum=(sum==1 or d>0) and 1 or 0
                        end
                    end
                    result[index]['_non_zero_']=sum>0
                end
            end

            if #groups>0 then
                local func=function(a,b) return a[top_agg_idx]>b[top_agg_idx] end
                for index,group_name in ipairs(groups) do
                    if #top_data[group_name]>1 and top_agg_idx then
                        table.sort(top_data[group_name],func)
                    end
                    if top_data[group_name][1]['_non_zero_'] then
                        cmd.grid:add(top_data[group_name][1])
                    end
                end
                idx=''
                for i,_ in pairs(agg_idx) do
                    idx=idx..(-i)..','
                    if cmd.set_ratio~='off' then cmd.grid:add_calc_ratio(i) end
                end
                cmd.grid:sort(idx,true)
            end
            local title=("\n["..(self.command..'#'..name):upper().."]: From "..start_time.." to "..end_time..":\n"):format(name)
            print(title..string.rep("=",title:len()-2))
            cmd.grid:print(nil,nil,nil,cmd.max_rows or cfg.get(self.command.."rows"))
        end
    end
    self.db:commit()
    self:trigger('after_exec_action')
end


function snapper:__onload()
    cfg.init(self.command.."rows","50",nil,"db.core","Number of max records for the '"..self.command.."' command result","5 - 3000")
end

return snapper