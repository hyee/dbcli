local env=env
local parser=env.class(env.lexer)
local table,math,pairs,type,print,ipairs,io=table,math,pairs,type,print,ipairs,io
local qb_exp='%u%u%u+$[%u%d]+'
local xml2lua = require("xml2lua")
local handler = require("xmlhandler.tree")

function parser:ctor()
    self.name='10053'
end

local function get_dop(line,default)
    return tonumber(line:match('[dD]egree: *(%d+)')) or default or 1
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
            local ary=data.qbs[qb]

            data.lines[lineno]=qb or 'ROOT'
            if qb then
                if not ary then
                    ary={0,0,0}
                    data.qbs[qb]=ary
                end
                --re-calc the cost for (Overall) and (Final) due to overlap
                if (line:find('(Overall)',1,true) or line:find('(Final)',1,true)) and ary then
                    data.cpu,data.ela=data.cpu-ary[2],data.ela-ary[3]
                    ary[2],ary[3]=0,0
                end
                ary[1],ary[2],ary[3]=ary[1]+1,ary[2]+cpu,ary[3]+ela
                data.count,data.cpu,data.ela=data.count+1,data.cpu+cpu,data.ela+ela
            end
            return false
        end,

        extract={
            --[[
                option:
                    -l       : list the raw timer data
                    <keyword>: list the raw timer data matching the keyword(case insensitive)
            --]]
            help="|@@NAME [-l\\|<keyword>] |Show timer (fix control # 16923858)|",
            call=function(this,data,option)
                env.checkerr(data and data.count,"No data found.")
                local root=data.root
                if root.qbs and not option then
                    --load qb tree from Query Block Regitries
                    local qbs=this.probes.qbs.extract.call(this,root.qbs,nil,false)
                    local rows={}
                    local stack={}
                    local idx=0
                    local prev
                    for i=2,#qbs do
                        local line=qbs[i][1]:strip_ansi()
                        local qb=line:match(qb_exp)
                        if qb then
                            local timer=data.qbs[qb] or {0,0,0}
                            local lv=#(line:match('^%s*'))
                            idx=idx+1
                            stack[lv]=idx
                            rows[#rows+1]={'|',timer[1],timer[2],timer[3],data.ela and timer[3]/data.ela or 0,(lv==0 and '' or '|')..qbs[i][1],0,lv}
                            if timer[1]>0 then
                                --Also show the parent nodes even they has no timer recods to completely show the hierachy
                                for k,v in pairs(stack) do
                                    if k<=lv then
                                        rows[v][7]=rows[v][7]+timer[2]
                                    end
                                end
                                table.clear(stack)
                            end
                            if lv==0 and idx>1 and prev>0 and rows[#rows][2]==0 and rows[#rows-1][2]>0 then 
                                rows[#rows-1][1]='$UDL$|'
                                rows[#rows-1][6]=rows[#rows-1][6]:gsub('$NOR%$','$NOR$$UDL$')
                            end
                            prev=lv
                        end
                    end

                    for i=#rows,1,-1 do
                        if rows[i][7]==0 then
                            --remove the records who and its child nodes all have no timer record
                            table.remove(rows,i) 
                        else
                            for j=1,5 do
                                if rows[i][j]==0 then rows[i][j]='' end
                            end
                        end
                    end
                    env.var.define_column('cpu,elapsed','for','usmhd2')
                    env.var.define_column('ela%','for','pct3')
                    table.insert(rows,1,{'|','Count','CPU','Elapsed','Ela%','Query Block Registry'})
                    rows[#rows+1]={'=','=','=','=','=','='}
                    rows[#rows+1]={'',data.count,data.cpu,data.ela,1,'----- TOTAL -----'}
                    env.grid.print(rows)
                    env.var.define_column('cpu,elapsed','clear')
                    return
                end

                option=option:lower()
                if option=='-l' then  option='$' end
                local fmt='%-12s:   %s'
                root.print_start('timer')
                for line,lineno in root.range(root.start_line,root.end_line) do
                    local l=fmt:format(data.lines[lineno],line)
                    if data.lines[lineno] and l:lower():find(option,1,true) then
                        root.print(lineno,l)
                    end
                end
                root.print_end(true)
            end
        }
    }
end

local function extract_plan()
    return {
        start=function(line) return line:find('^%-[%s%-]+ Explain Plan Dump[%s%-]*$') end,
        set_end_line=function(self,lineno,curr,adj)
            if not self.data.line_ranges then self.data.line_ranges={} end
            self.data.last_block=curr
            for k,v in pairs(self.data.line_ranges) do
                if not v[2] then v[2]=lineno-1 end
            end
            if curr then self.data.line_ranges[curr]={adj or lineno} end
        end,

        parse=function(self,line,lineno)
            --record the line range for each component of the execution plan
            if line:find('^| *Id *| ') then
                self:set_end_line(lineno,'plan',lineno-1)
            elseif line:find('^Query Block Name') then
                self:set_end_line(lineno,'qb')
            elseif line:find('^Predicate Information') then
                self:set_end_line(lineno,'pred')
            elseif line:find('^Content of other_xml column') then
                self:set_end_line(lineno,'xml')
            elseif line:find('^QUERY BLOCK REGISTRY') then
                self:set_end_line(lineno,'qbr')
            elseif line:find('^ * Outline Data:') then
                self:set_end_line(lineno,'outline')
            elseif line=='' and self.data.last_block and self.data.last_block~='plan' then
                self.data.line_ranges[self.data.last_block][2]=lineno-1
            end
        end,

        end_parse=function(self,line,lineno)
            self:set_end_line(lineno)
        end,

        load=function(self,part)
            local root=self.root
            for line,lineno in self.root.range(self.last_start_line,self.last_end_line) do
                line=line:rtrim()
                --init the metadata at the beginning
                if lineno==self.last_start_line then
                    self.text={}
                    self.plan={}
                    self.qb_pattern={'^ *(%d+) +%- +(%S+) +/ +(%S+)$','^ *(%d+) +%- +(%S+)$'}
                    self.lines=0
                    self.plan_start=nil
                    self.qb_start=nil
                    self.add=function(self,text)
                        self.lines=self.lines+1
                        self.text[self.lines]=text
                    end
                    self.print=function(self)
                        if not self.text then return '' end
                        local lines=table.concat(self.text,'\n')
                        local rows={{'Execution Plan Dump'}}
                        for k,v in ipairs(self.text) do
                            rows[k+1]={v}
                        end
                        env.grid.print(rows)
                        self.text,self.plan,rows=nil
                        if lines=='' then line='No execution plan found' end
                        return lines
                    end
                --keep parsing in this block if the plan line has not started
                elseif self.plan_start==nil then
                    if line:find('^| *Id *| ') then
                        self.plan[#self.plan+1]=line
                        self.plan_start=0
                    end
                --record the plan lines untile the end
                elseif self.plan_start then
                    self.plan[#self.plan+1]=line
                    if line:find('--------',1,true)==1 then
                        self.plan_start=self.plan_start+1
                        if self.plan_start==2 then
                            self.plan_start=false
                        end
                    end
                --Find the header of the QB informaiton
                elseif self.qb_start==nil and line:find('^Query Block Name') then
                    self.qb_start=0
                    self.qbs={}
                    self.qb_len,self.alias_len=3,5
                --Parse QB/Alias informaiton
                elseif self.qb_start then
                    --search the matching plan line id
                    local id,qb,alias=line:match(self.qb_pattern[1])
                    if not id then
                        id,qb=line:match(self.qb_pattern[2])
                        alias=''
                    end
                    --if the matching plan line id is found
                    if id then
                        id=tonumber(id)
                        self.qb_start=id
                        self.qb_len=math.max(self.qb_len,#qb)
                        self.alias_len=math.max(self.alias_len,#alias)
                        self.qbs[id]={qb,alias}
                        --record the plan line id into global qbs information that used for other commands so that they know it's the final qb: qbs/jo/tb
                        if root.qbs[qb] then
                            root.qbs[qb].in_plan=root.qbs[qb].in_plan or id
                            if not self.qbs[qb] then self.qbs[qb]={} end
                            if alias~='' then self.qbs[qb][alias]=id end
                        end
                    elseif self.qb_start>0 then
                        --else it means reaching the end of the QB information
                        self.qb_start=false
                        local fmt="%s %s%-"..self.qb_len.."s%s | %-"..self.alias_len.."s|"
                        local sep=self.plan[2]..('-'):rep(self.qb_len+self.alias_len+5)
                        self:add(sep)
                        self:add(fmt:format(self.plan[1],'','Q.B','','Alias'))
                        self:add(sep)
                        local hier,stack,found={_vws={}},{}
                        local stack1,names={hier},{}
                        self.hier=hier
                        local spaces=function(len) return (' '):rep(len) end
                        for i=3,#self.plan-1 do
                            local plan=self.plan[i]
                            local qb=self.qbs[i-3] or {"",""}
                            local plan1=plan:gsub('%([^|]+%)',function(s) return spaces(#s) end):gsub('(%u) (%u)','%1_%2')
                            local indent,op,tb=plan1:match('|([^|]+) +([%u_]+) *|*([^|]-)|')

                            if indent then
                                indent=#indent
                                for j=#stack,1,-1 do
                                    if stack[j][2]>=indent or (names[qb[1]] and hier~=names[qb[1]]) then
                                        table.remove(stack)
                                        table.remove(stack1)
                                        hier=stack1[#stack1]
                                    else
                                        break
                                    end
                                end
                            end
                            if indent and qb[1]~='' then
                                --Build QB hierachy
                                if hier._name~=qb[1] then
                                    hier[qb[1]]={_indent=indent,_id=i-3,_name=qb[1],_tables={}}
                                    hier=hier[qb[1]]
                                    stack[#stack+1]={qb[1],indent}
                                    stack1[#stack1+1]=hier
                                    names[qb[1]]=hier
                                end

                                tb=tb:trim()
                                local h=stack1[#stack1-1]
                                if tb and tb~='' then
                                    if hier._id==i-3 then
                                        hier._vw=tb
                                        self.hier._vws[tb]=hier._name
                                        if h and h._name then h._tables[tb]=i-3 end
                                    else
                                        hier._tables[tb]=i-3
                                    end
                                end

                                --replace empty view name in the execution plan as internal view name
                                if qb[2]~='' and op:find('^VIEW') and tb=='' and h and h._name then
                                    local vw=hier._vw
                                    if not vw then
                                        local pq=h._name
                                        local tbs=root.jo and root.jo[pq] and root.jo[pq].perms[1].tables or {}

                                        local tb='['..qb[2]:gsub('"',''):match('^[^@]+')..']'
                                        for j,t in ipairs(tbs) do
                                            if t:find(tb,1,true) then
                                                if not vw or t:upper()~=t or t:find('^VW') then
                                                    vw=t:gsub('%[.*','')
                                                end
                                            end
                                        end
                                    end
                                    if vw then
                                        h._tables[vw]=i-3
                                        local w=#vw
                                        hier._vw=vw
                                        self.hier._vws[vw]=hier._name
                                        vw=('$HIC$'..vw..'$NOR$'):convert_ansi()
                                        plan=plan:gsub('(| +VIEW.-)( +)| ( +)|',function(a,b,c)
                                            local fmt=a..'%s| %s|'
                                            if #c>=w then
                                                return fmt:format(b,vw..spaces(#c-w))
                                            elseif #b>w+3 then
                                                return fmt:format(' ('..vw..')'..spaces(#b-w-3),c)
                                            else
                                                return a..' ('..vw..')'..spaces(#b+#c+2-w-3)..'|'
                                            end
                                        end)
                                    end
                                end
                            end
                            self.qbs[i-3]=nil
                            if qb[1]~='' then found=true end
                            --Mark the QB that has unparsed SQL as blue
                            self:add(fmt:format(plan,
                                                qb[1]~='' and root.qbs[qb[1]] and root.qbs[qb[1]].sql and '$HIB$' or '',
                                                qb[1],
                                                qb[1]~='' and root.qbs[qb[1]] and root.qbs[qb[1]].sql and '$NOR$' or '',
                                                qb[2]))
                        end
                        self:add(sep)
                        if found then 
                            self:add('* The unparsed sql for the $HIB$blue$NOR$ query block can be extracted via "10053 sql <qb_name>"')
                        end
                        if part=='plan' then return self:print() end
                    end
                --this is for <=11g who doesn't have QB/Alias information
                elseif self.qb_start==nil and self.plan and #self.plan>1 then
                    self:add(self.plan[2])
                    for k,v in ipairs(self.plan) do self:add(v) end
                    if part=='plan' then 
                        return self:print() 
                    else
                        self.plan=nil
                    end
                --formate the XML of QB registry(>=19c)
                elseif line:find('<qb_registry>',1,true) then
                    line=line:gsub('<!%[CDATA%[([^%]]+)%]%]>','%1'):gsub('<q ','\n  <q '):gsub('</qb_registry>','\n<qb_registry>')
                    self:add(line)
                else 
                    self:add(line)
                end
            end
            return self:print()
        end,

        on_finish=function(self,data)
            self.load(data,'plan')
        end,

        extract={
            help='|@@NAME [plan \\| pred \\| outline \\| qb \\| qbr \\| xml]|Show execution plan|',
            call=function(this,data,option)
                if option then option=option:lower() end
                env.checkerr(not option or data.line_ranges[option],'Invalid option or no data: '..(option or ''))
                if not option or option=='plan' then
                    local text=this.probes.plan.load(data,option)
                    return print("Result saved to "..env.write_cache(data.root.prefix..'_plan_'..(option and option or 'all')..'.txt',text))
                    
                end
                local root=data.root
                local o=data.line_ranges[option]
                root.print_start('plan_'..option)
                for line,lineno in root.range(o[1],o[2]) do
                    local ls={line}
                    --formate the XML of QB registry(>=19c)
                    if line:find('<qb_registry>',1,true) then
                        line=line:gsub('<!%[CDATA%[([^%]]+)%]%]>','%1'):gsub('<q ','\n  <q '):gsub('</qb_registry>','\n<qb_registry>')
                        ls=line:split('[\n\r]+')
                    end
                    for i,l in ipairs(ls) do
                        root.print(lineno,l)
                    end
                end
                root.print_end()
            end
        }
    }
end

local any={['*']=1,['.']=1,['']=1}
local op_offset=0
local function check_op(line,root,qb)
    --if not line:find('^%u%u+:') then return end
    local pt='%u%u+'
    if not qb then 
        qb=root.prev_qb
        if root.prev_op then pt=root.prev_op end
    end
    if qb and root.qbs[qb] then
        local op=line:match('^('..pt..') *:')
        if not op then
            if op_offset<5 then
                op_offset=op_offset+1
                op=root.prev_op
            end
        else
            op_offset=0
        end
        if op and root.qbs[qb] then
            local ln,ops=' '..line:lower(),root.qbs[qb].ops
            if  ln:find(' bypass',1,true) or 
                ln:find(' not? ') or 
                ln:find(' fail',1,true) or
                ln:find(' invalid ',1,true) then
                --mark the op as failed that can be shown in '10053 qbs'
                ops[op]=0
            else
                ops[op]=ops[op] or 1
            end
            root.prev_qb,root.prev_op=qb,op
            return true
        else
            root.prev_qb,root.prev_op=nil
        end
    end
    return false
end

local qb_patterns={'^Registered qb: *(%u[%u%d$_]+)','^%w+:.- ('..qb_exp..') ','^Query Block +(%u[%u%d$_]+)',' qb_name=(%u[%u%d$_]+) '}
local function extract_qb()
    return {
        --target_qb: used by the extract.call function
        start=function(line,root,lineno,full_line,target_qb)
            local qb,curr_fmt,curr_pt,ln
            if target_qb then
                ln,curr_fmt,curr_pt=(' '..line..' '),root.current_qb_formatter,root.current_search_qb
            end
            --Scan QB info on each trace line
            for i,p in ipairs(qb_patterns) do
                qb=line:match(p)
                if qb then
                    qb=qb:upper()
                    --Mark the line and onward as the scope of this QB, so that other working probes know the QB, until next QB is matched
                    if i~=2 or line:find('Considering .-[Qq]uery.- [Bb]lock') or line:find('optimizing query block') then
                        root.current_qb=qb:upper()
                    end

                    root.prev_qb,root.prev_op=qb

                    if target_qb then
                        return ln:gsub(curr_pt,curr_fmt)
                    end
                    
                    --If the line starts with "Registered qb" then build the hierachy tree and save into root.qbs
                    if i==1 then
                        if not root.qbs then root.qbs={seq={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,[0]=0}} end
                        if not root.qbs[qb] then
                            root.qbs.seq[1]=root.qbs.seq[1]+1
                            local chain=line:match('%((.+)%)$')
                            local fmt='%s%03X'
                            local seq,str,parent=0,''
                            local obj={name=qb,seq=root.qbs.seq[1],chain=chain,depth=1,lineno=lineno,childs={},ops={}}
                            for q in chain:gmatch('%u%u%u+$[%u%d]+') do
                                if root.qbs[q] then
                                    local s=root.qbs[q].seq
                                    if s>seq then
                                        seq=s
                                        parent=root.qbs[q]
                                        obj.depth=parent.depth+1
                                        str=root.qbs[q].id
                                        fmt='%s%02X'
                                    end
                                    local found=false
                                    for k,v in ipairs(root.qbs[q].childs) do
                                        if v==qb then found=true end
                                    end
                                    if not found then
                                        root.qbs[q].childs[#root.qbs[q].childs+1]=qb
                                    end
                                end
                            end
                            if obj.depth>1 then
                                if parent.childs[#parent.childs]==qb then
                                    parent.childs[#parent.childs]=nil
                                end
                                root.qbs.seq[obj.depth]=(root.qbs.seq[obj.depth] or 0)+1
                            end
                            obj.id=fmt:format(str,root.qbs.seq[obj.depth])
                            root.qbs.seq[0]=math.max(root.qbs.seq[0],#obj.id)
                            root.qbs[qb]=obj 
                        end
                    elseif i==2 then
                        --If the line starts with abbr op(i.e.: 'JDDP:''), then check wether the op is bypassed/failed/etc
                        check_op(line,root,qb)
                    end

                    --For the unknown qb that never has 'Registered qb', then mark it as missing qb
                    if not root.qbs or not root.qbs[qb] then
                        if root.qbs then 
                            if not root.qbs.missings then root.qbs.missings={} end
                            if not root.qbs.missings[qb] then return false end
                            root.qbs.missings[qb]=true
                        else
                            root.qbs={missings={[qb]=true}}
                        end
                        print('Cannot find query block register entry: '..qb)
                        return false
                    end
                    return true
                end
            end
            
            local found=check_op(line,root)
            if target_qb then
                local l,f=ln:gsub(curr_pt,curr_fmt)
                return l,f,target_qb==root.prev_qb and found or false
            end

            if not root.qbs then return line,0 end
            --record the unparsed sql line for each qb
            if line:find('^QUERY BLOCK TEXT') or line:find('****** UNPARSED QUERY IS ******',1,true) and not line:find('^Stmt') and not line:find('^Final') then
                if not root.qbs[root.current_qb].sql then
                    root.qbs[root.current_qb].sql={}
                end
                table.insert(root.qbs[root.current_qb].sql,lineno+1)
            end
            return false
        end,

        repeatable=true,
        closeable=false,
        priority=2,
        extract={
            --[[--
                <qb_name>: fuzzy search the trace lines that related to the specific QB
                <abbr>   : fuzzy search the trace lines that related to the specific QB + abbr

            --]]--
            help='|@@NAME <qb_name>  [<abbr>\\|*] | Show query block info with the specific QB name |',
            call=function(this,data,qb,abbr)
                env.checkerr(qb,"Please input the query block name.")
                if abbr then
                    if any[abbr] then
                        abbr='^%u%u+ -: (.+)' 
                    else
                        abbr='^'..abbr:upper()..' -:?(.+)' 
                    end
                end
                local level,prev,lv,spaces
                local root,name=data.root,qb:upper()
                
                local spd,prev_line
                local function pr(l,c) root.print(l,c)end
                local stack,seq,found={},{},{}
                root.print_start('qb_'..name)
                root.current_qb=nil
                root.current_search_qb='(%W)('..qb:upper():escape()..')(%W)'
                root.current_qb_formatter=env.ansi.convert_ansi('%1$UDL$%2$NOR$%3')
                local full_text,op
                for line,lineno in root.range(root.start_line,root.end_line) do
                    full_text,line=line,line:sub(1,256):rtrim()
                    if line~='' then
                        line,found,op=this.probes.qb.start(line,root,lineno,full_text,name)
                        line=line:sub(2,-2)
                        spaces=line:match('^%s+')
                        lv=spaces==nil and 0 or #spaces
                        if abbr then
                            if root.current_qb==name or found>0 then
                                local text=line:match(abbr)
                                if text then
                                    pr(lineno,line)
                                end
                            end
                        --For block level SPD informaiton, show the complete content
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
                        --Skip timer and line seperators (such as ====,----,****)
                        elseif line~=prev and not line:find('^([^%w ])%1%1%1') and not line:find('^TIMER:') then
                            stack[lv]={lineno,line}
                            if found>0 then 
                                prev=line
                                table.clear(seq)
                                --if current line matches the target QB, also print its parent lines(smaller indents)
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
                            --print abbr information(such as JDDP)
                            elseif op then
                                pr(lineno,line)
                            elseif line~='' and lv==0 or (level and lv<=level) then
                                level=nil
                            --print the child lines of the matched line(larger indents)
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

local function pair(o)
    return ipairs(type(o)~='table' and {} or (type(o[1])=='table' or #o>1) and o or {o})
end

local function extract_qbs()
    return {
        start=function(line,root,lineno,full_line)
                if root.plan and line:find('^<qb_registry>') and full_line and full_line:sub(-128):find('</qb_registry>%s*$') then
                    local content=handler:new()
                    local parser=xml2lua.parser(content)
                    local done,err=pcall(parser.parse,parser,full_line)
                    if not done then return end
                    local transforms={}
                    root.qb_transforms=transforms
                    
                    for _,q in pair(content.root.qb_registry.q) do
                        if type(q.n)=='string'  then
                            if type(q.p)=='string' then
                                transforms[q.p]=q.n
                            end
                            for _,o in pair(q.i and q.i.o) do
                                if o.v then
                                    transforms[o.v]=q.n
                                end
                            end
                        end
                    end
                    return
                end
                return root.fixctl and line:find("Query Block Registry:",1,true)
            end,
        extract={
            --The infomation of root.qbs is generated by extract_plan and extract_qb
            help="|@@NAME [<keyword>] \\| [-raw [<keyword>]] | Show Registered Query Blocks |",
            call=function(this,data,keyword,is_print)
                if keyword and keyword:lower()=='-raw' then
                    return this:pattern_search(data,is_print)
                end
                local fmt,fmt1='%s%s%s%s (%s)','%s'
                local qbs,chains={},{}
                for k,v in pairs(data) do
                    if type(v)=='table' and v.id then
                        qbs[#qbs+1]=v
                        --sort and mark the failed ops (in extract_qb) as red
                        local cbqt={}
                        for o,n in pairs(v.ops) do cbqt[#cbqt+1]=o end
                        table.sort(cbqt)
                        for i,n in ipairs(cbqt) do
                            if v.ops[n]==0 then
                                cbqt[i]='$HIR$'..n..'$NOR$'
                            end
                        end
                        v.cbqt=table.concat(cbqt,';')
                    end
                end
                table.sort(qbs,function(a,b) return a.id<b.id end)
                if keyword then
                    --if keyword is specified and the line is matched, then highlight the matched word, as well as displaying the whole hierachy
                    keyword='(%W)('..keyword:upper():escape():rtrim(';')..')(%W)'
                    fmt1='%1$COMMANDCOLOR$%2$NOR$%3'
                    for i,q in ipairs(qbs) do
                        if q.depth==1 then chains={} end
                        q.child_chains=chains
                        if not chains[1] and (';'..q.name..';'..q.chain..';'..table.concat(q.childs,';')..';'):upper():find(keyword) then
                            chains[1]=q.depth
                        end
                    end
                end
                local rows,sep,found={},' '
                for i,q in ipairs(qbs) do
                    if not keyword or q.child_chains[1] then
                        local chain=q.chain..(#q.childs==0 and '' or (' => '..table.concat(q.childs,';',1,math.min(5,#q.childs)))) 
                        --if target QB can be found in execution plan lines(extract_plan), then mark it as blue
                        if q.in_plan then found=true end
                        rows[#rows+1]={fmt:format(sep:rep(q.depth-1),
                                            q.in_plan and '$HIB$' or '',
                                            not keyword and q.name or (' '..q.name..' '):gsub(keyword,fmt1):trim(),
                                            q.in_plan and '$NOR$' or '',
                                            not keyword and chain or (' '..chain..' '):gsub(keyword,fmt1):trim()
                                            ), q.in_plan or '','|',q.seq,q.lineno,q.cbqt}
                    end
                end
                table.insert(rows,1,{'Query Block Registry','Plan#','|','QB#','Line#','Query Transformations'})
                if is_print==false then return rows end
                env.grid.print(rows)
                if found then
                    print(('-'):rep(112))
                    print('* The $HIB$blue$NOR$ query blocks can be found in the execution plan, and the $HIR$red$NOR$ abbrs means the operations are bypassed.')
                end

                local hier=data.root.plan and data.root.plan.hier
                local vws={}
                local function fill_hier(h,sep,siblings,is_last)
                    local tbs={}
                    if h._name then
                        local row={h._id,sep..(siblings>0 and (is_last and '!-' or '|-') or '')..h._name,''}
                        if h._vw then 
                            row[2]=row[2]..' ('..h._vw..')' 
                        end
                        for k,v in pairs(h._tables or {}) do
                            tbs[#tbs+1]={k,v}
                        end
                        
                        table.sort(tbs,function(a,b) return a[2]<b[2] end)
                        if #tbs>0 then
                            local strs={}
                            for k,v in ipairs(tbs) do
                                strs[k]=hier._vws[v[1]] or v[1]
                            end
                            row[3]=table.concat(strs,', ')
                        end
                        rows[#rows+1]=row
                        sep=sep..(siblings>0 and (is_last and '  ' or '| ') or '')..'  '
                        tbs={}
                    end
                    for k,v in pairs(h) do
                        if type(v)=='table' and v._id then
                            tbs[#tbs+1]={v,v._id}
                        end
                    end
                    table.sort(tbs,function(a,b) return a[2]<b[2] end)
                    for k,v in ipairs(tbs) do
                        fill_hier(v[1],sep,#tbs-1,k==#tbs)
                    end
                end
                if hier and not keyword then
                    print('\n')
                    rows={{'Plan#','Query Block Hierachy','Child Objects'}}
                    fill_hier(hier,'',0,true)
                    env.grid.print(rows)
                end
            end
        },
        parse=function(self,line,lineno)
            if line=='' or line:find('^([%*=])%1%1$') then return false end
        end
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
                --Determine the source of the line: "SINGLE TABLE ACCESS PATH" or "BASE STATISTICAL INFORMATION"
                self.type=line:find('^SINGLE') and 'sta' or 'bsi'
                return
            elseif lineno==self.start_line+1 then
                self.qb=root.current_qb
                local tab,alias
                --Scan table name and alias
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
                --Build a map
                self.tmp_info,self.tmp_link,self.tmp_alias=nil
                self.info={name=tab,qb=self.qb,alias=alias,[self.type]={start_line=self.start_line}}
                tab,alias=tab:upper(),alias:upper()
                --Dict tree: table => qb => alias => map
                
                local grp=self.data[tab] or {}
                if not grp[self.qb] then grp[self.qb]={} end
                if not grp[self.qb][alias] then 
                    grp[self.qb][alias]=self.info 
                else
                    self.tmp_info,self.tmp_link,self.tmp_alias=table.clone(grp[self.qb][alias]),grp[self.qb],alias
                    grp[self.qb][alias][self.type]=self.info[self.type]
                    self.info=grp[self.qb][alias]
                end
                grp[self.qb][alias][self.type..'_seens']=(grp[self.qb][alias][self.type..'_seens'] or 0)+1
                self.data[tab]=grp
                --Globally report current working table
                root.current_tb=tab
                root.current_alias=alias
            elseif line:find('^ *SPD: *Return') or line:find('DS_SVC',1,true) or line:find('OPT_DYN_SAMP',1,true) then
                --Handle SPD and dynamic sampling
                local found,typ=line:match(': *(%u+), *estType *= *(%u+)')
                if found then
                    found=found..'('..typ..')'
                elseif line:find('DS_SVC',1,true) then
                    found='DS_SVC'
                else
                    found='DYN_SAMP'
                end
                --Bypass NODIR/NOQBCTX/NOCTX
                if found:find('^NO') then return end
                if (self.info.spd or 'NO'):find('^NO') then 
                    self.info.spd=found 
                end
            elseif self.type=='sta' and line:find('Best:: AccessPath: *(%S+)') then
                --Handle the best candidate
                self.info.indent,self.info.best_sta=line:match('( *)Best:: AccessPath: *(%S+)')
            elseif self.info.indent then
                if not line:match('^'..self.info.indent) then
                    self.info.indent=nil
                else--Search the cost/card of the child lines of the best candidate
                    local cost,card=line:match('[cC]ost: *([%.%d]+).-[cC]ard: *([%.%d]+)')
                    if cost then
                        self.info.indent=nil
                        self.info.cost,self.info.card=math.round(tonumber(cost),3),math.round(tonumber(card),3)
                        self.info.degree=get_dop(line,self.info.degree)
                        if self.tmp_info and self.tmp_info.cost and self.info.cost>self.tmp_info.cost then
                            self.tmp_link[self.tmp_alias]=self.tmp_info
                            if self.info.bsi and self.tmp_info.bsi and self.info.bsi.end_line==self.tmp_info.bsi.end_line then
                                self.info=self.tmp_info
                            end
                        end
                    end
                end
            elseif line:match('^ *[%*=]+$') or line:find('^Access path analysis') or line:find('^Join order') then
                self.info[self.type].end_line=lineno-1
                return false
            --elseif self.type=='bsi' and line=='' then
            --    self.info[self.type].end_line=lineno-1
            --    return false
            end
        end,

        end_parse=function(self,line,lineno)
            self.root.current_tb,self.root.current_alias=nil
            self.tmp_info,self.tmp_link,self.tmp_alias=nil
            if self.info and not self.info[self.type].end_line then
                self.info[self.type].end_line=lineno-1
            end
        end,

        extract={
            --[[--
                When table_name is not specified, then display the list of tables
                When table_name is specified then display all detailed lines of BSI/STA
                When table_name and qb is specified then display the detailed lines of BSI/STA for the specific QB
            --]]--
            help="|@@NAME [<table_name>] [<qb_name>]| Show single table stats and access paths. |",
            call=function(this,data,tab,qb)
                if tab then 
                    tab=tab:upper()
                    if any[tab] then tab='' end
                end
                if qb then 
                    qb=qb:upper()
                    if any[qb] then qb=nil end
                end
                local root,rows=data.root,{}
                local plan,found=root.plan and root.plan.qbs or {}
                --Dict tree: table => qb => alias => detailed map
                for t,v in pairs(data) do
                    if t~='root' and type(v)=='table' then
                        for q,o in pairs(v) do
                            if type(o)=='table' then
                                for alias,p in pairs(o) do
                                    if (not tab or tab==alias or tab==t or tab=='') and (not qb  or q==qb or any[qb]) then
                                        local lines={}
                                        if p.bsi then lines[#lines+1]=p.bsi end
                                        if p.sta then lines[#lines+1]=p.sta end
                                        --if QB is in the execution plan lines, then mark it as blue
                                        local f=plan[q:upper()]
                                        if f then found=f end
                                        rows[#rows+1]={p.name,alias==t and '' or alias,
                                                       (f and '$HIB$' or '')..q..(f and '$NOR$' or ''),
                                                       lines[1].start_line,lines[#lines].end_line,
                                                       p.bsi_seens or 0,p.sta_seens or 0,
                                                       p.best_sta or '',
                                                       p.card or '',
                                                       p.degree or '',
                                                       p.spd or '',
                                                       p.qb_perms ,
                                                       p.best_jo or '',
                                                       p.jo or '',
                                                       p.jo_card or '',
                                                       p.jo_spd,
                                                       root.qbs[q].seq*1e9+lines[1].start_line,
                                                       lines}
                                    end
                                end
                            end
                        end
                    end
                end

                if not tab then
                    --order by qb sequence
                    table.sort(rows,function(a,b) return a[#a-1]<b[#b-1] end)
                    table.insert(rows,1,{"Table Name",'Alias','Query|Block','Start|Line','End|Line','BSI|Scans','STA|Scans','STA|Best','STA|Card','STA|DoP','STA|SPD','Join|Orders','Best|JO#','Join|Method',"Join|Card",'JO|SPD'})
                    env.grid.print(rows)
                    local msg='* BSI: BASE STATISTICAL INFORMATION / STA: SINGLE TABLE ACCESS PATH / TB: Table / JO: Join Order'
                    print(('-'):rep(#msg)..'\n'..msg)
                    if found then print('* The query block in $HIB$blue$NOR$ means it exists in the exeuction plan.') end
                    return
                end

                env.checkerr(#rows>0,'Invalid table name or query block name.')
                table.sort(rows,function(a,b) return a[4]<b[4] end)

                root.print_start('tb_'..tab..(qb and ('_'..qb) or ''))
                local w=root.width
                for i,qb in ipairs(rows) do
                    qb[3]=qb[3]:strip_ansi()
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

local function find_tb(root,qb,t)
    local tab,alias=t:match('^(.-)%[(.-)%]')
    if tab then
        tab,alias=tab:upper(),alias:upper()
        local tb=root.tb
        return tb and tb[tab] and tb[tab][qb] and tb[tab][qb][alias] or {sta={}}
    end
    return {sta={}}
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
            local jo=self.curr_jo
            if not jo then return end
            --each time a line is chosen, also record the range end line for JO/table
            jo.end_line,self.last_indent=lineno,level
            jo.lines[lineno]=level
            if self.curr_tab_index then
                jo.tlines[self.curr_tab_index][2]=lineno
            end
            table.clear(self.stack)
        end,

        parse=function(self,line,lineno,full_line)
            if not self.stack then self.stack={} end
            if not self.data.tree then self.data.tree={} end
            if not self.cost then self.cost=0 end
            local root=self.root
            if line:match('^kkoqbc: finish optimizing query block') then
                local qb=self.data[self.qb]
                qb.end_line=lineno
                qb.perms_all[#qb.perms_all].end_line=lineno
                return false
            elseif lineno==self.start_line then
                self.qb=self.root.current_qb:upper()
                if not self.data[self.qb] then 
                    self.data[self.qb]={perms_all={},trees={}}
                end
                local cnt=#self.data[self.qb].perms_all+1
                self.data[self.qb].perms_all[cnt]={start_line=lineno}
                self.data[self.qb].trees[cnt]={}
                self.data[self.qb].perms=self.data[self.qb].perms_all[cnt]
                self.data[self.qb].start_line=lineno
                local qbs=self.root.qb
                if qbs and not qbs[self.qb] then qbs[self.qb]={} end
                qbs[self.qb].jo=self.data[self.qb]
                self.data.tree[self.qb]=self.data[self.qb].trees[cnt]
            end
            
            if line:find('^Join order%[') then
                --search join order number
                local perm=tonumber(line:match('^Join order%[(%d+)%]'))
                local tables=full_line:rtrim():match(': *(%S.-%S)$')
                if not tables then
                    self:end_parse()
                    return 
                end
                tables=tables:split('%s+')
                self.stack={}
                --Build join tree, it's necessary because multiple JOs could share the same part of the tree
                --For multiple JOs, the join information could appear only once for the same join part 
                self.tree_index={}
                local curr=self.data.tree[self.qb]
                local degree
                for k,v in ipairs(tables) do 
                    if not curr[v] then 
                        curr[v]={jos={},level=k}
                        local tb=find_tb(root,self.qb,v)
                        if k==1 then
                            --For the driving table, read info from BSI and STA because it has no join info
                            curr[v].lines={card=tb.card,cost=tb.cost,method=tb.best_sta,spd=tb.spd,degree=tb.degree}
                            local sta=tb.sta or tb.bsi
                            if sta then
                                curr[v].lines[1],curr[v].lines[2]=sta.start_line,sta.end_line
                            end
                        else
                            curr[v].lines={spd=tb.spd,degree=tb.degree}
                        end
                        if curr[v].lines.degree then
                            degree=math.max(degree or 1,curr[v].lines.degree)
                        end
                    end
                    curr=curr[v]
                    self.tree_index[tonumber(v:match('#(%d+)'))]=curr
                    curr.jos[#curr.jos+1]=perm
                end
                

                --build detailed map
                local jo={lines={},tables=tables,tlines={},jo=perm,start_line=lineno,cost=0,degree=degree}
                self.curr_jo=self.data[self.qb].perms[perm] or jo
                if not self.data[self.qb].perms[perm] then
                    self.data[self.qb].perms[perm]=jo
                end
                self.data[self.qb].perm_count=perm
                self.data[self.qb].perms.perm_count=perm
                --globally report current working JO
                root.current_jo=perm
                self:add(0,lineno)
            elseif lineno==self.start_line then
                return
            elseif line:find('^%*%*+ *%w+') then
                --Text start with: **** <text>
                self:add(0,lineno)
            elseif line:find('^Now joining:') then
                --Handle the joining table
                if not self.curr_jo then return end
                self.cost=0
                self.curr_tab_index=nil
                self.curr_table=line:match(': *(%S.-%S)$')
                --set working tree node
                self.curr_tree=self.data.tree[self.qb]
                --fine sequence of the table
                for i,t in ipairs(self.curr_jo.tables) do
                    --down the tree
                    self.curr_tree=self.curr_tree[t]
                    if t==self.curr_table then
                        --build table line info
                        self.curr_tab_index=i
                        local tline=self.curr_jo.tlines[i] or {lineno,lineno}
                        tline.spd=self.curr_tree.lines.spd
                        tline.jo=root.current_jo
                        self.curr_jo.tlines[i]=tline
                        --map line info to the tree
                        self.curr_tree.lines=tline
                        break
                    end
                end
                --globally report current working table
                root.current_tb,root.current_alias=self.curr_table
                self:add(1,lineno)
            elseif line:find('^%u%u+ Join') or line:find('^ +.- %u%u+ [cC]ost:') then
                --Handle NL/SM/HA Join and the cost
                self:add(2,lineno)
                local method,cost=line:match('(%u%u+) *[cC]ost: *([%d%.]+)')
                if cost and self.curr_tab_index then
                    cost=tonumber(cost)
                    if self.cost==0 or self.cost>cost then
                        self.cost,self.method,self.degree=cost,method,get_dop(line,self.degree)
                    end

                    local tb=self.curr_jo.tlines[self.curr_tab_index]
                    if tb then
                        tb.cost,tb.degree=self.cost,self.degree
                        tb.method=self.method..'(Aborted)'
                    end
                end
            elseif line:find('^ *Cost of predicates:') then
                --Show join predicates
                self:add(2,lineno)
                self.pred=line:match('^ *')
            elseif self.pred then
                --Also show join predicates child lines by indent
                if line:find('^'..self.pred..'%s+') then
                    self:add(2,lineno)
                else
                    self.pred=nil
                    self.last_indent=1
                end
            elseif line:find('Join Card.-Computed') then
                --extract table join level card
                local card=tonumber(line:match('Computed: *([%d%.]+)'))
                if card and self.curr_tab_index then
                    card=math.round(card,3)
                    self.curr_jo.tlines[self.curr_tab_index].card=card
                end
                self:add(3,lineno)
            elseif line:find('^Best:+') then
                --Handle table level best join
                if not self.curr_jo then return end
                self:add(2,lineno)
                self:add(2,lineno+1)
                local best=line:match('%S+$')
                self.curr_jo.tlines[self.curr_tab_index].method=best
                self.is_best=2
            elseif self.is_best==2 then
                if line:find('^ +') then
                    local cost,card=line:match('[cC]ost: *([%.%d]+).-[cC]ard: *([%.%d]+)')
                    if cost then
                        cost,card=tonumber(cost),math.round(tonumber(card),3)
                        local tb=self.curr_jo.tlines[self.curr_tab_index]
                        local degree=get_dop(line)
                        tb.card,tb.cost,tb.degree=card,cost,degree
                        self.curr_jo.degree=math.max(self.curr_jo.degree or 1,degree)
                    end
                end
                self.is_best=nil
            elseif line:find('^Join order aborted') or line:find('^Best so far') then
                --Hanle the end of JO level join
                if not self.curr_jo then return end
                self.curr_tab_index,self.curr_table,root.current_tb,root.current_alias=nil
                self:add(0,lineno)
                if line:find('^Join') then
                    --handle the aborted join
                    if self.curr_jo.cost==0 then
                        self.curr_jo.cost='> '..math.round(self.cost,3)
                    end
                    self.cost,self.card,self.degree=0,0
                    root.current_jo=nil
                else
                    --handle the complete join(currently best)
                    --extract table sequence/cost/card
                    if not self.tree_index then return end
                    local seq,cost,card=line:match('Table#: *(%d+).-[cC]ost: *([%.%d]+).-[cC]ard: *([%.%d]+)')
                    if cost then
                        self.cost,self.card=tonumber(cost),math.round(tonumber(card),3)
                        seq=tonumber(seq)
                        local tb=self.tree_index[seq].lines
                        tb.card,tb.cost=self.card,self.cost
                    end
                    --set the last cost/card as JO level cost/card
                    self.curr_jo.cost,self.curr_jo.card='= '..math.round(self.cost,3),self.card
                    self.is_best=1
                end
            elseif self.is_best==1 then
                --handle the child lines of the complete join(currently best)
                if line:find('^ +') then
                    self:add(0,lineno)
                    local seq,cost,card=line:match('Table#: *(%d+).-[cC]ost: *([%.%d]+).-[cC]ard: *([%.%d]+)')
                    if cost then
                        seq,self.cost,self.card=tonumber(seq),tonumber(cost),math.round(tonumber(card),3)
                        local tb=self.tree_index[seq].lines
                        self.curr_jo.cost,self.curr_jo.card='= '..math.round(self.cost,3),self.card
                        tb.card,tb.cost=self.card,self.cost
                    end
                else--housekeeping
                    self.is_best=0
                    self.cost,self.card,self.degree=0,0
                    root.current_jo=nil
                end
            elseif line:find('^%s+Best join order: *(%d+)$') then
                --Handle the best JO in QB level
                self.curr_tab_index,self.curr_table=nil
                local best=tonumber(line:match('%d+$'))
                local qb=self.data[self.qb]
                local perm=qb.perms[best]
                if not perm then return end
                qb.perm_best=best
                qb.cost,qb.card=math.round(tonumber(perm.cost:match('[%.%d]+'))),math.round(perm.card)
                qb.perms.perm_best,qb.perms.cost,qb.perms.card=qb.perm_best,qb.cost,qb.card
                local curr=self.data.tree[self.qb]
                for i,t in ipairs(perm.tables) do
                    --find the matched data of table STA/BSI and set the jo/spd/card/cost
                    local tab,alias=t:match('^(.-)%[(.-)%]')
                    curr=curr[t]
                    local curr_tb=find_tb(root,self.qb,t)
                    curr_tb.qb_perms,curr_tb.best_jo=(curr_tb.qb_perms or 0)+qb.perm_count,best
                    curr_tb.jo=curr.lines.method
                    curr_tb.jo_spd=curr.lines.spd
                    curr_tb.jo_card=curr.lines.card
                end
                self.is_best=3
            elseif self.is_best==3 then
                local cost,card=line:match('[cC]ost: *([%.%d]+).-[cC]ard: *([%.%d]+)')
                if cost then
                    local qb=self.data[self.qb]
                    local best=qb.perms[qb.perm_best]
                    if not best then return end
                    qb.perms.cost,qb.perms.card,qb.perms.degree=math.round(tonumber(cost),3),math.round(tonumber(card),3),get_dop(line)
                    best.degree=qb.perms.degree or best.degree
                end
                self.is_best=nil
            elseif (self.last_indent or 0) > 0 and (line:find(' +Cost:') or line:find('^%s+Index:')) then
                --Show more detail in each tables join method: NL/SM/HA
                local lv=#(line:match('^%s*'))
                local seq={}
                --also show the matched lines' parent lines by indent
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
                --Show SPD and dynamic sampling info
                local found,typ=line:match(': *(%u+), *estType *= *(%u+)')
                if found then
                    found=found..'('..typ..')'
                elseif line:find('DS_SVC',1,true) then
                    found='DS_SVC'
                else
                    found='DYN_SAMP'
                end

                --Bypass the SPD that started as 'NO' (NODIR/NOCTX/NOTQBCTX)
                if found:find('^NO') then return end
                if self.curr_tab_index then
                    self:add(2,lineno)
                    self.curr_jo.tlines[self.curr_tab_index].spd=found
                end
            elseif line~='' and not line:find('%*%*') and (self.last_indent or 0) > 0 then
                --record line stack by indent
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
            --[[--
                when no parameters then show the list of QBs
                when only qb is specified then show the list of join orders of that QB
                when jo is '-tree', then display all JOs for the specific QB in tree mode#1
                when jo is table name, then display the specific QB in tree mode#1 starts from the table
                when jo is table name and <table_name> is not nil, then display the specific QB in tree mode#2
                when jo is number, then display the brief join(remove some unimportant lines) info of the JO
                when qb/jo/tb is specify then display the detail lines of the table in the JO
            --]]--
            help="|@@NAME [<qb_name>[#<seq>] or *] [<JO#>\\|* [<table_name>]] \\| <table_name> \\| -tree| Show join orders, more details for more parameters |",
            call=function(this,data,qb,jo,tb)
                local rows,last={}
                local root,start_node=data.root

                local is_best_displayed
                local seq
                if qb and qb:find('#%d+$') then
                    qb,seq=qb:match('(.*)#(.*)')
                    seq=tonumber(seq)
                end

                if qb then qb=qb:upper() end

                local function show_tree(qb,best,t,node,sep,is_last,siblings,parent_best)
                    local jos,lines={},node.lines or {'',''}
                    --check if this node belongs to the best JO
                    local is_best
                    local fmt1=('$PROMPTCOLOR$%s$NOR$'):convert_ansi()
                    local fmt2='%s'
                    for k,v in ipairs(node.jos) do
                        if v==best then 
                            is_best=true
                            fmt2=fmt1
                            break
                        end
                    end

                    local fmt3=parent_best and not is_best_displayed and node.jos[#node.jos]<best and fmt1 or '%s'
                    --order the displayed child tables
                    for k,v in pairs(node) do
                        if type(v)=='table' and v.jos then
                            jos[#jos+1]={k,v}
                        end
                    end
                    table.sort(jos,function(a,b) return a[2].jos[1]<b[2].jos[1] end)

                    rows[1+#rows]={qb,
                                   --When current node has no child then show underline to separate each JO
                                   (#jos==0 and '$UDL$' or '')..(#jos<=1 and node.jos[1]==best and ' Y' or ''),
                                   sep~='' and node.jos[1] or '',
                                   lines[1],lines[2],
                                   math.round(lines.cost,3),
                                   lines.card,lines.degree or 1,lines.spd,lines.method,
                                   --highlight the best join chain
                                   (#jos==0 and '$NOR$ ' or ' ')..sep..(siblings>0 and ((is_best and fmt1 or fmt3):format(is_last and '!' or '|') or '')..fmt2:format('-') or '')..fmt2:format(t)}
                    if #jos==0 and is_best then is_best_displayed=true end
                    --Display all child nodes
                    for k,v in ipairs(jos) do
                        local sep1=sep..(is_last and ' ' or fmt3:format('|'))..(siblings>0 and '   ' or ' ')
                        show_tree(qb,best,v[1],v[2],sep1,k==#jos,#jos-1,is_best)
                    end
                end

                if tb then 
                    tb=tb:upper()..(tb:find('[',1,true) and '' or '[')
                elseif jo and not tonumber(jo) then
                    --when the jo parameter is table then display join orders in tree mode#1 
                    jo=jo:upper()..(jo:find('[',1,true) and '' or '[')
                    rows[1]={'Q.B','Best','Jo#','Start Line','End Line','Cost','Card','DoP','SPD','Method','Join Tree'}
                    local jos=data[qb]
                    env.checkerr(type(jos)=='table' and jos.trees,'No data found.')
                    local cn=#jos.trees

                    for i=1,cn do
                        if i>1 and not seq then
                            rows[#rows+1]={'=','=','','','','','','','','',''}
                        end

                        if not seq or seq==i then
                            is_best_displayed=nil
                            local tb_count={}
                            for t,o in pairs(jos.trees[i]) do
                                if type(o)=='table' and o.jos and (jo=='-TREE[' or (t:upper():find(jo,1,true)==1 or jo:find(t:upper(),1,true)==1)) then
                                    tb_count[#tb_count+1]={qb..(cn>1 and ('#'..i) or ''),t,o.jos[1],o}
                                end
                            end
                            table.sort(tb_count,function(a,b) return a[3]<b[3] end)
                            for k,v in ipairs(tb_count) do
                                show_tree(v[1],jos.perms_all[i].perm_best,v[2],v[4],'',k==#tb_count,#tb_count-1,false)
                            end
                        end
                    end
                    return env.grid.print(rows)
                end

                local fmt='%s=%s'
                local mode
                --Build join chains with <table_name> (<join_method>)
                local function get_chain(tree,perm)
                    local chain = {}
                    for c=1,#perm.tables do
                        local t=perm.tables[c]
                        if not tree[t] then return '' end
                        chain[c]=t..(tree[t].lines.method and ('('..tree[t].lines.method..')') or '')
                        tree=tree[t]
                    end
                    return table.concat(chain,' -> ')
                end
                
                --If the join information of a table is not recorded in current JO, then find it in other JOs by accessing the tree
                local plan,found=root.plan and root.plan.qbs or {}
                local extralines,eb,ee={}
                local function build_extra(qb,tree)
                    if not tree.lines[1] then return end
                    local pjo=qb.perms[tree.lines.jo]
                    local pieces=pjo and pjo.lines or nil
                    for p=tree.lines[1],tree.lines[2] do
                        if not pieces or pieces[p] then 
                            extralines[p]=not pieces and 0 or pieces[p]
                            eb=(not eb or eb>p) and p or eb
                            ee=(not ee or ee<p) and p or ee
                        end
                    end
                    return tree.lines.spd
                end

                for k,v in pairs(data) do
                    local cn=#(type(v)=='table' and v.perms_all or {})
                    if type(v)=='table' and v.perms_all and (not qb or qb==k or any[qb]) then
                        if not qb then
                            mode='qb'
                            for i,j in ipairs(v.perms_all) do
                                local best=j[j.perm_best]
                                local spd=root.spd and root.spd.qbs[k] or {count=0}
                                local f=plan[k:upper()]
                                --Highlight the QB that can be found in the execution plan
                                if f then found=f end
                                if best then
                                    rows[#rows+1]={(f and '$HIB$' or '')..k..(cn>1 and ('#'..i) or '')..(f and '$NOR$' or ''),
                                                    j.perm_count,j.perm_best,j.start_line,j.end_line,j.cost,j.card,best.degree or '',
                                                    spd.count>0 and 'EXISTS' or '',
                                                    get_chain(v.trees[i],best),
                                                    root.qbs[k].seq}
                                end
                            end
                        else
                            for c,piece in pairs(v.perms_all) do
                                if not seq or seq==c then for i,j in ipairs(piece) do
                                    local treemode=jo and (j.tables[1]:upper():find(jo,1,true)==1 or jo:find(j.tables[1]:upper(),1,true)==1)
                                    if not jo or jo==tostring(i) or any[jo] or treemode then
                                        local chain=table.concat(j.tables,' -> ')
                                        local tree=v.trees[c]
                                        local spd
                                        if not tb or treemode then --Display the list of JO, or the brief of a JO
                                            mode=treemode and 'tree' or 'jo'
                                            chain = {}
                                            for c=1,#j.tables do
                                                local t=j.tables[c]
                                                tree=tree[t]
                                                --fetch missing table join info from prev jo
                                                if (not j.tlines[c] and c>1) and jo and tree.lines then
                                                    --if no table join info, then get it from the tree
                                                    local tree_spd=build_extra(data[k],tree)
                                                    if tree_spd then spd=tree_spd end
                                                elseif j.tlines[c] and j.tlines[c].spd then
                                                    spd=j.tlines[c].spd
                                                end
                                                
                                                if treemode then
                                                    chain[c]={(' '):rep(c*2-2)..t.. ' $HIB$->$NOR$'}
                                                    for k,v in pairs(tree.lines) do
                                                        if type(v)~='table' and type(k)~='number' and k~='jo' then
                                                            chain[c][#chain[c]+1]=fmt:format(k,tostring(v))
                                                        end
                                                    end
                                                    chain[c]=table.concat(chain[c],'  ')
                                                else
                                                    chain[c]=t..(tree.lines.method and ('('..tree.lines.method..')') or '')
                                                end
                                            end
                                            rows[#rows+1]={k..(cn>1 and ('#'..c) or ''),i,piece.perm_best==i and 'Y' or '',j.start_line,j.end_line,j.cost,j.card,j.degree or '',spd,table.concat(chain,treemode and '\n' or ' -> '),j}
                                        else --Display the specific table join information
                                            mode='tb'
                                            for c,t in ipairs(j.tables) do
                                                tree=tree[t]
                                                t=t:upper()
                                                if (t:find(tb,1,true)==1 or tb:find(t,1,true)==1) then
                                                    local lines=j.tlines[c]
                                                    if not lines and not any[jo] then
                                                        --if no table join info, then get it from the tree
                                                        extralines,eb,ee={}
                                                        spd=build_extra(data[k],tree)
                                                        lines={eb,ee}
                                                    elseif lines then
                                                        spd=lines.spd
                                                    end

                                                    if lines then
                                                        rows[#rows+1]={k,i,piece.perm_best==i and 'Y' or '',lines[1],lines[2],j.cost,j.card,j.degree or '',spd or '',chain,j}
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end end
                            end
                        end
                    end
                end

                --read lines from other JOs
                local extras={}
                if eb then
                    for line,lineno in root.range(eb,ee) do
                        if extralines[lineno] then
                            extras[#extras+1]={lineno,line,extralines[lineno]}
                        end
                    end
                end


                if mode=='qb' then
                    table.sort(rows,function(a,b) if a[#a]==b[#b] then return a[4]<b[4] else return a[#a]<b[#b] end end)
                    table.insert(rows,1,{'QB Name','JOs','Best JO#','Start Line','End Line','Cost','Card','DoP','SPD','Join Chain'})
                    env.grid.print(rows)
                    if found then
                        print(('-'):rep(65))
                        print('* The query block in $HIB$blue$NOR$ means it exists in the exeuction plan.')
                    end
                else
                    local size=#rows
                    env.checkerr(size>0,'Please input the valid QB name / JO# / table name.')
                    if  mode=='tree' or (mode=='jo' and size>1) then --list jo
                        table.insert(rows,1,{'QB Name','JO#','Best','Start Line','End Line','Cost','Card','DoP','JO SPD','Join Chain'})
                        env.grid.sort(rows,4,true)
                        if mode=='tree' then env.set.set('rowsep','-') end
                        env.grid.print(rows)
                        if mode=='tree' then env.set.set('rowsep','back') end
                    elseif qb and size==1 and not jo then --display all QB details if only has one JO and jo# is not specified
                        root.print_start('jo_'..qb)
                        qb=data[rows[1][1]:gsub('#%d+$','')]
                        for line,lineno in root.range(qb.start_line,qb.end_line) do
                            root.print(lineno,line)
                        end
                        root.print_end()
                    else --display the detail lines for jo/tb mode
                        root.print_start('jo_'..qb..(tonumber(jo) and ('_'..jo) or '')..(tb  and ('_'..tb:sub(1,-2)) or ''))
                        local fmt,prev='Query Block %s    Join Order #%d'
                        local w=root.width

                        for i,j in ipairs(rows) do
                            local pieces=j[#j].lines
                            local curr=fmt:format(j[1],j[2]):strip_ansi()
                            local counter,numsep,linesep=0
                            --Display header of QB+JO
                            if curr~=prev then
                                prev=curr
                                local width=#curr+4
                                root.print(("="):rep(w),("="):rep(width))
                                root.print(("/"):rep(w),'|$HEADCOLOR$ '..curr..' $NOR$|')
                                root.print(("="):rep(w),("="):rep(width))
                            end

                            local function print_line(lineno,line,indent)
                                local sep=(' '):rep(indent*2)
                                counter=counter+1
                                --for each "Now Joining", add an extra line to separate
                                if counter>1 and indent==1 then
                                    numsep,linesep=(' '):rep(w),sep..(('-'):rep(80))
                                    root.print(numsep,linesep)
                                elseif indent==0 and numsep then
                                    root.print(numsep,linesep)
                                    numsep,linesep=nil
                                end
                                root.print(lineno,sep..line)
                            end

                            for line,lineno in root.range(j[4],j[5]) do
                                if tb and size==1 then
                                    root.print(lineno,line)
                                elseif pieces[lineno] then
                                    print_line(lineno,line,pieces[lineno])
                                    if extras then --fill missing join info
                                        for c,l in ipairs(extras) do
                                            print_line(l[1],l[2],l[3])
                                        end
                                        extras=nil
                                    end
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
            call=function(this,data,qb)
                local root,text=data.root,{}
                if not qb then
                    for line in root.range(data.last_start_line+1,data.last_end_line) do
                        text[#text+1]=line
                    end
                    text=table.concat(text,'\n')
                    print(text)
                    print('\n'.. string.rep('=',30)..'\nSource SQL ID: '..root.sql_id)
                    print('\nResult saved to '..env.write_cache(root.prefix..'.sql',text))
                else
                    local q=root.qbs[qb:upper()]
                    env.checkerr(q and q.sql,"Cannot find unparsed SQL text for query block: "..qb)
                    local prev_sql
                    text=nil
                    for i,lineno in ipairs(q.sql) do
                        for line,ln in root.range(lineno,root.end_line) do
                            if ln==lineno and #line>10 and line:find('^ *[%*]+ *$') then
                                text={}
                            elseif ln>lineno then
                                if type(text)~='table' then
                                    break
                                elseif line:find('^[%-]+$') and #line>10 then
                                    print('Line # '..lineno..':\n===============')
                                    text=table.concat(text,'\n')
                                    print(text..'\n')
                                    break
                                else
                                    text[#text+1]=line
                                end
                            elseif line~=prev_sql then
                                text=line
                                prev_sql=line
                                print('Line # '..lineno..':\n===============')
                                print(line..'\n')
                                break
                            end
                        end
                    end
                    print('Result saved to '..env.write_cache(root.prefix..'_'..qb:gsub('[$@]','_')..'.sql',text))
                end
            end
        }
    }
end

local spd_patterns={'dirid *= *%d+','^SPD','%* *DS_SVC *%*','%* *OPT_DYN_SAMP *%*'}
local function extract_spd()
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
            --Bypass NODIR/NOQBCTX/NOCTX
            if line:find('NODIR') or line:find('NOQBCTX') or line:find('NOCTX') then
                return false
            --Handle the SPD info in QB/Statement level
            elseif line:find('^SPD: *BEGIN') then
                qb=line:find(' statement ') and 'STATEMENT' or qb
                self.data.in_spd=qb
                self.data.has_spd=false
                q=self.data.qbs[qb]
                if not q then
                    q={qb=qb,lineno-1,links={},has_spd=false,count=0}
                    self.data.qbs[qb]=q
                else
                    q[3]=q[1]
                    q[1]=lineno-1
                end
                return true
            elseif line:find('^SPD: *END') then
                q=self.data.qbs[self.data.in_spd]
                if self.data.has_spd then
                    q[2]=lineno+1
                elseif q.has_spd then
                    q[1]=q[3]
                else--if no SPD id in the scope, then remove it
                    q[1]=nil
                end
                self.data.in_spd=nil
                self.data.has_spd=false
                return false
            else--search SPD id
                local dirid=line:match('dirid *= *(%d+)')
                --for QB/Stmt level SPD, mark it as has SPD
                if self.data.in_spd then
                    if dirid then
                        q=self.data.qbs[self.data.in_spd]
                        self.data.has_spd=true
                        q.has_spd=true
                        q[dirid]=lineno
                    end
                else--For join/table level
                    local obj={qb=qb,tb=root.current_tb,jo=root.current_jo,alias=root.current_alias}
                    if not q then
                        q={qb=qb,lineno-1,links={},has_spd=false,count=0}
                        self.data.qbs[qb]=q
                    end
                    q.count=lineno
                    q.links[lineno]=obj
                end
                return self.data.in_spd~=nil
            end
            return false
        end,

        extract={
            help=[[|@@NAME [<qb_name>]|Show SQL Plan Directive or Dynamic Sampling information|]],
            call=function(this,data,qb_name)
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

                    --print header for each QB
                    root.print(("="):rep(w),("="):rep(width))
                    root.print(("/"):rep(w),'|$HEADCOLOR$ '..(qb.qb=='STATEMENT' and ' TOP LEVEL: ' or 'Query Block ')..qb.qb..' $NOR$|')
                    root.print(("="):rep(w),("="):rep(width))
                    --for QB/stmt level SPD, print all lines
                    if qb[2] then
                        for line,lineno in root.range(qb[1],qb[2]) do
                            root.print(lineno,line)
                        end
                    end

                    local lines={}
                    w=0
                    --For JO/Table level, only display the matched line + relative JO#/Table
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


function parser:build_probes()
    self.probes={
        plan=extract_plan(),
        qb=extract_qb(),
        qbs=extract_qbs(),
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
                call=self.pattern_search
            }
        },

        optenv={
            start=function(line,root) return root.plan and line:find("^Optimizer state dump:") end,
            parse=function(self,line,lineno) end,
            extract={
                help="|@@NAME [<keyword>] | Show optimizer environment |",
                call=self.pattern_search
            }
        },

        fixctl={
            start=function(line,root) return root.optenv and line:find("^Bug Fix Control Environment") end,
            extract={
                help="|@@NAME [<keyword>] | Show bug fix control environment |",
                call=self.pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^([%*=])%1%1$') then return false end
            end
        },

        stats={
            start="SYSTEM STATISTICS INFORMATION",
            extract={
                help="|@@NAME | Show system statistics information |",
                call=self.pattern_search
            },
            parse=function(self,line,lineno)
                if line:find('^*************************') then return false end
            end
        },
        abbr={
            start='The following abbreviations are used by optimizer trace',
            extract={
                help="|@@NAME [<keyword>] | Show abbreviations |",
                call=function(this,data,keyword) this:pattern_search(data,keyword,data.extras) end
            },
            parse=function(self,line,lineno)
                if line:find('^%*%*%*') or line=='' then return false end
                if not self.data.extras then
                    self.data.extras={
                    'CNT: count(col) to count(*) transformation',
                    'EQUIV: Equivalence Check',
                    'DCL: De-Correlated lateral view(or ansi join) into inline view',
                    'DE:  Distinct elimination',
                    'DAT: distinct aggregate transform?',
                    'DIS: distinct (similar to group by placement)',
                    'DTP: distinct placement',
                    'BJ:  Bushy join',
                    'OBYE: order by elimination',
                    'JE:  Join Elimination',
                    'JF:  Join Factorization',
                    'OJE: Outer Join Elimination',
                    'FPD: Filter Push Down',
                    'FOJ: Full Outer Join',
                    'GBP: Group By Placement',
                    'GBC: group by placement',
                    'GBF: group by placement',
                    'GBR: group by placement',
                    'CSE: Common Subexpression Elimination',
                    'PJE: Partial Join Evaluation(PARTIAL_JOIN Hint)',
                    'TE:  Table Expansion',
                    'NSO: Unnesting "IN" subquery',
                    'NSQ: a variation on "IN" subqueries',
                    'SJC: SET_TO_JOIN for MINUS/INTERSECT (parameter _convert_set_to_join )',
                    'SLP: select list pruning',
                    'SPJ: Select-Project-Join View Merging',
                    'SQ: Unnesting - possibly specific to correlated subqueries',
                    'SSQ: Scalar subquery',
                    'SQT: Statistic-based Query Transformation',
                    'SU: Subquery Unnesting',
                    'VT: Vector Transformation',
                    'WIF: Analytic functions (especially those generated by "remove aggregate subquery")',
                    'NWVW: projection view,related to complex view merging with distinct/group',
                    'COL: Naming convention (somtimes) for columns used in generated views',
                    'DAG: Distinct aggregatation transform',
                    'PM: predicate move-around',
                    'LAT: Lateral View'}
                end
            end
        },
        alter={
            start='PARAMETERS WITH ALTERED VALUES',
            extract={
                help="|@@NAME [<keyword>] | Show altered parameters |",
                call=self.pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^[%*=]+$') then return false end
            end
        },

        param={
            start='PARAMETERS WITH DEFAULT VALUES',
            extract={
                help="|@@NAME [<keyword>] | Show default parameters |",
                call=self.pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^[%*=]+$') then return false end
            end
        },

        optparam={
            start='PARAMETERS IN OPT_PARAM HINT',
            extract={
                help="|@@NAME [<keyword>] | Show parameters changed by opt_param hint|",
                call=self.pattern_search
            },
            parse=function(self,line,lineno)
                if line=='' or line:find('^[%*=]+$')then return false end
            end
        }
    }
    extract_plan,extract_qb,extract_tb,extract_sql,extract_jo,extract_timer,extract_spd,extract_qbs=nil
end

local filelist={}

function parser:check_file(f,path,seq)
    local ary,lineno=filelist[path]
    local q,o,s='Registered qb: [A-Z]+$1 ','End of Optimizer State Dump','Current SQL Statement for this session'
    if not ary then
        local st,ed,sql_id,offset,prev
        local q1,o1,sql_id='^'..q,'^'..o
        ary={}
        filelist[path]=ary
        lineno=0
        for line in f:lines() do
            lineno=lineno+1
            line=line:sub(1,256)
            if not (st or ed) and line:match(q1) then
                st=lineno
                offset=f:seek()-prev-1
            elseif st and not ed then
                if not sql_id and line:find(s) then
                    sql_id=line:match('sql_id=(%w+)')
                elseif sql_id and line:match(o1) then
                    ed=lineno
                    ary[#ary+1]={st,ed,sql_id,offset}
                    st,ed,sql_id=nil
                end
            end
            if not st then prev=#line end
        end
    end

    if #ary==1 or (seq and ary[seq]) then
        if lineno then f:seek('set',ary[4]) end
        local st,ed,sql_id=table.unpack(ary[seq or 1])
        if st>1 then
            lineno=1
            for line in f:lines() do
                lineno=lineno+1
                if lineno>=st then break end
            end
        end
        return st,ed,'SQL Id: '..sql_id
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

    local rows={{'Seq','Start Line','End Line','Offset','SQL Id'}}
   
    for k,v in ipairs(ary) do
        rows[k+1]={k,v[1],v[2],v[4],v[3]}
    end
    print('Mutiple SQL traces are found:')
    env.grid.print(rows)
    print('\n')
    env.raise('Please open the file plus the specific seq among above list!')
end

return parser.new()