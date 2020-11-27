local env,java=env,java
local runtime=java.require("java.lang.Runtime",true):getRuntime()
local helper={}

function helper.jvm()
    local grid=env.grid
    local set=env.set
    local rows={{},{}}
    local function add(name,value)
        local siz=#rows[1]+1
        rows[1][siz],rows[2][siz]=name,value
    end
    local keys={}
    for k,v in java.pairs(java.system:getProperties()) do
        if tostring(k)~="" then
            local n=1
            if type(v)=="string" then
                v,n=v:trim():gsub('(['..(env.IS_WINDOWS and ';' or ':')..'])','%1\n')
            else
                v=tostring(v)
            end
            keys[#keys+1]={k,v,n}
        end
    end
    table.sort(keys,function(a,b)
        if a[3]~=b[3] then 
            return a[3]<b[3]
        else
            return a[1]<b[1]
        end
    end)

    local cnt=0
    for k,v in ipairs(keys) do
        cnt=cnt+1
        add(v[1],v[2])
        if v[3]==1 and math.fmod(cnt,2)==1 and keys[k+1] and keys[k+1][3]>2 then
            cnt=cnt+1
            add("","")
        end
    end
    print("JVM System Properties:\n======================")
    set.set("PIVOTSORT","off")
    set.set("PIVOT",1)
    grid.print(rows)
    print("\nJVM Security Providers:\n=======================")
    rows={{"Name","Info"}}
    for k,v in java.pairs(console:getSecurityProviders()) do
        rows[#rows+1]={k,v}
    end
    table.sort(rows,function(a,b) return a[1]:lower()<b[1]:lower() end)
    grid.print(rows)
end

function helper.env(target,depth)
    if target and target:sub(1,1)~='-' and target:sub(1,1)~='+' then
        if type(_G[target])=="table" then
            return print(table.dump(_G[target],nil,depth))
        end
        if target:find("%.") then
            local obj=_G
            for v in target:gmatch('([^%.]+)') do
                if type(obj)~="table" then return end
                obj=obj[v]
                if not obj then return end
            end
            return print(table.dump(obj,nil,depth))
        end
        return
    end
    local grid=env.grid
    local set=env.set
    local rows={{},{}}
    local function add(name,value)
        if target then
            local ind,pat=target:sub(1,1),target:sub(2)
            local mat = tostring(value):match(pat) and true or false
            if mat~=(ind=='+' and true or false) then
                return
            end
        end
        local siz=#rows[1]+1
        rows[1][siz],rows[2][siz]=name,value
    end
    local e=terminal.encoding(terminal)
    
    
    add("Memory.LUA(KB)",math.floor(collectgarbage("count")))
    add("Memory.JVM(KB)",math.floor((runtime:totalMemory()-runtime:freeMemory())/1024))
    if rows[2][1] and rows[2][2] then
        add("Memory.Total(KB)",rows[2][1]+rows[2][2])
    end
    add("CodePoint",e)
    add("ENV.locale",os.setlocale())
    local prefix=env.WORK_DIR:len()+1
    for k,v in pairs(env) do
        --if not (k=='_G' or k=='_ENV' or k=='env') then
        if type(v)=="table" and type(v.props)=="table" then
            for i,j in pairs(v.props) do
                add(k.."."..i,j)
            end
        end
        local t=type(v)
        if t=="function" then
            v=string.from(v)
        elseif t=="table" and k~='env' and k~='_G' and k~='package' and k~='_ENV' then
            t=table.dump(v,nil,2):match('function(%([^%)]+%))')
            v= t and 'table'..t or tostring(v,'',3)
        elseif t=="string" then
            v='"'..v..'"'
        end
        add('env.'..k,v)
    end
    if math.fmod(#rows[1],2)==1 then
        add("","")
    end
    add('package.path',package.path:gsub(';',';\n'))
    add('package.cpath',package.cpath:gsub(';',';\n'))
    set.set("PIVOT",1)
    grid.print(rows)
end

function helper.colorful(helps,target)
    if helps:find('^[Nn]o ') then return helps end
    target=target:gsub(',.+','')
    helps='\n'..(helps:gsub('^%s*\n',''):gsub('\t','    '))
    local spaces=helps:match("\n( +)%S") or ""
    helps=helps:gsub("\r?\n"..spaces,"\n"):gsub("%s+$",""):sub(2)

    helps=helps:gsub('^(%s*[^\n\r]+)[Uu]sage[: ]+(@@NAME)([^\r\n]*)',function(prefix,name,line)
        local s=prefix..'\n'..string.rep('=',#(prefix:trim())+#target+2)..'\n$USAGECOLOR$Usage:$COMMANDCOLOR$ '..name:gsub(',.+','')..'$NOR$'
        return s..line:gsub('([<>{}%[%]|]+)','$COMMANDCOLOR$%1$NOR$'):gsub('(%-%w+)','$PROMPTSUBCOLOR$%1$NOR$')
    end)
 
    helps=(target=='' and '' or ('$USAGECOLOR$'..target:upper()..':$NOR$ '))..helps
    helps=helps:gsub("@@NAME",target:lower())

    local grid=env.grid
    local is_table
    helps=helps:gsub('%[(%s*|.-|)%s*%]',function(s)
        local tab,s0=grid.new(),s..' '
        local space=s:match('( *)|') or ''
        local _,cfg=grid.get_config(s0)
        local cols=0
        s0:gsub('\\|','\1'):gsub('[^\n%S]*(|[^\r\n]+|)%s+',function(s1)
            local row={}
            s1:gsub('([^|]+)',function(s2)
                row[#row+1]=s2:trim():gsub('\\n','\n '):gsub('\\%]',']'):gsub('\1','|')
                if #row==1 and #tab.data>0 then 
                    row[1]=row[1]=='-' and '-' or ('$BOLD$'..row[1]..' $NOR$') 
                elseif #tab.data>0 and row[1]~='-' and #row>1 then
                    row[#row]=row[#row]:gsub('[<>%+%-%*/%[%]\'"%%]+','$USAGECOLOR$%1$NOR$')
                end
                row[#row]=row[#row]=='-' and '-' or (' '..row[#row])
            end)
            if #row > 1 then
                if cols==0 then 
                    cols=#row
                    if cols==2 then table.insert(row,2,':') end
                elseif cols==2 then
                    table.insert(row,2,':')
                end
                tab:add(row) 
            end
        end)
        if #tab.data==0 then return s end
        for k,v in pairs(cfg) do tab[k]=v end
        is_table=true
        return space..table.concat(grid.merge({tab}),'\n'..space)
    end)

    local keys={
        ('Example'):case_insensitive_pattern(),
        ('Option'):case_insensitive_pattern(),
        ('Parameter'):case_insensitive_pattern(),
        ('Output'):case_insensitive_pattern()
    }
    local fmt='%s%s%s$NOR$%s'
    helps=helps:gsub('(\n[^%S\n\r]*)([%-<]?[ %w#%-<_]+>?)( *:)',function(prefix,s,comma)
        local s1,c=s:trim():gsub(' ','')
        if c>1 then return prefix..s..comma end
        c=0
        for _,k in ipairs(keys) do
            if s:match('.*'..k..'[sS]?') then return fmt:format(prefix,'$USAGECOLOR$',s,comma) end
        end
        return fmt:format(prefix,(s:find('-',1,true)==1 and '$PROMPTSUBCOLOR$' or '$COMMANDCOLOR$'),s,comma)
    end)
    helps=helps:gsub("(SQL>) ([^\n]+)","$PROMPTCOLOR$%1 $COMMANDCOLOR$%2$NOR$")
    return helps:rtrim()..'\n',is_table
end

function helper.helper(cmd,...)
    local grid,_CMDS=env.grid,env._CMDS
    local rows={}
    if cmd and cmd:sub(1,1)~="-" then
        cmd = cmd:upper()
        if not _CMDS[cmd] or not _CMDS[cmd].HELPER then
            if env.event then env.event.callback("ON_HELP_NOTFOUND",cmd,...) end
            return 
        end
        local helps,target
        if type(_CMDS[cmd].HELPER) =="function" then
            local args,sub= _CMDS[cmd].OBJ and {_CMDS[cmd].OBJ,cmd,...} or {cmd,...}
            helps,sub = (_CMDS[cmd].HELPER)(table.unpack(args))
            helps = helps or "No help information."
            target= table.concat({cmd,sub}," ")
        else
            helps = _CMDS[cmd].HELPER or ""
            target=cmd
        end
        
        if helps=="" then return end
        helps,target=helper.colorful(helps,target)
        if not target then return print(helps) end
        return print(helps,'__PRINT_COLUMN_')
    elseif cmd=="-e" or cmd=="-E" then
        return helper.env(...)
    elseif cmd=="-j" or cmd=="-J" then
        return helper.jvm(...)
    elseif cmd=="-dump" then
        local cmd=java.loader:dumpClass(env.WORK_DIR.."dump")
        io.write("Command: "..cmd.."\n");
        return os.execute(cmd)
    elseif cmd=="-modules" then
        local row=grid.new()
        row:add{"#","Module","Total Time(ms)","Load Time(ms)","Init Time(ms)"}
        for k,v in pairs(env._M) do
            row:add{v.load_seq,k,math.round((v.load+v.onload)*1000),math.round(v.load*1000),math.round(v.onload*1000)}
        end
        row:sort(1)
        row:add_calc_ratio(3)
        return row:print()
    elseif cmd=="-buildjar" then
        local uv=env.uv
        local dels='"'..env.join_path(env.WORK_DIR..'/dump/*.jar*')..'"'
        if env.IS_WINDOWS then
            os.execute("del "..dels)
        else
            os.execute("rm -f "..dels)
        end
        local java_home,src=java.system:getProperty("java.home"):gsub('\\','/')
        local target=env.WORK_DIR..(env.IS_WINDOWS and 'jre' or (env.PLATFORM=='mac' and 'jre_mac') or 'jre_linux')
        for f,p in pairs{ rt='',
                          jce='',
                          jsse='',
                          charsets='',
                          localedata='ext/',
                          --sunjce_provider='ext/',
                          sunec='ext/',
                          sunmscapi='ext/',
                          ojdbc8='/dump/',
                          --xmlparserv2='/dump/',
                          oraclepki='/dump/',
                          osdt_cert='/dump/',
                          osdt_core='/dump/',
                          --orai18n='/dump/',
                          xdb='/dump/'} do
            local dir=env.join_path(env.WORK_DIR..'/dump/'..f)
            local jar=env.join_path(target..'/lib/'..p..f..'.jar')
            if p:sub(1,1)=='/' then jar=env.join_path(env.WORK_DIR..p..f..'.jar') end
            local list={}
            for _,f in ipairs(os.list_dir(dir,'*',999)) do
                list[#list+1]=f.fullname:sub(#dir+2):gsub("[\\/]","/")
            end

            if jar:find(target,1,true)==1 then
                src=java_home..jar:sub(#target+1):gsub('\\','/')
            else
                src=(env.WORK_DIR..'/oracle/'..f..'.jar'):gsub("[\\/]","/")
            end
            loader:createJar(list,jar,src)
            os.execute('pack200 -r -O -G "'..jar..'" "'..jar..'"')
        end
        return
    elseif cmd=="-stack" then
        return env.print_stack()
    elseif cmd=="-verbose" then
        local dest=select(1,...)
        if not dest then
            dest=env.WORK_DIR.."cache"..env.PATH_DEL.."verbose.log"
            local f=io.open(dest)
            local txt=f:read("*a")
            f:close()
            for v in txt:gmatch("%[Loaded%s+(%S+).-%]") do
                v=v:gsub("%.class$","")
                java.loader:copyClass(v)
            end
            for v in txt:gmatch("(%S+)%.class%W") do
                java.loader:copyClass(v)
            end
        else
            java.loader:copyClass(dest)
        end
        return
    end

    local flag=(cmd=="-a" or cmd=="-A") and 1 or 0
    table.insert(rows,{"Command","Abbr.","Max Args"})
    if flag==1 then
        table.append(rows[#rows],"Cross-lines?","Source")
    end
    table.insert(rows[#rows],"Decription")
    local ansi=env.ansi
    for k,v in pairs(_CMDS) do
        if k~="___ABBR___" and (v.DESC and not v.DESC:find("[ \t]*#") or flag==1) then
            table.insert(rows,{
                    k,
                    v.ABBR,
                    v.ARGS-1})
            if flag==1 then
                table.append(rows[#rows],(type(v.MULTI)=="function" or type(v.MULTI)=="string") and "Auto" or v.MULTI and 'Yes' or 'No',v.FILE)
            end
            local desc=v.DESC and v.DESC:gsub("^[%s#]+","") or " "
            local k1=k:gsub(',.+','')
            desc=desc:gsub("([Uu]sage)(%s*:%s*)(@@NAME)","$USAGECOLOR$Usage:$NOR$ "..k1:lower()):gsub("@@NAME","$USAGECOLOR$"..k1:lower().."$NOR$")
            table.insert(rows[#rows],desc)
            if (v.COLOR or "")~="" then
                rows[#rows][1]=ansi.mask(v.COLOR,rows[#rows][1])
                rows[#rows][2]=ansi.mask(v.COLOR,rows[#rows][2])
            end
        end
    end
    print("Available comands:\n===============")
    grid.sort(rows,1,true)
    grid.print(rows)
    return ""
end

function helper.desc()
    return [[
        Type 'help' to see the available comand list. Usage: @@NAME [<command>[,<sub_command1>...]|-a|-j|-stack|-e [<obj>]|help ]
        Options:
           -stack     To print stack of historical commands
           -a         To show all commands, including the hidden commands.
           -j         To show current JVM information
           -e         To show current environment infomation. Usage: help -e [<lua_table>[.<sub_table>] ]
           Internal:
                -verbose [class] :  dump a class or classes from verbose.log into dir "dump"
                -dump            :  dump classed of current process into dir "dump"
                -buildjar        :  build jars from in dir "dump"
                -modules         :  show loaded modules
        Other commands:
            help                             To brief the available commands(excluding hiddens)
            help <command>                   To show the help detail of a specific command
            help <command> [<sub_command>]   i.e. help ora actives
     ]]
end

env.set_command(nil,'help',helper.desc,helper.helper,false,9)
return helper