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
        6. bypassemptyrs: 'on' or 'off'(default),when a 'sql' is an array, and one of which returns no rows, then controls wether to show this sql
        7. is_clearscreen: 'on' or 'off'(default), controls wether to clear the screen before print the result
        8. calc_rules: the additional formula on a specific column after the 'delta_by' columns is calculated
        9.fixed_title: true or false(default), controls wether not to change the 'delta_by' column titles
        10.include_zero:  true or false(default), controls wether not to show the row in case of its 'delta_by' columns are all 0
        11.set_ratio: true or false(default), controls wether not to add a percentage column on each 'delta_by' columns
        12.before_sql: the statements that executed before the 1st snapshot
        13.after_sql: the statements that executed after the 2nd snapshot

    The belowing variables can be referenced by the SQLs in 'snapper':
    1. :snap_cmd      :  The command that included by EOF
    2. :snap_interval :  The elapsed seconds betweens 2 snapshots
--]]
local env,pairs,ipairs,table,tonumber=env,pairs,ipairs,table,tonumber
local sleep,math,cfg=env.sleep,env.math,env.set
local terminal,getHeight=terminal,terminal.getHeight

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

    cmd.group_by=cmd.group_by or cmd.grp_cols
    cmd.top_by=cmd.top_by or cmd.top_grp_cols
    cmd.delta_by=cmd.delta_by or cmd.agg_cols
    cmd.group_by=cmd.group_by and (','..cmd.group_by:upper()..',') or nil
    cmd.top_by=cmd.top_by and (','..cmd.top_by:upper()..',')
    cmd.delta_by=','..(cmd.delta_by and cmd.delta_by:upper() or '')..','
    cmd.per_second=(cmd.per_second==true or cmd.per_second=="on") and true or false
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

    return rs,clock,time
end

function snapper:run_sql(sql,main_args,cmds,files)
    local db,print_args=self.db
    cfg.set("feed","off")
    cfg.set("autocommit","off")
    cfg.set("digits",2)
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

    for k,v in pairs(main_args) do
        if type(v)=="table" then
            local idx=0;
            args[k]={}
            for i=1,20 do
                local x="V"..i
                local y=tostring(v[x]):upper()
                if not (v[x]==snap_cmd or i==1 and (tonumber(interval) or self.is_repeat or y=="END" or y=="BEGIN"))
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
    
    self.cmds,self.args={},{}
    self.start_flag=true
    env.set.set("feed","off")
    self:trigger('before_exec_action')
    local clock=os.timer()
    for idx,text in ipairs(sql) do
        local cmd,arg=self:parse(cmds[idx],sql[idx],args[idx],files[idx])
        self.cmds[cmds[idx]],self.args[cmds[idx]]=cmd,arg
        arg.snap_cmd=snap_cmd or ''
        arg.snap_interval=tonumber(interval) or 0
        if cmd.before_sql then
            env.eval_line(cmd.before_sql,true,true) 
        end
        cmd.rs2,cmd.clock,cmd.starttime=self:build_data(cmd.sql,arg)
    end
    db:commit()
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
    local cmds,args,db,clock=self.cmds,self.args,self.db
    --self:trigger('before_exec_action')
    db:commit()

    for name,cmd in pairs(cmds) do
        args[name].snap_interval=os.timer()-cmd.clock
        local rs,clock,starttime=self:build_data(cmd.sql,args[name])
        if type(cmd.rs2)=="table" and type(rs)=="table" then
            cmd.rs1,cmd.clock,cmd.endtime,cmd.elapsed=rs,clock,starttime,clock-cmd.clock
        end
        if cmd.after_sql then
            env.eval_line(cmd.after_sql,true,true) 
        end
    end
    clock=os.timer()
    self.db:commit()

    local result,groups={}
    local define_column=env.var.define_column
    for name,cmd in pairs(cmds) do
        if cmd.rs1 and cmd.rs2 then
            local formatter=cmd.column_formatter or {}
            local defined_formatter={}
            
            for k,v in pairs(formatter) do
                local cols=v:split('%s*,%s*')
                for _,col in ipairs(cols) do
                    defined_formatter[col:upper()]=k
                    define_column(col,'format',k)
                end
            end

            for idx,_ in ipairs(cmd.rs1.rsidx) do
                local rs1,rs2=cmd.rs1.rsidx[idx],cmd.rs2.rsidx[idx]
                local agg_idx,grp_idx,top_grp_idx,agg_model_idx,found_top={},{},{},{}
                local title=rs2[1]
                local cols=#title
                local min_agg_pos,top_agg_idx,top_agg=1e4
                local elapsed=cmd.per_second and cmd.elapsed or 1
                local calc_rules=rs2.calc_rules or cmd.calc_rules or {}
                local calc_cols={}
                local is_groupped=false
                local order_by=rs2.order_by or cmd.order_by

                if type(order_by)=="string" then order_by=(','..order_by:upper()..','):gsub('%s*,[%s,]*',',') end

                for k,v in pairs(calc_rules) do
                    if type(k)=="string" then calc_rules[k:upper()]=v end
                end

                for i,k in ipairs(title) do
                    local tit=k:upper()
                    local idx=cmd.delta_by:find(','..tit..',',1,true)
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
                        agg_idx[i],title[i]=idx,(rs2.fixed_title or cmd.fixed_title) and k  or (rs2.per_second or cmd.per_second) and (k..'/s') or ('*'..k)
                        define_column(title[i],'format',defined_formatter[title[i]] or defined_formatter[tit] or "%,.2f")
                        if type(order_by)=="string" then
                            if order_by:find(',-'..tit..',',1,true) then
                                order_by=order_by:replace(',-'..tit..',',',-'..title[i]..',',true)
                            end
                            if order_by:find(','..tit..',',1,true) then
                                order_by=order_by:replace(','..tit..',',','..title[i]..',',true)
                            end
                        end
                    else
                        if not cmd.group_by or cmd.group_by:find(','..tit..',',1,true) then
                            grp_idx[i]=true
                        end

                        if cmd.top_by and cmd.top_by:find(','..tit..',',1,true) then
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
                
                if not is_groupped then
                    grid,rs2=rs1,{}
                else
                    local sum=0
                    local function check_zero(col,num)
                        if calc_cols[col] or sum==1 then 
                            return 
                        elseif rs2.include_zero or cmd.include_zero then 
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

                    rs2.max_rows=rs2.max_rows or cmd.max_rows or cfg.get(self.command.."rows")
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
                                        if done then row[k]=(rtn~=rtn or rtn==nil or rtn==1/0) and '' or rtn end
                                    end
                                end
                                grid:add(row)
                            end
                        end
                        idx=''
                        for i,_ in pairs(agg_idx) do
                            idx=idx..(-i)..','
                            if (rs2.set_ratio or cmd.set_ratio)=='on' then grid:add_calc_ratio(i) end
                        end
                        grid:sort(order_by or idx,true)
                    end
                end
                setmetatable(rs2,nil)
                for k=#rs2,1,-1 do rs2[k]=nil end
                for k,v in pairs(grid) do rs2[k]=v end
                setmetatable(rs2,getmetatable(grid))
                
            end
            local is_clearscreen=cmd.is_clearscreen
            is_clearscreen=(is_clearscreen==true or is_clearscreen=="on") and true or false
            local title=("\n["..(self.command..'#'..name):upper().."]: From "..cmd.starttime.." to "..cmd.endtime..":\n"):format(name)
            title=title..string.rep("=",title:len()-2)
            if is_clearscreen then
                title=title:trim("\n")
                env.ansi.clear_screen()
                env.printer.top_mode=true
            end
            print(title)
            if #cmd.rs2.rsidx==1 then
                (cmd.rs2.rsidx[1]):print(nil,nil,nil,cmd.max_rows or cfg.get(self.command.."rows"))
            else
                if is_clearscreen then cmd.rs2.max_rows=getHeight(terminal)-3 end
                env.grid.merge(cmd.rs2,true)
            end
            env.printer.top_mode=false
        end
    end

    
    if self.is_repeat then
        for name,cmd in pairs(cmds) do
            cmd.rs2,cmd.rs1,cmd.starttime,cmd.elapsed=cmd.rs1,nil,cmd.endtime
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