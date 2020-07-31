local env=env
local parser={data={open={},close={}}}
local table,math,pairs,type,print,ipairs,io=table,math,pairs,type,print,ipairs,io

function parser.command(cmd,...)
    env.checkhelp(cmd)
    cmd=tostring(cmd):lower()
    local func,data=parser.cmds[cmd],parser.data[cmd] or {root=parser.data}
    env.checkerr(func,"No such command: %s",cmd)
    env.checkerr(cmd=='open' or cmd=='close' or parser.data.file,"Please open an 10053 trace file firstly.")
    func(data,...)
end

local function pattern_search(data,keyword)
    env.checkerr(data and data.last_start_line,"No data found.")
    local root,counter=data.root,0
    root.print_start()
    if keyword then
        keyword=keyword:lower():gsub('%%','\1\2\3'):escape():gsub('\1\2\3','.-')
    end
    for line,lineno in root.range(data.last_start_line,data.last_end_line) do
        if not keyword or line:lower():find(keyword) then
            root.print(lineno,line)
        end
    end
    return root.print_end(true)
end

local function extract_timer()
    return {
        start="TIMER:",
        repeatable=true,
        exclusive=true,
        priority=1,
        parse=function(self,line,lineno)
            local cpu,ela=line:match('cpu: *([%d%.]+).-elapsed: *([%d%.]+)')
            if not cpu then return false end
            cpu,ela=tonumber(cpu)*1e6,tonumber(ela)*1e6
            local data=self.data
            if not data.lines then 
                data.lines,data.qbs={},{}
                data.count,data.cpu,data.ela=0,0,0
            end
            local qb=self.root.current_qb
            if qb and line:find('SQL Optimization (Overall)',1,true) and data.qbs[qb] then
                return 
            end

            data.lines[lineno]=qb or 'ROOT'
            if qb then
                if not data.qbs[qb] then data.qbs[qb]={0,0,0} end
                data.qbs[qb][1],data.qbs[qb][2],data.qbs[qb][3]=data.qbs[qb][1]+1,data.qbs[qb][2]+cpu,data.qbs[qb][3]+ela
                data.count,data.cpu,data.ela=data.count+1,data.cpu+cpu,data.ela+ela
            end
            return false
        end,

        extract={
            help="|@@NAME [-l] |Show timer (fix control # 16923858)|",
            call=function(data,option)
                env.checkerr(data and data.count,"No data found.")
                local root=data.root
                if option then option=option:lower() end
                if root.qbs and option~='-l' then
                    local rows={}
                    local stack={}
                    local idx=0
                    local prev
                    for line in root.range(root.qbs.last_start_line,root.qbs.last_end_line) do
                        local qb=line:match('%u+$%w+')
                        if prev~=line and qb then
                            local timer=data.qbs[qb] or {0,0,0}
                            local lv=#(line:match('^%s*'))
                            idx=idx+1
                            stack[lv]=idx
                            rows[#rows+1]={timer[1],timer[2],timer[3],data.ela and timer[3]/data.ela or 0,(lv==0 and '' or '|')..line:rtrim(),0}
                            if timer[1]>0 then
                                for k,v in pairs(stack) do
                                    if k<=lv then
                                        rows[v][6]=rows[v][6]+timer[1]
                                    end
                                end
                                table.clear(stack)
                            end
                        end
                        prev=line
                    end
                    for i=#rows,1,-1 do
                        if rows[i][6]==0 then 
                            table.remove(rows,i) 
                        else
                            for j=1,4 do
                                if rows[i][j]==0 then rows[i][j]='' end
                            end
                        end
                    end
                    env.var.define_column('cpu,elapsed','for','usmhd2')
                    env.var.define_column('ela%','for','pct3')
                    table.insert(rows,1,{'Count','CPU','Elapsed','Ela%','Query Block Registry'})
                    rows[#rows+1]={data.count,data.cpu,data.ela,1,'----- TOTAL -----'}
                    env.grid.print(rows)
                    env.var.define_column('cpu,elapsed','clear')
                    return
                end

                local fmt='%-12s:   %s'
                root.print_start('_timer.txt')
                for line,lineno in root.range(1,root.max_lines) do
                    if data.lines[lineno] then
                        root.print(lineno,fmt:format(data.lines[lineno],line))
                    end
                end
                root.print_end(true)
            end
        }
    }
end

local function extract_plan()
    return {
        start=function(line) return line:find('^[%s%-]+ Explain Plan Dump[%s%-]*$') end,
        parse=function(self,line,lineno,full_line)
            if lineno==self.start_line then
                self.data.text={}
                self.plan={}
                self.qb_pattern={'^ *(%d+) +%- +(%S+) +/ +(%S+)$','^ *(%d+) +%- +(%S+)$'}
                self.lines=0
                self.add=function(self,text)
                    self.lines=self.lines+1
                    self.data.text[self.lines]=text
                end
                return
            elseif self.plan_start==nil then
                if line:find('^| *Id *| ') then
                    self.plan[#self.plan+1]=line
                    self.plan_start=0
                end
                return
            elseif self.plan_start then
                self.plan[#self.plan+1]=line
                if line:find('--------',1,true)==1 then
                    self.plan_start=self.plan_start+1
                    if self.plan_start==2 then
                        self.plan_start=false
                    end
                end
                return
            elseif self.qb_start==nil and line:find('^Query Block Name') then
                self.qb_start=0
                self.qbs={}
                self.data.qbs={}
                self.qb_len,self.alias_len=3,5
                return
            elseif self.qb_start then
                local id,qb,alias=line:match(self.qb_pattern[1])
                if not id then
                    id,qb=line:match(self.qb_pattern[2])
                    alias=''
                end
                if id then
                    id=tonumber(id)
                    self.qb_start=id
                    self.qb_len=math.max(self.qb_len,#qb)
                    self.alias_len=math.max(self.alias_len,#alias)
                    self.qbs[id]={qb,alias}
                    if not self.data.qbs[qb] then self.data.qbs[qb]={} end
                    if alias~='' then self.data.qbs[qb][alias]=id end
                else
                    if self.qb_start>0 then
                        self.qb_start=false
                        local fmt="%s %-"..self.qb_len.."s | %-"..self.alias_len.."s|"
                        local sep=self.plan[2]..('-'):rep(self.qb_len+self.alias_len+5)
                        self:add(sep)
                        self:add(fmt:format(self.plan[1],'Q.B','Alias'))
                        self:add(sep)
                        for i=3,#self.plan-1 do
                            local qb=self.qbs[i-3] or {"",""}
                            self:add(fmt:format(self.plan[i],qb[1],qb[2]))
                        end
                        self:add(sep)
                        self.plan=nil
                        print(table.concat(self.data.text,'\n  '))
                    end
                end
                return
            end
            if self.plan and #self.plan>1 then
                self:add(self.plan[2])
                for k,v in ipairs(self.plan) do self:add(v) end
                self.plan=nil
                print(table.concat(self.data.text,'\n'))
            end
            if line:find('<qb_registry>',1,true) then
                line=full_line:gsub('<!%[CDATA%[([^%]]+)%]%]>','%1'):gsub('</q>','</q>\n')
            end
            self:add(line)
        end,

        end_parse=function(self,line,lineno)
            if type(self.data.text)~='table' then return end
            self.data.text[self.lines]=nil
            self.data.text=table.concat(self.data.text,'\n')
        end,

        extract={
            help='|@@NAME|Show execution plan|',
            call=function(data)
                print(data.text)
                print("Result saved to "..env.save_data(data.root.prefix..'_plan.txt',data.text))
            end
        }
    }
end

local qb_patterns={'Considering .+ query block (%S+$%S+)',"^Query Block +(%S+$%S+)",' qb_name=(%S+$%S+)','^Registered qb: *(%S+$%S+)'}
local function extract_qb()
    return {
        start=function(line,root,lineno,unparsed)
            local qb
            for _,p in ipairs(qb_patterns) do
                qb=line:match(p)
                if qb then
                    root.current_qb=qb:upper()
                    return true
                end
            end
            if unparsed==false or not root.qb then return false end
            if line:find('^SQL:******* UNPARSED QUERY IS *******') then
                if not root.qb[root.current_qb] then root.qb[root.current_qb]={} end
                root.qb[root.current_qb].sql=lineno+1
            end
            return false
        end,
        repeatable=true,
        priority=2,
        extract={
            help='|@@NAME <Query Block Name> | Show query block info with the specific QB name |',
            call=function(data,qb)
                env.checkerr(qb,"Please input the query block name.")
                local lineno,level,prev=0
                local root,name=data.root,qb
                qb='(%W)('..qb:escape()..')(%W)'
                local curr_qb,spd,prev_line
                local function pr(l,c)
                    root.print(l,c)
                end
                local stack,seq,found={},{},{}
                root.print_start(name:gsub('%$','_')..'.txt')
                root.current_qb=nil
                for line in root.seek(0):lines() do
                    parser.probes.qb.start(line,root,nil,false)
                    lineno,line=lineno+1,' '..line..' '
                    line,found=line:gsub(qb,'%1$UDL$%2$NOR$%3')
                    line=line:sub(2,-2)

                    if line:find('^SPD: *BEGIN') and root.current_qb==name then
                        spd=true
                        pr(lineno-1,prev_line)
                        pr(lineno,line)
                    elseif spd and line:find('^SPD: *END') then
                        spd=false
                        pr(lineno,line)
                        pr(lineno+1,prev_line)
                    elseif spd then
                        pr(lineno,line)
                    elseif line~=prev and not line:find('^([^%w ])%1%1%1%1%1') and not line:find('TIMER:',1,true)~=1 then
                        local spaces=line:match('^%s+')
                        local lv,is_root=spaces==nil and 0 or #spaces,spaces==nil
                        if line~='' then
                            stack[lv]={lineno,line}
                        end
                        if found>0 then 
                            prev=line
                            table.clear(seq)
                            for k,v in pairs(stack) do
                                if k<=lv then seq[#seq+1]=k end
                            end
                            table.sort(seq)
                            for _,l in ipairs(seq) do
                                pr(stack[l][1],stack[l][2])
                            end
                            table.clear(stack)
                            if not level or level<lv then
                                level=lv
                            end
                        elseif line~='' and lv==0 or (level and lv<=level) then
                            level=nil
                        elseif level and #(line:trim())>3 then
                            prev=line
                            pr(lineno,line)
                        end
                    end
                    prev_line=line
                end
                root.print_end(true)
            end
        }
    }
end

local function extract_tb()
    return {
        start=function(line) return line:find("^SINGLE TABLE ACCESS PATH") or line:find('^Table Stats:+$') end,
        repeatable=true,
        parse=function(self,line,lineno)
            local root=self.root
            if lineno==self.start_line then
                self.type=line:find('^SINGLE') and 'sta' or 'bsi'
                return
            elseif lineno==self.start_line+1 then
                self.qb=root.current_qb
                local tab,alias
                if self.type=='sta' then
                    tab=line:match('for (%S+)$')
                    if not tab then return false end
                    if tab:find('[',1,true) then
                        tab,alias=tab:match('^(.*)%[(.*)%]$')
                    else
                        alias=tab
                    end
                else
                    tab,alias=line:match('Table: +(%S+) +Alias: +(%S+)')
                    if not tab then return false end
                    if alias:find('online') then alias=alias:gsub('online.*','') end
                end
                tab,alias=tab:upper(),alias:upper()
                self.info={qb=self.qb,alias=alias,[self.type]={start_line=self.start_line}}
                local grp=self.data[tab] or {}
                if not grp[self.qb] then grp[self.qb]={} end
                if not grp[self.qb][alias] then 
                    grp[self.qb][alias]=self.info 
                else
                    grp[self.qb][alias][self.type]=self.info[self.type]
                    self.info=grp[self.qb][alias]
                end
                grp[self.qb][alias][self.type..'_seens']=(grp[self.qb][alias][self.type..'_seens'] or 0)+1
                self.data[tab]=grp
            elseif self.type=='sta' and line:find('Best:: AccessPath: *(%S+)') then
                self.info.best_sta=line:match('Best:: AccessPath: *(%S+)')
            elseif line:match('^ *[%*=]+$') or line:find('^Access path analysis') or line:find('^Join order') then
                self.info[self.type].end_line=lineno-1
                return false
            elseif self.type=='bsi' and line=='' then
                self.info[self.type].end_line=lineno-1
                return false
            end
        end,

        end_parse=function(self,line,lineno)
            if self.info and not self.info[self.type].end_line then
                self.info[self.type].end_line=lineno-1
            end
        end,

        extract={
            help="|@@NAME <table_name> [<qb_name>\\|all]| Show single table stats and access paths. |",
            call=function(data,tab,qb)
                if tab then 
                    tab=tab:upper() 
                    if tab=='.' then tab='' end
                end
                if qb then 
                    qb=qb:upper()
                    if qb=='' or qb=='.' then qb=nil end
                end
                local root,rows=data.root,{}
                local qbs=root.plan.qbs
                for t,v in pairs(data) do
                    if t~='root' and type(v)=='table' then
                        for q,o in pairs(v) do
                            if type(o)=='table' then
                                for alias,p in pairs(o) do
                                    if (not tab or tab==alias or tab==t or tab=='') and (not qb and (not qbs or qbs[q]) or q==qb or qb=='ALL') then
                                        local lines={}
                                        if p.bsi then lines[#lines+1]=p.bsi end
                                        if p.sta then lines[#lines+1]=p.sta end
                                        rows[#rows+1]={t,alias==t and '' or alias,q,
                                                       lines[1].start_line,lines[#lines].end_line,
                                                       p.bsi_seens or 0,p.sta_seens or 0,
                                                       p.best_sta or '',
                                                       p.qb_perms ,
                                                       p.best_jo or '',
                                                       p.jo or '',
                                                       lines}
                                    end
                                end
                            end
                        end
                    end
                end

                if not tab then
                    env.grid.sort(rows,'1,4')
                    table.insert(rows,1,{"Table Name",'Alias','Query Block','Start Line','End Line','BSI Seens','STA Seens','STA Best','JOs','Best JO#','Join'})
                    env.grid.print(rows)
                    return
                end

                env.checkerr(#rows>0,'Invalid table name or query block name.')
                table.sort(rows,function(a,b) return a[4]<b[4] end)

                root.print_start('_'..tab:gsub('[$#]','_')..(qb and ('_'..qb) or ''):gsub('[$#]','_')..'.txt')
                local w=root.width
                for i,qb in ipairs(rows) do
                    local width=#qb[3]+16
                    root.print(("="):rep(w),("="):rep(width))
                    root.print(("/"):rep(w),'|$HEADCOLOR$ Query Block '..qb[3]..' $NOR$|')
                    root.print(("="):rep(w),("="):rep(width))
                    for j,l in ipairs(qb[#qb]) do
                        local prev=nil
                        for line,lineno in root.range(l.start_line,l.end_line) do
                            if prev~=line then root.print(lineno,line) end
                            prev=line
                        end
                        if j<#qb[#qb] then
                            root.print(('-'):rep(w),('-'):rep(width))
                        end
                    end
                end
                root.print_end()
                return
            end
        }
    }
end

local function extract_jo()
    return {
        closeable=false,
        repeatable=true,
        start=function(line) 
            if line:find('^Permutations for Starting Table') then return true end
            if line:find('^Join order%[') then return true end
        end,
        add=function(self,level,lineno)
            local jo=self.curr_perm
            jo.end_line,self.last_indent=lineno,level
            jo.lines[lineno]=level
            if self.curr_tab_index then
                jo.tlines[self.curr_tab_index][2]=lineno
            end
            table.clear(self.stack)
        end,

        parse=function(self,line,lineno)
            if not self.stack then self.stack={} end
            if not self.cost then self.cost=0 end
            if line:match('^kkoqbc: finish optimizing query block') then
                self.data[self.qb].end_line=lineno
                return false
            elseif lineno==self.start_line then
                self.qb=self.root.current_qb:upper()
                self.data[self.qb]={start_line=lineno,perms={}}
                local qbs=self.data.root.qb
                if qbs and not qbs[self.qb] then qbs[self.qb]={} end
                qbs[self.qb].jo=self.data[self.qb]
            elseif line:find('^Join order%[') then
                local perm=tonumber(line:match('^Join order%[(%d+)%]'))
                local tables=line:match(': *(%S.-%S)$'):split('%s+')
                self.stack={}
                self.data[self.qb].perm_count=perm
                local jo={lines={},tables=tables,tlines={},jo=perm,start_line=lineno,cost=0}
                self.curr_perm=self.data[self.qb].perms[perm] or jo
                if not self.data[self.qb].perms[perm] then
                    self.data[self.qb].perms[perm]=jo
                end
                self:add(0,lineno)
            elseif line:find('^%s*[%*]+%s*%w+') and self.last_indent then
                self:add(self.last_indent,lineno)
            elseif line:find('^Now joining:') then
                self.cost=0
                self.curr_tab_index=nil
                self.curr_table=line:match(': *(%S.-%S)$')
                for i,t in ipairs(self.curr_perm.tables) do
                    if t==self.curr_table then 
                        self.curr_tab_index=i
                        local tline=self.curr_perm.tlines[i] or {lineno,lineno}
                        self.curr_perm.tlines[i]=tline
                        break
                    end
                end
                self:add(1,lineno)
            elseif line:find('^%u+ Join$') or line:find('^ +.- %u+ cost:') then
                self:add(2,lineno)
                local cost=tonumber(line:match('cost: *([%.%d]+)'))
                if cost then self.cost=math.min(cost,self.cost==0 and cost or self.cost) end
            elseif line:find('^Best:+') then
                self:add(2,lineno)
                self:add(2,lineno+1)
                local best=line:match('%S+$')
                local found=false
                for i=1,#self.curr_perm.tables do
                    if self.curr_perm.tables[i]==self.curr_table then
                        self.curr_perm.tables[i]=self.curr_table:gsub(' *#%d+$','')..'('..best..')'
                        found=true
                        break
                    end
                end
            elseif line:find('^Join order aborted') or line:find('^Best so far') then
                self:add(0,lineno)
                if line:find('^Join') then
                    self.curr_perm.cost='> '..math.round(self.cost,3)
                    self.curr_tab_index,self.curr_table=nil
                else
                    local cost=tonumber(line:match('cost: *([%.%d]+)'))
                    if cost then self.cost=cost end
                    self.curr_perm.cost,self.cost='= '..math.round(self.cost,3),0
                    self.is_best=1
                end
                self.cost=0
            elseif self.is_best==1 then
                if line:find('^ +') then
                    self:add(0,lineno)
                    local cost=tonumber(line:match('cost: *([%.%d]+)'))
                    if cost then self.curr_perm.cost='= '..math.round(cost,3) end
                else
                    self.curr_tab_index,self.curr_table=nil
                    self.is_best=0
                end
            elseif line:find('^%s+Best join order: *(%d+)$') then
                self.is_best=2
                self.curr_tab_index,self.curr_table=nil
                local best=tonumber(line:match('%d+'))
                self.data[self.qb].perm_best=best
                local perm=self.data[self.qb].perms[best]
                for i,t in ipairs(perm.tables) do
                    local tab,alias,method=t:match('^(.-)%[(.-)%]%((.-)%)')
                    if not tab then 
                        tab,alias=t:match('^(.-)%[(.-)%]')
                        method=''
                    end
                    if tab then
                        tab,alias=tab:upper(),alias:upper()
                        local tb=self.root.tb
                        if tb and tb[tab] and tb[tab][self.qb] and tb[tab][self.qb][alias] then
                            local curr_tb=tb[tab][self.qb:upper()][alias]
                            curr_tb.qb_perms=(curr_tb.qb_perms or 0)+self.data[self.qb].perm_count
                            curr_tb.jo,curr_tb.best_jo=method,best
                        end
                    end
                end
            elseif self.is_best==2 then
                local cost=tonumber(line:match('Cost: (%d+)'))
                self.data[self.qb].cost=cost
                self.is_best=0
            elseif (self.last_indent or 0) > 0 and (line:find('^ *%S.- Cost:') or line:find('^%s+Index:')) then
                local lv=#(line:match('^%s*'))
                local seq={}
                for k,v in pairs(self.stack) do
                    if k<lv then
                        seq[#seq+1]={k,v}
                    end
                end
                table.sort(seq,function(a,b) return a[1]<b[1] end)
                for k,v in ipairs(seq) do
                    self:add(3,v[2])
                end
                self:add(3,lineno)
            elseif line~='' and (self.last_indent or 0) > 0 then
                local lv=#(line:match('^%s*'))
                self.stack[lv]=lineno
            end
        end,

        extract={
            help="|@@NAME [<qb_name>] [<JO#>] [<table_name>] | Show join orders, more details for more parameters |",
            call=function(data,qb,jo,tb)
                local rows,last={}
                local root=data.root
                if tb then tb=tb:upper()..'[' end
                for k,v in pairs(data) do
                    if type(v)=='table' and k~='root' and (not qb or qb:upper()==k) then
                        if not qb then
                            local best=v.perms[v.perm_best]
                            rows[#rows+1]={k,v.perm_count,v.perm_best,v.start_line,v.end_line,v.cost,table.concat(best.tables,' -> ')}
                        else
                            for i,j in ipairs(v.perms) do
                                local chain=table.concat(j.tables,' -> ')
                                if not jo or jo==tostring(i) or jo=='*' or jo=='.' then
                                    if not tb then
                                        rows[#rows+1]={k,i,v.perm_best==i and 'Y' or '',j.start_line,j.end_line,j.cost,chain,j}
                                    else
                                        for c,t in ipairs(j.tables) do
                                            if (t:find(tb,1,true) or tb:find(t,1,true)) and j.tlines[c] then
                                                rows[#rows+1]={k,i,v.perm_best==i and 'Y' or '',j.tlines[c][1],j.tlines[c][2],j.cost,chain,j}
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if not qb then
                    table.insert(rows,1,{'QB Name','JOs','Best JO#','Start Line','End Line','Cost','Join Chain'})
                    grid.sort(rows,4,true)
                    grid.print(rows)
                else
                    local size=#rows
                    env.checkerr(size>0,'Please input the valid QB name / JO# / table name.')
                    if not jo and size>1 then --list jo
                        table.insert(rows,1,{'QB Name','JO#','Best','Start Line','End Line','Cost','Join Chain'})
                        grid.sort(rows,4,true)
                        grid.print(rows)
                    elseif not jo and size==1 then --display QB details
                        root.print_start('_'..qb:gsub('[$@]','_')..'.txt')
                        qb=data[rows[1][1]]
                        for line,lineno in root.range(qb.start_line,qb.end_line) do
                            root.print(lineno,line)
                        end
                        root.print_end()
                    else
                        root.print_start(('_'..qb..(tonumber(jo) and ('_'..jo) or '')..(tb  and ('_'..tb) or '')):gsub('[$@]','_')..'.txt')
                        local fmt,prev='Query Block %s    Join Order #%d'
                        local w=root.width
                        for i,j in ipairs(rows) do
                            local pieces=j[#j].lines
                            local curr=fmt:format(j[1],j[2])
                            if curr~=prev then
                                prev=curr
                                local width=#curr+4
                                root.print(("="):rep(w),("="):rep(width))
                                root.print(("/"):rep(w),'|$HEADCOLOR$ '..curr..' $NOR$|')
                                root.print(("="):rep(w),("="):rep(width))
                            end
                            for line,lineno in root.range(j[4],j[5]) do
                                if tb and size==1 then
                                    root.print(lineno,line)
                                elseif pieces[lineno] then
                                    root.print(lineno,(' '):rep(pieces[lineno]*2)..line)
                                end
                            end
                        end
                        root.print_end()
                    end
                end
            end
        }
    }
end

local function extract_sql()
    return {
        start=function(line,root)
            if root.sql_id then return end
            local sql_id=line:match('Current SQL Statement for this session *%(sql_id=(%S+)%)')
            if sql_id then
                root.sql_id=sql_id
                return true
            end
        end,
        parse=function(self,line,lineno)
            if lineno>self.start_line and line:find('^([%-=%*])%1%1%1') then
                return false
            end
        end,
        extract={
            help="|@@NAME [<qb_name>] | Show the source SQL text or the unparsed SQL text for the specific query block.|",
            call=function(data,qb)
                local root,text=data.root,{}
                if not qb then
                    for line in root.range(data.last_start_line+1,data.last_end_line) do
                        text[#text+1]=line
                    end
                    text=table.concat(text,'\n')
                    print(text)
                    print('\n'.. string.rep('=',30)..'\nSource SQL ID: '..root.sql_id)
                    print('\nResult saved to '..env.save_data(root.prefix..'_sql.sql',text))
                else
                    local q=root.qb[qb:upper()]
                    env.checkerr(q and q.sql,"Cannot find unparsed SQL text for query block: "..qb)
                    for line in root.range(q.sql,q.sql) do
                        text=line
                    end
                    print(text)
                    print('\nResult saved to '..env.save_data(root.prefix..'_'..qb:gsub('[$@]','_')..'_sql.sql',text))
                end
            end
        }
    }
end

local function extract_lines()
    return {
        start='sql_id=',
        extract={
            help="|@@NAME {<start_line> [<end_line>]}\\|<keyword> | Show matched lines with the specific line range or keyword(supports wildchar '%') |",
            call=function(data,b,e)
                env.checkerr(b,"Please input the start line number or keyword.")
                local root,st,ed,keyword,prev=data.root,tonumber(b),tonumber(e)
                if b and not st then
                    keyword='%W'..b:lower():gsub('%%','\1\2\3'):escape():gsub('\1\2\3','.-')..'%W'
                    b,e=1,root.max_lines
                else
                    b,e=st,ed
                    env.checkerr(b>0,"Please input the start line number.")
                    env.checkerr(not e or e>=b, "<end_line> must not be smaller than <start_line>.")
                    if not e then
                        b=math.max(0,b-20)
                        e=b+50 
                    end
                end

                root.print_start()
                for line,lineno in root.range(b,e) do
                    if not keyword or prev~=line and (' '..line:sub(1,256)..' '):lower():match(keyword) then
                        root.print(lineno,not ed and lineno==st and ('$COMMANDCOLOR$'..line..'$NOR$') or line)
                        if keyword then prev=line end
                    end
                end
                root.print_end(true)
            end
        }
    }
end

--[[--
Probe Attriutes:
    start        : the function/string that triggers the start of the probe, if function and returns 0/true means starting the probe
    parse        : function, parse each line when the probe is started,when return false then force closing the probe(call end_parse(nil))
                             when this attr is not defined then the probe is a single-line probe
    end_parse    : function, triggered when close the started probe, when inut parameters are null then force closing the probe
    repeatable   : boolean,  when not true then the probe can only be started once
    closeable    : boolean,  when false then the started probe can be closed by other running probes(parallel probe)
    exclusive    : boolean,  when true then bypass the parsing of other concurrent probes in case of this probe is started
    priority     : number,   smaller number means higher priority
    extract.help : string,   the help info of the sub-command
    extract.call : function, executed as sub-command
--]]--

local function build_probes()
    parser.probes={
        plan=extract_plan(),
        qb=extract_qb(),
        tb=extract_tb(),
        sql=extract_sql(),
        jo=extract_jo(),
        timer=extract_timer(),
        binds={
            start='Peeked values',
            parse=function(self,line,lineno)
                if line=='' then return false end
            end,
            extract={
                help="|@@NAME | Show Peeked values of the binds in SQL statement |",
                call=pattern_search
            }
        },

        optenv={
            start=function(line,root) return root.plan and line:find("^Optimizer state dump:") end,
            parse=function(self,line,lineno) end,
            extract={
                help="|@@NAME [<keyword>] | Show optimizer environment |",
                call=pattern_search
            }
        },

        fixctl={
            start=function(line,root) return root.optenv and line:find("^Bug Fix Control Environment") end,
            extract={
                help="|@@NAME [<keyword>] | Show bug fix control environment |",
                call=pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^([%*=])%1%1$') then return false end
            end
        },

        qbs={
            start=function(line,root) return root.fixctl and line:find("Query Block Registry:") end,
            extract={
                help="|@@NAME [<keyword>] | Show Registered Query Blocks |",
                call=pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^([%*=])%1%1$') then return false end
            end
        },

        stats={
            start="SYSTEM STATISTICS INFORMATION",
            extract={
                help="|@@NAME | Show system statistics information |",
                call=pattern_search
            },
            parse=function(self,line,lineno)
                if line:find('^*************************') then return false end
            end
        },
        abbr={
            start='The following abbreviations are used by optimizer trace',
            extract={
                help="|@@NAME [<keyword>] | Show abbreviations |",
                call=pattern_search
            },
            parse=function(self,line,lineno)
                if line:find('^%*%*%*') or line=='' then return false end
            end
        },
        alter={
            start='PARAMETERS WITH ALTERED VALUES',
            extract={
                help="|@@NAME [<keyword>] | Show altered parameters |",
                call=pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^[%*=]+$') then return false end
            end
        },

        param={
            start='PARAMETERS WITH DEFAULT VALUES',
            extract={
                help="|@@NAME [<keyword>] | Show default parameters |",
                call=pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^[%*=]+$') then return false end
            end
        },

        optparam={
            start='PARAMETERS IN OPT_PARAM HINT',
            extract={
                help="|@@NAME [<keyword>] | Show parameters changed by opt_param hint|",
                call=pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^[%*=]+$')then return false end
            end
        },

        lines=extract_lines()
    }
    build_probes,extract_plan,extract_qb,extract_tb,extract_sql,extract_lines,extract_jo,extract_timer=nil
end

function parser.read(data,file)
    local f=io.open(file,'r')
    env.checkerr(f,"Unable to open file: %s",file)
    parser.close()
    local root=parser.data
    local short_name=file:match('([^\\/]+)$')
    local lines,data={}
    local curr_probe
    local lineno,offset,prev_offset,size,curr,sub,full_line=0,0,0

    root.file=file
    root.prefix=short_name:match('^[^%.]+')

    local probes,finds,priors={},{},parser.priors

    local function end_parse(name,force)
        local probe=probes[name]
        if not probe then return end
        probe.data.last_end_line,probe.data.last_end_offset=lineno-1,prev_offset
        probe.end_line,probe.end_offset=lineno-1,prev_offset
        if probe.end_parse then
            if force then
                probe:end_parse(nil,lineno)
            else
                local res=probe:end_parse(curr,lineno,full_line)
                if res==false then return res end
            end
        end
        probes[name]=nil
    end

    local function parse(name)
        local probe=probes[name]
        if not probe then return end
        if not probe.parse then
            probe.data.last_end_line,probe.data.last_end_offset=probe.data.last_start_line,offset
            probes[name]=nil
            return
        end
        local res=probe:parse(curr,lineno,full_line)
        if res==false then return end_parse(name,true) end
    end

    local function _exec(name,p,e,c)
        if c and probes[name].closeable==false then return end
        if p then parse(name) end
        if e~=nil then end_parse(name,e) end
    end

    local function execute(p,e,c)
        for i,h in ipairs(priors) do
            if probes[h.name] then
                _exec(h.name,p,e,c)
                if h.exclusive then p=nil end
            end
        end
        for name,probe in pairs(probes) do
            if not priors[name] then
                _exec(name,p,e,c)
            end
        end
    end

    --bug on file:seek('cur')
    local n=(f:read(4096):find('\n')) and 2 or 1
    f:seek('set',0)
    
    for line in f:lines() do
        offset=offset+#line+n
        full_line,curr=line,line:sub(1,256):rtrim()
        lineno,sub=lineno+1,curr:ltrim()
        for k,v in pairs(parser.probes) do
            if v.start and not finds[k] and not probes[k] then
                local found=false
                if type(v.start)=="string" then
                    found=sub:find(v.start,1,true)
                else
                    found=v.start(sub,root,lineno)
                end

                if found==1 or found==true then
                    execute(true,false,v.parse)
                    data=root[k] or {root=root}
                    root[k]=data
                    data.last_start_line,data.last_start_offset=lineno,prev_offset

                    curr_probe=table.clone(v)
                    for k1,v1 in pairs{
                        name=k,
                        data=data,
                        root=root,
                        start_line=lineno,
                        start_offset=prev_offset
                    } do curr_probe[k1]=v1 end

                    finds[k]=not curr_probe.repeatable
                    probes[k]=curr_probe
                end
            end
        end
        execute(true)
        prev_offset=offset
    end
    execute(false,true)
    f:close()

    env.checkerr(root.sql_id,'Cannot find SQL Id from the trace file!')

    root.max_lines=lineno
    root.width=math.max(5,#tostring(lineno))

    local formatter='| %'..root.width..'s | %s'
    local stack={}
    root.print=function(l,s)
        local text=formatter:format(tostring(l),s)
        print(text)
        lineno=lineno+1
        if file then stack[#stack+1]=text end
    end
    root.print_start=function(save_to)
        stack,file={},save_to
        lineno=0
        local width=console:getScreenWidth()-10
        local sep=('-'):rep(width)
        print(sep)
        if file then stack[#stack+1]=sep end
        root.print("Line#",'Text')
        print(sep)
        if file then stack[#stack+1]=sep end
    end

    root.print_end=function(feed)
        local width=console:getScreenWidth()-10
        local sep=('-'):rep(width)
        print(sep)
        if file then 
            stack[#stack+1]=sep
            print("Result saved to",env.save_data(root.prefix..file,table.concat(stack,'\n'):strip_ansi()))
        end
        if feed then print(lineno-1,'lines matched.') end
    end

    root.seek=function(lineno)
        local root=parser.data
        env.checkerr(root.file,"Please open an 10053 trace file firstly.")
        local f=root.handler
        if io.type(f)~='file' then
            root.handler=nil
            f=io.open(root.file,'r')
            env.checkerr(f,"Unable to open file: %s",root.file)
        end
        f:seek('set',0)
        local curr=1
        while curr<lineno do 
            f:read('*l') 
            curr=curr+1
        end
        root.handler=f
        return f
    end

    root.range=function(start_line,end_line)
        env.checkerr(start_line and end_line,'Invalid start_line and end_line')
        local lineno=math.max(0,start_line-1)
        local f=root.seek(start_line)
        local function next()
            lineno=lineno+1
            if lineno>end_line then return end
            return f:read('*l'),lineno
        end
        return next
    end

    local options={}
    for k,v in pairs(root) do
        if parser.probes[k] and parser.probes[k].extract then
            options[#options+1]=k
        end
    end
    table.sort(options)
    print('\n',lineno,'lines processed. Following commands are available: '..table.concat(options,','))
end

function parser.close()
    if not parser.data.file then return end
    if io.type(parser.data.handler)=='file' then pcall(parser.data.handler.close,parser.data.handler) end
    parser.data,parser.data.file,parser.data.handler={open={},close={}}
end

function parser.onload()
    build_probes()
    parser.cmds={
        open=parser.read,
        close=parser.close
    }
    local help={[[Parse 10053 trace file. type 'help @@NAME' for more detail.

                [| grid:{topic='Parameters'}
                 | Parameter | Description |
                 | open <file path> | Attach to an 10053 trace file, this is the pre-action of other operations|
                 | close | Dettach from the opened trace file |
                 | - | - |]]}
    local subs,priors={},{}
    local width=0
    for k,v in pairs(parser.probes) do
        if v.priority or v.exclusive then
            priors[#priors+1]={name=k,prior=v.priority or 100,exclusive=v.exclusive}
            priors[k]=priors[#priors]
        end
        if v.extract then
            parser.cmds[k]=v.extract.call
            subs[#subs+1]=v.extract.help:gsub("@@NAME",k)
            width=math.max(width,#(subs[#subs]:match('| *([^%s|]+)')))
        end
    end

    width='\n|% -'..width..'s '
    table.sort(priors,function(a,b) return a.prior<b.prior end)
    table.sort(subs)
    for k,v in ipairs(subs) do 
        help[#help+1]=v
    end
    parser.priors=priors
    help=table.concat(help,'\n'):gsub('\n%s*|%s*([^%s|]+)%s+',function(s) return width:format(s) end)
    env.set_command(nil,"10053",help..']',parser.command,false,5)
end

function parser.onunload()
    parser.close()
end

return parser