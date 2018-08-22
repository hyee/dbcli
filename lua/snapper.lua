--[[
    Snapper: to generate delta stats based on specific period.
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Script template can be either Lua or JSON format, elements:
    Mandatory:
        sql: can be a SQL string, or an array that in Lua/Json format, refer to command 'grid' for more detail
    Optional:
        1. group_by: Optional, the columns that used for groupping the aggregation(similar to SQL 'GROUP BY' list)
                     The columns that not listed in both 'group_by' and 'delta_by' will only show the post result
        2. delta_by: Optional, the columns that for aggregation(similar to SQL 'SUM(...)' list)
        3. order_by: The columns that used to sort the final result, "-<column_name>" means desc ordering. 
        4. top_by  : Optional, if not specified then it equals to 'group_by', it is the subset of 'group_by' columns
        5. per_second: 'on' or 'off'(default), controls if to devide the delta stats by elapsed seconds
        6. bypassemptyrs: 'on' or 'off'(default),when a 'sql' is an array, and one of which returns no rows, then controls whether to show this sql
        7. top_mode: 'on' or 'off'(default), controls whether to clear the screen before print the result
        8. calc_rules: the additional formula on a specific column after the 'delta_by' columns is calculated
        9.fixed_title: true or false(default), controls whether not to change the 'delta_by' column titles
        10.include_zero:  true or false(default), controls whether not to show the row in case of its 'delta_by' columns are all 0
        11.set_ratio: true or false(default), controls whether not to add a percentage column on each 'delta_by' columns
        12.before_sql: the statements that executed before the 1st snapshot
        13.after_sql: the statements that executed after the 2nd snapshot

    The belowing variables can be referenced by the SQLs in 'snapper':
    1. :snap_cmd      :  The command that included by EOF
    2. :snap_interval :  The elapsed seconds betweens 2 snapshots
--]]
local env,pairs,ipairs,table,tonumber,pcall,type=env,pairs,ipairs,table,tonumber,pcall,type
local sleep,math,cfg=env.sleep,env.math,env.set
local console,getHeight=console,console.getScreenHeight

local snapper=env.class(env.scripter)
function snapper:ctor()
    self.command="snap"
    self.ext_name='snap'
    self.help_title='Calculate a period of db/session performance/waits. '
    self.usage=[[<name1>[,<name2>...] { {<seconds>|BEGIN|END} [args] | [args] "<command to be snapped>"} [-top] [-sec]
    Options:
        -top: show result in top-style
        -sec: show delta stats based on per second, instead of the whole period
    Description:
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
        5. calc the delta stats with repeat interval:
           @@NAME <name1>[,<name2>...] $PROMPTCOLOR$<seconds>+$NOR$ [args]
           @@NAME <name1>[,<name2>...] $PROMPTCOLOR$+$NOR$ [args] <"command"|EOF commands>
    Of which:
        $HEADCOLOR$<name1>[,<name2>...]$NOR$ is the snap commands listed below
        $HEADCOLOR$args$NOR$ is the parameter that required for the specific script
        $HEADCOLOR$EOF$NOR$ is the unix EOF style, the keyword is not limited to just 'EOF'
    ]]
end

function snapper:parse(name,txt,args,file)
    txt=env.var.update_text(txt,1,args)
    txt=table.totable(txt)

    local cmd={}
    for k,v in pairs(txt) do
        cmd[tostring(k):lower()]=v
    end

    cmd.name=name
    return cmd,args
end

function snapper:after_script()
    if self.var_context then
        env.var.import_context(table.unpack(self.var_context))
        self.var_context=nil
    end
    if self.start_flag then
        self.start_flag,self.snap_cmd,self.is_repeat=false
        self:trigger('after_exec_action')
        self.db:commit()
        cfg.set("feed","back")
        cfg.set("digits","back")
        cfg.set("sep4k",'back')
    end
end

function snapper:get_time()
    return self:trigger('get_db_time') or "unknown"
end

function snapper:build_data(sqls,args)
    local clock,time=os.timer(),os.date('%Y-%m-%d %H:%M:%S')
    local rs,rsidx=nil,{}

    if type(sqls)=="string" then
        rs=self.db:exec(sqls,args)
        if type(rs)=="userdata" then
            rs={self.db.resultset:rows(rs,-1)}
            rs[1]._is_result=true
        elseif type(rs)=="table" then
            for k,v in ipairs(rs) do 
                rs[k]=db.resultset:rows(v,-1)
                rs[k]._is_result=true
            end
        else
            rs=nil
        end
    else
        rs=self.db:grid_call(sqls,-1,args)
    end

    local function scanrs(rs)
        for k,v in ipairs(rs) do
            if type(v)=="table" then 
                if not rs[k]._is_result then
                    scanrs(v)
                else
                    rsidx[#rsidx+1]=v
                end
            end
        end
    end

    if type(rs)=="table" then
        scanrs(rs)
        rs.rsidx=rsidx
    end

    return rs,clock,time,os.timer()-clock
end

function snapper:run_sql(sql,main_args,cmds,files)
    local db,print_args=self.db
    cfg.set("feed","off")
    cfg.set("autocommit","off")
    cfg.set("digits",2)
    cfg.set("sep4k",'on')
    self.var_context={env.var.backup_context()}
    
    local interval=main_args[1].V1
    local args={}
    self.is_repeat=false
    local itv=interval:match("^(%d*)%+$")
    if itv then
        if itv=='' then itv='1' end 
        interval,self.is_repeat=itv,tonumber(itv)
    end

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

    self.snap_cmd=snap_cmd
    self.per_second,self.top_mode=nil

    for k,v in pairs(main_args) do
        if type(v)=="table" then
            local idx=0;
            args[k]={}
            for i=1,20 do
                local x="V"..i
                local y=tostring(v[x]):upper()
                if y=="-SEC" then
                    self.per_second=true
                elseif y=="-TOP" then
                    self.top_mode=true
                elseif not (v[x]==snap_cmd or i==1 and (tonumber(interval) or self.is_repeat or y=="END" or y=="BEGIN")) then
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
            if self.start_time then 
                self.start_time=nil
                self:next_exec() 
            end
            return
        elseif interval=="BEGIN" then
            self.start_time=os.clock()
            begin_flag=true
        end
    end

    env.checkerr(begin_flag~=nil or tonumber(interval),'Uage: '..self.command..' <names> <interval>|BEGIN|END [args] ')
    
    self.db:assert_connect()
    
    self.cmds,self.args={},{}
    self.start_flag=true
    env.set.set("feed","off")
    self:trigger('before_exec_action')
    local clock=os.timer()
    for idx,text in ipairs(sql) do
        local cmd,arg=self:parse(cmds[idx],sql[idx],args[idx],files[idx])
        self.cmds[cmds[idx]],self.args[cmds[idx]]=cmd,arg
        arg.snap_cmd=(snap_cmd or ''):sub(1,2000)
        arg.snap_interval=tonumber(interval) or 0
        if cmd.before_sql then
            env.eval_line(cmd.before_sql,true,true) 
        end
        cmd.rs2,cmd.clock,cmd.starttime,cmd.fetch_time2=self:build_data(cmd.sql,arg)
    end
    self.db:commit()
    if snap_cmd then
        env.eval_line(snap_cmd,true,true)
        self:next_exec()
    elseif not begin_flag then
        local timer=interval+clock-os.timer()
        if timer>0 then sleep(timer) end
        self:next_exec()
    end
end

function snapper:next_exec()
    local cmds,args,db,clock=self.cmds,self.args,self.db,os.timer()
    --self:trigger('before_exec_action')
    for name,cmd in pairs(cmds) do
        self.db.grid_cost=nil
        local rs,clock,starttime,fetch_time1=self:build_data(cmd.sql,args[name])
        if self.db.grid_cost then 
            args[name].snap_interval=clock - cmd.clock + self.db.grid_cost
        else
            local timer2=os.timer()
            args[name].snap_interval=timer2-cmd.clock-(timer2-clock)/2
        end
        if type(cmd.rs2)=="table" and type(rs)=="table" then
            cmd.rs1,cmd.clock,cmd.endtime,cmd.elapsed,cmd.fetch_time1=rs,clock,starttime,clock-cmd.clock,fetch_time1
        end
        if cmd.after_sql then
            env.eval_line(cmd.after_sql,true,true) 
        end
    end
    self.db:commit()

    local result,groups={}
    local define_column=env.var.define_column
    for name,cmd in pairs(cmds) do
        if cmd.rs1 and cmd.rs2 then
            local calc_clock,formatter=os.timer(),cmd.column_formatter or {}
            local defined_formatter={}
            for k,v in pairs(formatter) do
                define_column(v,'format',k)
                local cols=v:split('%s*,%s*')
                for _,col in ipairs(cols) do
                    defined_formatter[col:upper()]=k
                end
            end

            for idx,_ in ipairs(cmd.rs1.rsidx) do
                local rs1,rs2=cmd.rs1.rsidx[idx],cmd.rs2.rsidx[idx]
                local agg_idx,grp_idx,top_grp_idx,agg_model_idx,found_top={},{},{},{}
                local title=rs2[1]
                local cols=#title
                local min_agg_pos,top_agg_idx,top_agg=1e4
                local is_groupped=false
                local calc_cols={}
                local props={}
                for k,v in pairs(cmd) do if type(k)=="string" then props[k]=v end end
                for k,v in pairs(rs2) do if type(k)=="string" then props[k]=v end end
                props.per_second=(props.per_second~=nil and props.per_second) or self.per_second
                local calc_rules=props.calc_rules or {}
                local order_by=props.order_by
                local elapsed=(props.per_second=='on' or props.per_second==true) and props.elapsed or 1
                props.group_by=props.group_by or props.grp_cols
                props.top_by=props.top_by or props.top_grp_cols
                props.delta_by=props.delta_by or props.agg_cols
                props.group_by=props.group_by and (','..props.group_by:upper()..',') or nil
                props.top_by=props.top_by and (','..props.top_by:upper()..',')
                props.delta_by=','..(props.delta_by and props.delta_by:upper() or '')..','

                if type(order_by)=="string" then order_by=(','..order_by:upper()..','):gsub('%s*,[%s,]*',',') end

                for k,v in pairs(calc_rules) do
                    if type(k)=="string" then calc_rules[k:upper()]=v end
                end

                for i,k in ipairs(title) do
                    local tit=k:upper()
                    local idx=props.delta_by:find(','..tit..',',1,true)
                    if calc_rules[tit] then
                        local v=calc_rules[tit]:upper()
                        for i,x in ipairs(rs1[1]) do
                            v=v:replace('['..x:upper()..']','\1'..i..'\2',true)
                        end
                        calc_cols[i]='return '..v
                    end
                    if idx then
                        is_groupped=true
                        if min_agg_pos> idx then
                            min_agg_pos,top_agg=idx,i
                        end
                        agg_idx[i],title[i]=idx,props.fixed_title  and k  or elapsed~=1 and not props.topic and (k..'/s') or ('*'..k)
                        local fmt = defined_formatter[title[i]] or defined_formatter[tit]
                        if fmt then define_column(title[i],'format', fmt) end
                        if type(order_by)=="string" then
                            if order_by:find(',-'..tit..',',1,true) then
                                order_by=order_by:replace(',-'..tit..',',',-'..title[i]..',',true)
                            end
                            if order_by:find(','..tit..',',1,true) then
                                order_by=order_by:replace(','..tit..',',','..title[i]..',',true)
                            end
                        end
                    else
                        if not props.group_by or props.group_by:find(','..tit..',',1,true) then
                            grp_idx[i]=true
                        end

                        if props.top_by and props.top_by:find(','..tit..',',1,true) then
                            found_top=true
                            top_grp_idx[i]=true
                        end
                    end
                end

                if type(order_by)=="string" then
                    order_by=order_by:trim(',')
                end

                if not found_top then top_grp_idx=grp_idx end

                result,groups=table.new(1,#rs1+10),{}
                local grid=grid.new(true)
                
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

                local top_data,r,d,data,index,top_index=table.new(1,#rs1+10)
                props.max_rows=props.height==0 and 300 or props.max_rows or cfg.get(self.command.."rows")
                if not is_groupped then
                    grid=rs1
                    if order_by then grid.sort(grid,order_by) end
                else
                    local sum=0
                    local function check_zero(col,num)
                        if calc_cols[col] or sum==1 then 
                            return 
                        elseif props.include_zero then 
                            sum=1
                            return
                        end
                        sum=(num and num~=0) and 1 or 0
                    end

                    grid:add(title)
                    for rx=2,#rs1 do
                        local row=table.new(cols,0)
                        for ix=1,cols do row[ix]=rs1[rx][ix] end
                        index,top_index=make_index(row)
                        data=result[index]
                        if not top_data[top_index] then 
                            top_data[top_index]={}
                            groups[#groups+1]=top_index
                        end
                        sum=0
                        if not data then
                            result[index],top_data[top_index][#top_data[top_index]+1]=row,row
                            for k,_ in pairs(agg_idx) do
                                local d=tonumber(row[k])
                                check_zero(k,d)
                                row[k]=d and math.round(d/elapsed,2) or nil
                            end
                        else
                            for k,_ in pairs(agg_idx) do
                                r,d=tonumber(row[k]),tonumber(data[k])
                                if r or d then 
                                    data[k]=math.round((d or 0)+(r or 0)/elapsed,2)
                                    check_zero(k,data[k])
                                end
                            end
                        end
                        result[index]['_non_zero_']=sum>0
                    end

                    for rx=2,#rs2 do
                        local row=rs2[rx]
                        index=make_index(row)
                        data=result[index]
                        if data then
                            sum=0
                            for k,_ in pairs(agg_idx) do
                                r,d=tonumber(row[k]),tonumber(data[k])
                                if r and d then
                                    data[k]=math.round(d-r/elapsed,2)
                                    check_zero(k,data[k])
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
                                local row=top_data[group_name][1]
                                for k,v in pairs(calc_cols) do
                                    for i,x in ipairs(rs1[1]) do
                                        v=v:gsub('\1'..i..'\2',row[i]==nil and '0' or tostring(row[i]))
                                    end
                                    v=loadstring(v)
                                    if v then
                                        local done,rtn=pcall(v)
                                        if done then
                                            row[k]=(rtn~=rtn or rtn==nil or rtn==1/0 or rtn==-1/0 ) and '' or type(rtn)=="number" and math.round(rtn,2) or rtn
                                        end
                                    end
                                end
                                grid:add(row)
                            end
                        end
                        idx=''
                        for i,_ in pairs(agg_idx) do
                            idx=idx..(-i)..','
                            if props.set_ratio=='on' then grid:add_calc_ratio(i) end
                        end
                        grid:sort(order_by or idx,true)
                    end
                end
                setmetatable(rs2,nil)
                table.clear(rs2)
                for k,v in pairs(props) do rs2[k]=v end
                for k,v in pairs(grid) do rs2[k]=v end
                setmetatable(rs2,getmetatable(grid))
            end
            local per_second=(cmd.per_second~=nil and cmd.per_second) or self.per_second
            per_second=(per_second==true or per_second=="on") and '(per Second)' or ''
            local top_mode=cmd.top_mode~=nil and cmd.top_mode or self.top_mode          
            local cost=string.format('(SQL:%.2f  Calc:%.2f)',cmd.fetch_time1+cmd.fetch_time2,os.timer()-calc_clock)
            local title=string.format('\n$REV$[%s#%s%s]: From %s to %s%s:$NOR$\n',self.command,name,per_second,cmd.starttime,cmd.endtime,
                env.set.get("debug")~="SNAPPER" and '' or cost)
            if top_mode then
                title=title:trim("\n")
                env.ansi.clear_screen()
                env.printer.top_mode=true
            end
            print(title)
            if #cmd.rs2.rsidx==1 then
                (cmd.rs2.rsidx[1]):print(nil,nil,nil,cmd.max_rows and cmd.max_rows+2 or cfg.get(self.command.."rows"))
            else
                if top_mode then cmd.rs2.max_rows=getHeight(console)-3 end
                env.grid.merge(cmd.rs2,true)
            end
            env.printer.top_mode=false
            env.var.import_context(table.unpack(self.var_context))
        end
    end

    
    if self.is_repeat then
        for name,cmd in pairs(cmds) do
            cmd.rs2,cmd.rs1,cmd.starttime,cmd.fetch_time2=cmd.rs1,nil,cmd.endtime,cmd.fetch_time1
        end
        
        if self.snap_cmd then
            env.eval_line(self.snap_cmd,true,true)
        else
            local timer=self.is_repeat+clock-os.timer()-0.1
            if timer>0 then sleep(timer) end
        end
        return self:next_exec()
    end
    self:trigger('after_exec_action')
end

function snapper:__onload()
    cfg.init(self.command.."rows","50",nil,"db.core","Number of max records for the '"..self.command.."' command result","5 - 3000")
end

return snapper