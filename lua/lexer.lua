local env=env
local table,math,pairs,type,print,ipairs,io=table,math,pairs,type,print,ipairs,io
local lexer=env.class()


function lexer:ctor()
    self.probes,self.data={},{open={},close={}}
    self.name='lexer'
end

function lexer:run_command(cmd,...)
    env.checkhelp(cmd)
    cmd=tostring(cmd):lower()
    local func,data=self.cmds[cmd],self.data[cmd] or {root=self.data}
    env.checkerr(func,"No such command: %s",cmd)
    env.checkerr(cmd=='open' or cmd=='close' or self.data.file,"Please open a valid "..self.name.." trace file firstly.")
    func(self,data,...)
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
function lexer:build_probes()
end

function lexer:check_file(handler,file,seq)
end

function lexer.pattern_search(this,data,keyword,extras)
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
    if type(extras)=='table' then
        for k,line in ipairs(extras) do
            if not keyword or line:sub(1,256):rtrim():lower():find(keyword) then
                root.print('9999',line)
            end
        end
    end
    return root.print_end(true)
end


function lexer:read(data,file,seq)
    env.checkerr(file,'Please specify the input file path.')
    local f=io.open(file,'rb')
    env.checkerr(f,"Unable to open file: %s",file)
    
    local start_line,end_line,target=self:check_file(f,file,tonumber(seq))
    if not start_line then
        start_line,end_line=1,1e8
    end
    local short_name=file:match('([^\\/]+)$')
    local lines,data={}
    local curr_probe
    local lineno,offset,prev_offset,sizel,curr,sub,full_line=start_line-1,0,0

    self:close()
    local root=self.data
    root.file,root.handler,root.start_line,root.end_line=file,f,start_line,end_line
    root.prefix=short_name:match('^[^%.]+')
    root.seeks=table.new(8192,8)

    local probes,finds,priors={},{},self.priors

    --call probe.end_parse
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
    --call probe.parse
    local function parse(name)
        local probe=probes[name]
        if not probe then return end
        if not probe.parse then
            probe.data.last_end_line,probe.data.last_end_offset=probe.data.last_start_line,offset
            probes[name]=nil
            return
        end
        local res=probe:parse(curr,lineno,full_line)
        --when the function return false then end the probe
        if res==false then return end_parse(name) end
    end

    local function _exec(name,p,e,c)
        if c and probes[name].breakable==false then return end
        if c or p then parse(name) end
        if c or e~=nil then end_parse(name,c) end
    end

    local function execute(p,e,c)
        for i,h in ipairs(priors) do
            --call all active probes with the order of prorities
            if probes[h.name] then
                _exec(h.name,p,e,c)
                if h.exclusive then p=nil end
            end
        end
    end

    local counter,batch_size=0,math.max(4,math.ceil((end_line-start_line+1)/8192))
    local clock=os.timer()
    local fmod,floor=math.fmod,math.floor
    print('Analyzing the trace file'..(target and (' for '..target) or '')..' ...')
    root.seeks[0]=f:seek()
    offset=root.seeks[0]
    for line in f:lines() do
        offset=offset+#line+1
        counter=counter+1
        full_line,curr=line,line:sub(1,256):rtrim()
        lineno,sub=lineno+1,curr:ltrim()
        --record the offset for each batch_size lines in order to fastly seek the position
        if fmod(counter+1,batch_size)==1 then 
            root.seeks[floor(counter/batch_size)]=offset
        end
        for i,n in ipairs(priors) do
            local k,v=n.name,n.probe
            local p=probes[k]
            --if the high prior probe is active, then skip all following probes 
            if p and p.exclusive then
                break
            elseif v.start and not finds[k] and not p then
                local found=false
                --call the start function/string
                if type(v.start)=="string" then
                    found=sub:find(v.start,1,true)
                else
                    found=v.start(sub,root,lineno,full_line)
                end
                --if the probe's start string/function match the line, then activate the probe
                if found==1 or found==true then
                    if v.closeable~=false then 
                        execute(true,false,v.parse and k) 
                    end
                    data=root[k] or {}
                    data.root,root[k]=root,data
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
    root.end_line,end_line=lineno,lineno

    execute(false,true,'EOF')
    f:close()

    local options={}
    for k,v in pairs(root) do
        if self.probes[k] and self.probes[k].extract then
            options[#options+1]=k
        end
    end
    table.sort(options)
    
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
        local sep=""
        if lineno>0 then
            sep=('-'):rep(width)
            print(sep)
        end
        if file then 
            stack[#stack+1]=sep
            file=file:gsub('[$@/\\%*%?<>]','_'):lower()
            print("Result saved as",env.write_cache(root.prefix..'_'..file..'.txt',table.concat(stack,'\n'):strip_ansi()))
        end
        if feed then print(lineno,'lines matched.') end
    end

    root.seek=function(lineno)
        local root=self.data
        env.checkerr(root.file,"Please open the "..self.name.." trace file firstly.")
        local f=root.handler
        if io.type(f)~='file' then
            root.handler=nil
            f=io.open(root.file,'rb')
            if not f then
                root.file=nil
                env.raise("Unable to open file: %s",root.file)
            end
        end
        local c=floor((lineno-root.start_line)/batch_size)
        f:seek('set',root.seeks[c])
        --f:seek('set',0)
        local curr=c*batch_size+root.start_line
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
            return f:read('*l'):rtrim(),lineno
        end
        return next
    end

    root.line=function(lineno)
        env.checkerr(lineno,'Invalid lineno')
        lineno=math.min(root.end_line,math.max(root.start_line,lineno))
        local f=root.seek(lineno)
        return f:read('*l'):rtrim()
    end
    
    for i,h in ipairs(priors) do
        if h.probe.on_finish then
            h.probe.on_finish(h.probe,root[h.name])
        end
    end
    print('\n'..(end_line-start_line+1)..' lines processed in '..math.round(os.timer()-clock,3)..' secs. Following commands are available: '..table.concat(options,','))
end

function lexer:close()
    if not self.data.file then return end
    if io.type(self.data.handler)=='file' then 
        pcall(self.data.handler.close,self.data.handler)
    end
    self.data,self.data.file,self.data.handler={}
end


function lexer:__onload()
    if not self.probes then self.probes={} end
    self:build_probes()
    self.cmds={
        open=self.read,
        close=self.close,
    }
    local help={[[Analyze :name trace file. type 'help @@NAME' for more detail.
[| grid:{topic='List of :name Commands'}
         | Command | Description |
         | open <file path> [<seq>] | Attach to an :name trace file, this is the pre-action of other operations|
         | close | Dettach from the opened trace file |
         | - | - |]]}
    help[1]=help[1]:gsub(':name',self.name)
    local subs,priors={},{}
    local width=0
    self.probes.lines=self.lines
    for k,v in pairs(self.probes) do
        priors[#priors+1]={name=k,prior=v.priority or v.exclusive and 100 or 1000,exclusive=v.exclusive,probe=v}
        if v.extract then
            self.cmds[k]=v.extract.call
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
    self.priors=priors
    help=table.concat(help,'\n'):gsub('\n%s*|%s*([^%s|]+)%s*',function(s) return width:format(s) end)..']'

    env.set_command(self,self.name,help,self.run_command,false,5)
end

function lexer:__onunload()
    self:close()
end

lexer.lines={
    start='-',
    breakable=false,
    extract={
        --[[--
            1) if only begin lineno is specified then display all nearby lines, and highlight this line
            2) if either begin/end lineno is specified then print the line range
            3) if begin/end lineno is not a number, then fuzzy search and display all matched lines
                   * b or p: previous page based on 1)
                   * f or n: next page based on 1)
        --]]--
        help="|@@NAME {<start_line> [<end_line>]}$COMMANDCOLOR$ \\| p \\| n \\| $NOR$<keyword> | Show matched lines with the specific line range or keyword(supports wildchar '%') |",
        call=function(this,data,b,e,...)
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
                b=table.concat({b,e,...},'%'):lower()
                env.checkerr(#b>2,'Target search string must not be less than 3 chars.')
                local fuzzy=b:find('%',1,true) and not e and '%W' or ''
                keyword=fuzzy..b:gsub('%%','\1\2\3'):escape():gsub('\1\2\3','.-')..fuzzy
                b,e=root.start_line,root.end_line
            else
                b,e=st,ed
                env.checkerr(b>0,"Please input the start line number.")
                env.checkerr(not e or e>=b, "<end_line> must not be smaller than <start_line>.")
                if not e then
                    data.l=b
                    b=math.max(1,math.floor(b-h/2))
                    e=b+h
                end
                data.b,data.e=b,e
            end

            root.print_start()
            for line,lineno in root.range(b,e) do
                if not keyword or prev~=line and (' '..line:sub(1,256)..' '):lower():match(keyword) then
                    root.print(lineno,lineno==data.l and ('$COMMANDCOLOR$'..line..'$NOR$') or line)
                    --if keyword then prev=line end
                end
            end
            root.print_end(true)
        end
    }
}
lexer.finalize='N/A'
return lexer