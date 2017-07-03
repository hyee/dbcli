local env,pairs,ipairs,table,tonumber=env,pairs,ipairs,table,tonumber
local sleep,math,cfg=env.sleep,env.math,env.set

local snapper=env.class(env.scripter)
function snapper:ctor()
    self.command="snap"
    self.ext_name='snap'
    self.help_title='Calculate a period of db/session performance/waits. '
    self.usage=[[<name1>[,<name2>...] { {<seconds>|BEGIN|END} [args] | [args] "<command to be snapped>"}
        1. calc the delta stats within a specific seconds: @@NAME <name1>[,<name2>...] $PROMPTCOLOR$<seconds>$NOR$ [args]
        2. calc the delta stats for a specific series of commands:
           1) @@NAME <name1>[,<name2>...] $PROMPTCOLOR$BEGIN$NOR$ [args]
           2) <run other commands>
           3) @@NAME <name1>[,<name2>...] $PROMPTCOLOR$END$NOR$
        3. calc the delta stats for a specific command: @@NAME <name1>[,<name2>...] [args] "<command to be snapped>"
        4. calc the delta stats for a specific series of commands:
           @@NAME <name1>[,<name2>...] [args] $PROMPTCOLOR$<<EOF$NOR$
               <run other commands>
           $HIY$EOF$NOR$
    Of which:
        $HEADCOLOR$<name1>[,<name2>...]$NOR$ is the snap commands listed below
        $HEADCOLOR$args$NOR$ is the parameter that required for the specific script
        $HEADCOLOR$EOF$NOR$ is the unix EOF style, the keyword is not limited to just 'EOF'
    ]]
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
                if str:trim():find("%s") then
                    local command=env.parse_args(2,str)
                    if command and command[1] and env._CMDS[command[1]:upper()] then
                        snap_cmd=str 
                        interval="BEGIN"
                    end
                end
                break
            end
        end
    end

    local args={}

    for k,v in pairs(main_args) do
        if type(v)=="table" then
            local idx=0;
            args[k]={}
            for i=1,20 do
                local x="V"..i
                local y=tostring(v[x]):upper()
                if not (v[x]==snap_cmd or i==1 and (tonumber(y) or y=="END" or y=="BEGIN"))
                then
                    idx=idx+1
                    args[k]["V"..idx]=v[x]
                end
            end
            for x,y in pairs(v) do
                if not tostring(x):find('^V%d+$') then
                    args[k][x]=y
                end 
            end
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
        local cmd,arg=self:parse(cmds[idx],sql[idx],args[idx],files[idx])
        self.cmds[cmds[idx]],self.args[cmds[idx]]=cmd,arg
        arg.snap_cmd=snap_cmd or ''
        if cmd.before_sql then
            env.eval_line(cmd.before_sql,true,true) 
        end
        local rs=db:exec(cmd.sql,arg)
        if type(rs)=="userdata" then
            cmd.rs2=self.db.resultset:rows(rs,-1)
        end
    end
    db:commit()
    if snap_cmd then
        env.eval_line(snap_cmd,true,true)
        self:next_exec()
    elseif not begin_flag then
        sleep(interval+clock-os.clock()-0.1)
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
                result[index]['_non_zero_']=sum>0 or cmd.include_zero
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
                    result[index]['_non_zero_']=sum>0 or cmd.include_zero
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
                cmd.grid:sort(cmd.sort or idx,true)
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