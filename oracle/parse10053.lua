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
        if not keyword or line:sub(1,256):rtrim():lower():find(keyword) then
            root.print(lineno,line)
        end
    end
    return root.print_end(true)
end

local function extract_timer()
    return {
        start="TIMER:",
        repeatable=true,
        closeable=false,
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
                        line=line:sub(1,256):rtrim()
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
                root.print_start('timer')
                for line,lineno in root.range(root.start_line,root.end_line) do
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
                        print(table.concat(self.data.text,'\n'))
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
                line=full_line:gsub('<!%[CDATA%[([^%]]+)%]%]>','%1'):gsub('<q ','\n  <q '):gsub('</qb_registry>','\n<qb_registry>')
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
local any={['*']=1,['.']=1,['']=1}

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
            if line:find('SQL:******* UNPARSED QUERY IS *******',1,true)==1 then
                if not root.qb[root.current_qb] then root.qb[root.current_qb]={} end
                root.qb[root.current_qb].sql=lineno+1
            end
            return false
        end,
        repeatable=true,
        priority=2,
        extract={
            help='|@@NAME <qb_name>  [<abbr>\\|*] | Show query block info with the specific QB name |',
            call=function(data,qb,abbr)
                env.checkerr(qb,"Please input the query block name.")
                if abbr then
                    if any[abbr] then
                        abbr='^%u%u+ -: (.+)' 
                    else
                        abbr='^'..abbr:upper()..' -:?(.+)' 
                    end
                end
                local level,prev
                local root,name=data.root,qb:upper()
                qb='(%W)('..qb:escape()..')(%W)'
                local curr_qb,spd,prev_line
                local function pr(l,c)
                    root.print(l,c)
                end
                local stack,seq,found={},{},{}
                root.print_start('qb_'..name)
                root.current_qb=nil
                local fmt=env.ansi.convert_ansi('%1$UDL$%2$NOR$%3')

                for line,lineno in root.range(root.start_line,root.end_line) do
                    line=line:sub(1,256):rtrim()
                    if line~='' then
                        parser.probes.qb.start(line,root,nil,false)
                        line=' '..line..' '
                        line,found=line:gsub(qb,fmt)
                        line=line:sub(2,-2)
                        if abbr then
                            if root.current_qb==name then
                                local text=line:match(abbr)
                                if text then
                                    pr(lineno,line)
                                end
                            end
                        elseif line:find('^SPD: *BEGIN') and root.current_qb==name then
                            spd=true
                            pr(lineno-1,prev_line)
                            pr(lineno,line)
                        elseif spd and line:find('^SPD: *END') then
                            spd=false
                            pr(lineno,line)
                            pr(lineno+1,prev_line)
                        elseif spd then
                            pr(lineno,line)
                        elseif line~=prev and not line:find('^([^%w ])%1%1%1%1%1') and not line:find('^TIMER:') then
                            local spaces=line:match('^%s+')
                            local lv,is_root=spaces==nil and 0 or #spaces,spaces==nil
                            stack[lv]={lineno,line}
                            if found>0 then 
                                prev=line
                                table.clear(seq)
                                for k,v in pairs(stack) do
                                    if k<=lv then seq[#seq+1]=k end
                                end
                                table.sort(seq)
                                local c=0
                                for _,l in ipairs(seq) do
                                    if stack[l][1]>c then
                                        c=stack[l][1]
                                        pr(c,stack[l][2])
                                    end
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
                end
                root.print_end(true)
            end
        }
    }
end

local function extract_tb()
    return {
        start=function(line,root)
            if not root.current_qb then return end
            return line:find("^SINGLE TABLE ACCESS PATH") or line:find('^Table Stats:+$') 
        end,
        repeatable=true,
        breakable=false,
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
                self.info={name=tab,qb=self.qb,alias=alias,[self.type]={start_line=self.start_line}}
                tab,alias=tab:upper(),alias:upper()
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
                root.current_tb=tab
                root.current_alias=alias
            elseif line:find('^ *SPD: *Return') or line:find('DS_SVC',1,true) or line:find('OPT_DYN_SAMP',1,true) then
                local found,typ=line:match(': *(%u+), *estType *= *(%u+)')
                if found then
                    found=found..'('..typ..')'
                elseif line:find('DS_SVC',1,true) then
                    found='DS_SVC'
                else
                    found='DYN_SAMP'
                end
                if found:find('^NODIR') or found:find('^NOQBCTX') then return end
                if (self.info.spd or 'NO'):find('^NO') then 
                    self.info.spd=found 
                end
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
            self.root.current_tb,self.root.current_alias=nil
            if self.info and not self.info[self.type].end_line then
                self.info[self.type].end_line=lineno-1
            end
        end,

        extract={
            help="|@@NAME [<table_name>] [<qb_name>\\|*]| Show single table stats and access paths. |",
            call=function(data,tab,qb)
                if tab then 
                    tab=tab:upper()
                    if any[tab] then tab='' end
                end
                if qb then 
                    qb=qb:upper()
                    if any[qb] then qb=nil end
                end
                local root,rows=data.root,{}
                local qbs=root.plan.qbs
                for t,v in pairs(data) do
                    if t~='root' and type(v)=='table' then
                        for q,o in pairs(v) do
                            if type(o)=='table' then
                                for alias,p in pairs(o) do
                                    if (not tab or tab==alias or tab==t or tab=='') and (not qb and (not qbs or qbs[q]) or q==qb or any[qb]) then
                                        local lines={}
                                        if p.bsi then lines[#lines+1]=p.bsi end
                                        if p.sta then lines[#lines+1]=p.sta end
                                        rows[#rows+1]={p.name,alias==t and '' or alias,q,
                                                       lines[1].start_line,lines[#lines].end_line,
                                                       p.bsi_seens or 0,p.sta_seens or 0,
                                                       p.best_sta or '',
                                                       p.spd or '',
                                                       p.qb_perms ,
                                                       p.best_jo or '',
                                                       p.jo or '',
                                                       p.jo_spd,
                                                       lines}
                                    end
                                end
                            end
                        end
                    end
                end

                if not tab then
                    env.grid.sort(rows,'3,1,4')
                    table.insert(rows,1,{"Table Name",'Alias','Query Block','Start Line','End Line','BSI Seens','STA Seens','STA Best','TB SPD','JOs','Best JO#','Join','JO SPD'})
                    env.grid.print(rows)
                    local msg='BSI: BASE STATISTICAL INFORMATION / STA: SINGLE TABLE ACCESS PATH / TB: Table / JO: Join Order'
                    print(('-'):rep(#msg)..'\n'..msg)
                    return
                end

                env.checkerr(#rows>0,'Invalid table name or query block name.')
                table.sort(rows,function(a,b) return a[4]<b[4] end)

                root.print_start('tb_'..tab..(qb and ('_'..qb) or ''))
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
        repeatable=true,
        breakable=false,
        start=function(line,root)
            if not root.current_qb then return end
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

        parse=function(self,line,lineno,full_line)
            if not self.stack then self.stack={} end
            if not self.cost then self.cost=0 end
            local root=self.root
            if line:match('^kkoqbc: finish optimizing query block') then
                self.data[self.qb].end_line=lineno
                return false
            elseif lineno==self.start_line then
                self.qb=self.root.current_qb:upper()
                self.data[self.qb]={start_line=lineno,perms={}}
                local qbs=self.root.qb
                if qbs and not qbs[self.qb] then qbs[self.qb]={} end
                qbs[self.qb].jo=self.data[self.qb]
            elseif line:find('^Join order%[') then
                local perm=tonumber(line:match('^Join order%[(%d+)%]'))
                local tables=full_line:rtrim():match(': *(%S.-%S)$'):split('%s+')
                self.stack={}
                self.data[self.qb].perm_count=perm
                local jo={lines={},tables=tables,tlines={},jo=perm,start_line=lineno,cost=0}
                self.curr_perm=self.data[self.qb].perms[perm] or jo
                if not self.data[self.qb].perms[perm] then
                    self.data[self.qb].perms[perm]=jo
                end
                root.current_jo=perm
                self:add(0,lineno)
            elseif line:find('^%*%*+ *%w+') then
                self:add(0,lineno)
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
                root.current_tb,root.current_alias=self.curr_table
                self:add(1,lineno)
            elseif line:find('^%u+ Join$') or line:find('^ +.- %u+ cost:') then
                self:add(2,lineno)
                local cost=tonumber(line:match('cost: *([%.%d]+)'))
                if cost then self.cost=math.min(cost,self.cost==0 and cost or self.cost) end
            elseif line:find('^ *Cost of predicates:') then
                self:add(2,lineno)
                self.pred=line:match('^ *')
            elseif self.pred then
                if line:find('^'..self.pred..'%s+') then
                    self:add(2,lineno)
                else
                    self.pred=nil
                    self.last_indent=1
                end
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
                self.curr_tab_index,self.curr_table,root.current_tb,root.current_alias=nil
                self:add(0,lineno)
                if line:find('^Join') then
                    if self.curr_perm.cost==0 then
                        self.curr_perm.cost='> '..math.round(self.cost,3)
                    end
                    root.current_jo=nil
                else
                    local cost,card=line:match('cost: *([%.%d]+).-card: *([%.%d]+)')
                    if cost then 
                        self.cost,self.card=tonumber(cost),math.round(tonumber(card),3) 
                    end
                    self.curr_perm.cost,self.curr_perm.card='= '..math.round(self.cost,3),self.card
                    self.cost,self.card=0,0
                    self.is_best=1
                end
                self.cost=0
            elseif self.is_best==1 then
                if line:find('^ +') then
                    self:add(0,lineno)
                    local cost,card=line:match('cost: *([%.%d]+).-card: *([%.%d]+)')
                    if cost then 
                        self.cost,self.card=tonumber(cost),math.round(tonumber(card),3)
                        self.curr_perm.cost,self.curr_perm.card='= '..math.round(self.cost,3),self.card
                    end
                else
                    self.is_best=0
                    root.current_jo=nil
                end
            elseif line:find('^%s+Best join order: *(%d+)$') then
                self.curr_tab_index,self.curr_table=nil
                local best=tonumber(line:match('%d+'))
                local qb=self.data[self.qb]
                qb.perm_best=best
                local perm=qb.perms[best]
                qb.cost,qb.card=math.round(tonumber(perm.cost:match('[%.%d]+'))),math.round(perm.card)
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
                            curr_tb.qb_perms=(curr_tb.qb_perms or 0)+qb.perm_count
                            curr_tb.jo,curr_tb.best_jo=method,best
                            if perm.tlines[i] then curr_tb.jo_spd=perm.tlines[i].spd end
                        end
                    end
                end
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
                    self:add(2,v[2])
                end
                self:add(2,lineno)
            elseif line:find('^ *SPD: *Return') or line:find('DS_SVC',1,true) or line:find('OPT_DYN_SAMP',1,true) then
                local found,typ=line:match(': *(%u+), *estType *= *(%u+)')
                if found then
                    found=found..'('..typ..')'
                elseif line:find('DS_SVC',1,true) then
                    found='DS_SVC'
                else
                    found='DYN_SAMP'
                end
                if found:find('^NODIR') or found:find('^NOQBCTX') then return end
                if self.curr_tab_index and (self.curr_perm.tlines[self.curr_tab_index][3] or 'NO'):find('^NO') then
                    self:add(2,lineno)
                    self.curr_perm.tlines[self.curr_tab_index].spd=found
                end
            elseif line~='' and not line:find('%*%*') and (self.last_indent or 0) > 0 then
                local lv=#(line:match('^%s*'))
                self.stack[lv]=lineno
            end
        end,

        end_parse=function(self,line,lineno,full_line,closer)
            local root=self.root
            if not self.data[self.qb].end_line then self.data[self.qb].end_line=lineno end
            root.current_tb,root.current_alias,root.current_jo=nil
        end,

        extract={
            help="|@@NAME [<qb_name> or *] [<JO#> or *] [<table_name>] | Show join orders, more details for more parameters |",
            call=function(data,qb,jo,tb)
                local rows,last={}
                local root=data.root
                if tb then tb=tb:upper()..'[' end
                if any[qb] and not tb then tb,jo=jo,'*' end

                for k,v in pairs(data) do
                    if type(v)=='table' and k~='root' and (not qb or qb:upper()==k or any[qb]) then
                        if not qb then
                            local best=v.perms[v.perm_best]
                            local spd=root.spd and root.spd.qbs[k] or {count=0}
                            rows[#rows+1]={k,v.perm_count,v.perm_best,v.start_line,v.end_line,v.cost,v.card,spd.count>0 and 'EXISTS' or '',table.concat(best.tables,' -> ')}
                        else
                            for i,j in ipairs(v.perms) do
                                local chain=table.concat(j.tables,' -> ')
                                if not jo or jo==tostring(i) or any[jo] then
                                    if not tb then
                                        local spd={}
                                        for c=1,#j.tables do
                                            if j.tlines[c] and j.tlines[c].spd then spd[#spd+1]=j.tlines[c].spd end
                                        end
                                        rows[#rows+1]={k,i,v.perm_best==i and 'Y' or '',j.start_line,j.end_line,j.cost,j.card,table.concat(spd,'/'),chain,j}
                                    else
                                        for c,t in ipairs(j.tables) do
                                            t=t:upper()
                                            if (t:find(tb,1,true) or tb:find(t,1,true)) and j.tlines[c] then
                                                rows[#rows+1]={k,i,v.perm_best==i and 'Y' or '',j.tlines[c][1],j.tlines[c][2],j.cost,j.card,j.tlines[c].spd or '',chain,j}
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if not qb then
                    table.insert(rows,1,{'QB Name','JOs','Best JO#','Start Line','End Line','Cost','Card','SPD','Join Chain'})
                    grid.sort(rows,4,true)
                    grid.print(rows)
                else
                    local size=#rows
                    env.checkerr(size>0,'Please input the valid QB name / JO# / table name.')
                    if not jo and size>1 then --list jo
                        table.insert(rows,1,{'QB Name','JO#','Best','Start Line','End Line','Cost','Card','JO SPD','Join Chain'})
                        grid.sort(rows,4,true)
                        grid.print(rows)
                    elseif not jo and size==1 then --display QB details
                        root.print_start('jo_'..qb)
                        qb=data[rows[1][1]]
                        for line,lineno in root.range(qb.start_line,qb.end_line) do
                            root.print(lineno,line)
                        end
                        root.print_end()
                    else
                        root.print_start('jo_'..qb..(tonumber(jo) and ('_'..jo) or '')..(tb  and ('_'..tb) or ''))
                        local fmt,prev='Query Block %s    Join Order #%d'
                        local w=root.width
                        for i,j in ipairs(rows) do
                            local pieces=j[#j].lines
                            local curr=fmt:format(j[1],j[2])
                            local counter,numsep,linesep=0
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
                                    counter=counter+1
                                    local sep=(' '):rep(pieces[lineno]*2)
                                    if counter>1 and pieces[lineno]==1 then
                                        numsep,linesep=(' '):rep(w),sep..(('-'):rep(80))
                                        root.print(numsep,linesep)
                                    elseif pieces[lineno]==0 and numsep then
                                        root.print(numsep,linesep)
                                        numsep,linesep=nil
                                    end
                                    root.print(lineno,sep..line)
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
                    print('\nResult saved to '..env.save_data(root.prefix..'.sql',text))
                else
                    local q=root.qb[qb:upper()]
                    env.checkerr(q and q.sql,"Cannot find unparsed SQL text for query block: "..qb)
                    for line in root.range(q.sql,q.sql) do
                        text=line
                    end
                    print(text)
                    print('\nResult saved to '..env.save_data(root.prefix..'_'..qb:gsub('[$@]','_')..'.sql',text))
                end
            end
        }
    }
end

local function extract_lines()
    return {
        start='sql_id=',
        extract={
            help="|@@NAME {<start_line> [<end_line>]}$COMMANDCOLOR$ \\| p \\| n \\| $NOR$<keyword> | Show matched lines with the specific line range or keyword(supports wildchar '%') |",
            call=function(data,b,e,...)
                env.checkerr(b,"Please input the start line number or keyword.")
                local root,st,ed,keyword,prev=data.root,tonumber(not b:find('^0x') and b),tonumber(e)
                local h=console:getScreenHeight()-12
                b=b:lower()
                if (b=='p' or b=='n' or b=='b' or b=='f') and data.b then
                    if b=='p' or b=='b' then
                        st,ed=data.b-h,data.b
                    else
                        st,ed=data.e,data.e+h
                    end
                end
                if not st then
                    b=table.concat({b,e,...},' ')
                    env.checkerr(#b>2,'Target search string must not be less than 3 chars.')
                    keyword='%W'..b:gsub('%%','\1\2\3'):escape():gsub('\1\2\3','.-')..'%W'
                    b,e=root.start_line,root.end_line
                else
                    b,e=st,ed
                    env.checkerr(b>0,"Please input the start line number.")
                    env.checkerr(not e or e>=b, "<end_line> must not be smaller than <start_line>.")
                    if not e then
                        data.l=b
                        b=math.max(1,math.round(b-h/2))
                        e=b+h
                    end
                    data.b,data.e=b,e
                end

                root.print_start()
                for line,lineno in root.range(b,e) do
                    if not keyword or prev~=line and (' '..line:sub(1,256)..' '):lower():match(keyword) then
                        root.print(lineno,lineno==data.l and ('$COMMANDCOLOR$'..line..'$NOR$') or line)
                        if keyword then prev=line end
                    end
                end
                root.print_end(true)
            end
        }
    }
end

local spd_patterns={'dirid *= *%d+','^SPD','%* *DS_SVC *%*','%* *OPT_DYN_SAMP *%*'}
function extract_spd()
    return {
        start=function(line,root)
            for k,v in ipairs(spd_patterns) do
                if line:find(v) then return true end
            end
        end,
        repeatable=true,
        closeable=false,
        parse=function(self,line,lineno)
            if not self.data.dirs then self.data.dirs,self.data.qbs={},{} end
            local root=self.root
            local qb=root.current_qb
            local q=self.data.qbs[qb]
            if line:find('NODIR') or line:find('NOQBCTX') then
                return false
            elseif line:find('^SPD: *BEGIN') then
                self.data.in_spd=true
                self.data.has_spd=false
                if not q then
                    q={qb=qb,lineno-1,links={},has_spd=false,count=0}
                    self.data.qbs[qb]=q
                else
                    q[3]=q[1]
                    q[1]=lineno-1
                end
                return true
            elseif line:find('^SPD: *END') then
                self.data.in_spd=false
                if self.data.has_spd then
                    q[2]=lineno+1
                elseif q.has_spd then
                    q[1]=q[3]
                else
                    self.data.qbs[qb][1]=nil
                end
                self.data.has_spd=false
                return false
            else
                local dirid=line:match('dirid *= *(%d+)')
                if self.data.in_spd then
                    if dirid then
                        self.data.has_spd=true
                        q.has_spd=true
                        q[dirid]=lineno
                    end
                else
                    local obj={qb=qb,tb=root.current_tb,jo=root.current_jo,alias=root.current_alias}
                    if not q then
                        q={qb=qb,lineno-1,links={},has_spd=false,count=0}
                        self.data.qbs[qb]=q
                    end
                    q.count=lineno
                    q.links[lineno]=obj
                end
                return self.data.in_spd==true
            end
            return false
        end,

        extract={
            help=[[|@@NAME [<qb_name>]|Show SQL Plan Directive or Dynamic Sampling information|]],
            call=function(data,qb_name)
                env.checkerr(data.qbs,"No data found.")
                local rows={}
                for k,v in pairs(data.qbs) do
                    if not qb_name or qb_name:upper()==k then
                        if type(v)=='table' and (v[1] or v.count>0) then
                            if not v[1] then v[1]=v.count end
                            rows[#rows+1]=v
                        end
                    end
                end
                env.checkerr(#rows>0,"No data found.")
                table.sort(rows,function(a,b) return a[1]<b[1] end)

                local root=data.root
                root.print_start('spd_'..(qb_name or 'all'))
                for k,qb in ipairs(rows) do
                    local w,st,ed,fmt=root.width
                    local width=#qb.qb+16
                    root.print(("="):rep(w),("="):rep(width))
                    root.print(("/"):rep(w),'|$HEADCOLOR$ Query Block '..qb.qb..' $NOR$|')
                    root.print(("="):rep(w),("="):rep(width))

                    if qb[2] then
                        for line,lineno in root.range(qb[1],qb[2]) do
                            root.print(lineno,line)
                        end
                    end

                    local lines={}
                    w=0
                    for k1,v1 in pairs(qb.links) do
                        if type(k1)=='number' and type(v1)=='table' then
                            if v1.tb then
                                fmt=('%-7s - %s'):format(v1.jo and ('JO#'..v1.jo) or 'STA',v1.tb..(v1.alias and '['..v1.alias..']' or ''))
                            else
                                fmt='  '
                            end
                            w=math.max(#fmt,w)
                            lines[k1]=fmt
                            st,ed=math.min(st or k1,k1),math.max(ed or k1,k1)
                        end
                    end
                    
                    if st then
                        fmt='%-'..w..'s: %s'
                        local prev
                        for line,lineno in root.range(st,ed) do
                            if lines[lineno] then
                                prev=line
                                line=line:trim()
                                root.print(lineno,fmt:format(lines[lineno],line))
                            end
                        end
                    end
                    if k<#rows then root.print(' ',' ') end
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
    breakable    : boolean,  when false then the started probe cannot be closed by other running probes(parallel probe)
    closeable    : boolean,  when false then the started probe will not close other running probes
    exclusive    : boolean,  when true then bypass the parsing of other concurrent probes in case of this probe is started
    priority     : number,   smaller number means higher priority(default 1000)
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
        spd=extract_spd(),
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
    build_probes,extract_plan,extract_qb,extract_tb,extract_sql,extract_lines,extract_jo,extract_timer,extract_spd=nil
end

local filelist={}

function parser.check_file(f,path,seq)
    local ary,lineno=filelist[path]
    local q,o,s='Registered qb: [A-Z]+$1 ','End of Optimizer State Dump','Current SQL Statement for this session'
    if not ary then
        local st,ed,sql_id
        local q1,o1,sql_id='^'..q,'^'..o
        ary={}
        filelist[path]=ary
        lineno=0
        for line in f:lines() do
            lineno=lineno+1
            line=line:sub(1,256)
            if not (st or ed) and line:match(q1) then
                st=lineno
            elseif st and not ed then
                if not sql_id and line:find(s) then
                    sql_id=line:match('sql_id=(%w+)')
                elseif sql_id and line:match(o1) then
                    ed=lineno
                    ary[#ary+1]={st,ed,sql_id}
                    st,ed,sql_id=nil
                end
            end
        end
    end

    if #ary==1 or (seq and ary[seq]) then
        if lineno then f:seek('set',0) end
        local st,ed,sql_id=table.unpack(ary[seq or 1])
        if st>1 then
            lineno=1
            for line in f:lines() do
                lineno=lineno+1
                if lineno>=st then break end
            end
        end
        return st,ed,sql_id
    end

    f:close()
    if #ary==0 then
        env.warn('The target file is not an 10053 trace file, or the content is incompleted due to some of the following lines are missing:')
        env.warn('    1). '..q)
        env.warn('    2). '..s)
        env.warn('    3). '..o)
        env.raise('Please choose another valid 10053 trace file.')
        return
    end

    local rows={{'Seq','Start Line','End Line','SQL Id'}}
   
    for k,v in ipairs(ary) do
        rows[k+1]={k,v[1],v[2],v[3]}
    end
    print('Mutiple SQL traces are found:')
    grid.print(rows)
    print('\n')
    env.raise('Please open the file plus the specific seq among above list!')
end

function parser.read(data,file,seq)
    local f=io.open(file,'rb')
    env.checkerr(f,"Unable to open file: %s",file)
    
    local start_line,end_line,sql_id=parser.check_file(f,file,tonumber(seq))
    local short_name=file:match('([^\\/]+)$')
    local lines,data={}
    local curr_probe
    local lineno,offset,prev_offset,size,curr,sub,full_line=start_line-1,0,0

    parser.close()
    local root=parser.data
    root.file,root.start_line,root.end_line=file,start_line,end_line
    root.prefix=short_name:match('^[^%.]+')

    local probes,finds,priors={},{},parser.priors

    local function end_parse(name,closer)
        local probe=probes[name]
        if not probe then return end
        probe.data.last_end_line,probe.data.last_end_offset=lineno-1,prev_offset
        probe.end_line,probe.end_offset=lineno-1,prev_offset
        if probe.end_parse then
            if closer then
                probe:end_parse(nil,lineno,full_line,closer)
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
        if res==false then return end_parse(name) end
    end

    local function _exec(name,p,e,c)
        if c and probes[name].breakable==false then return end
        if c or p then parse(name) end
        if c or e~=nil then end_parse(name,c) end
    end

    local function execute(p,e,c)
        for i,h in ipairs(priors) do
            if probes[h.name] then
                _exec(h.name,p,e,c)
                if h.exclusive then p=nil end
            end
        end
    end

    --bug on file:seek('cur')
    print('Analyzing the trace file for SQL Id: '..sql_id)
    for line in f:lines() do
        offset=offset+#line+1
        full_line,curr=line,line:sub(1,256):rtrim()
        lineno,sub=lineno+1,curr:ltrim()
        for i,n in ipairs(priors) do
            local k,v=n.name,n.probe
            local p=probes[k]
            if p and p.exclusive then
                break
            elseif v.start and not finds[k] and not p then
                local found=false
                if type(v.start)=="string" then
                    found=sub:find(v.start,1,true)
                else
                    found=v.start(sub,root,lineno,full_line)
                end

                if found==1 or found==true then
                    if v.closeable~=false then 
                        execute(true,false,v.parse and k) 
                    end
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

                    if curr_probe.exclusive then break end
                end
            end
        end
        execute(true)
        prev_offset=offset
        if lineno>=end_line then break end
    end

    execute(false,true,'EOF')
    f:close()

    local options={}
    for k,v in pairs(root) do
        if parser.probes[k] and parser.probes[k].extract then
            options[#options+1]=k
        end
    end
    table.sort(options)
    print('\n',end_line-start_line+1,'lines processed. Following commands are available: '..table.concat(options,','))
    root.max_lines=lineno
    root.width=math.max(5,#tostring(lineno))

    local formatter='| %'..root.width..'s | %s'
    local stack={}
    root.print=function(l,s)
        local text=formatter:format(tostring(l),s)
        print(text)
        if tonumber(l) then lineno=lineno+1 end
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
        if lineno>0 then
            local sep=('-'):rep(width)
            print(sep)
        end
        if file then 
            stack[#stack+1]=sep
            file=file:gsub('[$@/\\%*%?<>]','_'):lower()
            print("Result saved to",env.write_cache(root.prefix..'_'..file..'.txt',table.concat(stack,'\n'):strip_ansi()))
        end
        if feed then print(lineno,'lines matched.') end
    end

    root.seek=function(lineno)
        local root=parser.data
        env.checkerr(root.file,"Please open an 10053 trace file firstly.")
        local f=root.handler
        if io.type(f)~='file' then
            root.handler=nil
            f=io.open(root.file,'rb')
            if not f then
                root.file=nil
                env.raise("Unable to open file: %s",root.file)
            end
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
        start_line=math.min(root.end_line,math.max(root.start_line,start_line))
        end_line  =math.max(root.start_line,math.min(root.end_line,end_line))
        local lineno=math.max(0,start_line-1)
        local f=root.seek(start_line)
        local function next()
            lineno=lineno+1
            if lineno>end_line then return end
            return f:read('*l'),lineno
        end
        return next
    end    
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
        [| grid:{topic='List of 10053 Commands'}
         | Command | Description |
         | open <file path> [<seq>] | Attach to an 10053 trace file, this is the pre-action of other operations|
         | close | Dettach from the opened trace file |
         | - | - |]]}
    local subs,priors={},{}
    local width=0
    for k,v in pairs(parser.probes) do
        priors[#priors+1]={name=k,prior=v.priority or v.exclusive and 100 or 1000,exclusive=v.exclusive,probe=v}
        if v.extract then
            parser.cmds[k]=v.extract.call
            subs[#subs+1]=v.extract.help:gsub("@@NAME",k)
            width=math.max(width,#(subs[#subs]:match('| *([^%s|]+)')))
        end
    end

    width='\n| %-'..width..'s '
    table.sort(priors,function(a,b) return a.prior<b.prior end)
    table.sort(subs)
    for k,v in ipairs(subs) do 
        help[#help+1]=v
    end
    parser.priors=priors
    help=table.concat(help,'\n'):gsub('\n%s*|%s*([^%s|]+)%s*',function(s) return width:format(s) end)..']'

    env.set_command(nil,"10053",help,parser.command,false,5)
end

function parser.onunload()
    parser.close()
end

return parser