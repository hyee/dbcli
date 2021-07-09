local env,string,java,math,table,tonumber,tostring=env,string,java,math,table,tonumber,tostring
local grid,snoop,callback,cfg,db_core=env.grid,env.event.snoop,env.event.callback,env.set,env.db_core
local var=env.class()
local rawset,rawget=rawset,rawget
local cast,ip=java.cast,{}
local type,pairs,ipairs=type,pairs,ipairs
var.outputs,var.desc,var.global_context,var.columns=table.strong{},table.strong{},table.strong{},table.strong{}
var.inputs=setmetatable({},{
    __index=function(self,k)
        return rawget(ip,k)
    end,
    __pairs=function(self)
        return pairs(ip)
    end,
    __newindex=function(self,k,v) 
        rawset(ip,k,v)
    end})

var.cmd1,var.cmd2,var.cmd3,var.cmd4='DEFINE','DEF','VARIABLE','VAR'
var.types={
    REFCURSOR =  'CURSOR',
    CURSOR    =  'CURSOR',
    VARCHAR2  =  'VARCHAR',
    VARCHAR   =  'VARCHAR',
    NUMBER    =  'NUMBER',
    CLOB      =  'CLOB',
    CHAR      =  'VARCHAR',
    NCHAR     =  'VARCHAR',
    NVARCHAR2 =  'VARCHAR',
    BOOLEAN   =  'BOOLEAN'
}

function var.helper()
    local help=[[
        Define output variables for db execution. Usage: @@NAME <name> [<data type> [description] ]
            Define variable: @@NAME <name> <data_type> [description]
            Remove variable: @@NAME <name>
        Available Data types:
        ====================
        REFCURSOR CURSOR CLOB NUMBER CHAR VARCHAR VARCHAR2 NCHAR NVARCHAR2 BOOLEAN]]
    return help
end

function var.get_input(name)
    local res = var.inputs[name:upper()]
    return res~=db_core.NOT_ASSIGNED and res or nil
end

function var.import_context(global,input,output,cols)
    if type(output)=='table' then 
        var.outputs=output
    else
        output=table.strong{}
    end
    for k,v in pairs(global) do var.global_context[k]=v end
    for k,v in pairs(input or {}) do var.inputs[k]=v end
    if input then
        for k,v in pairs(var.global_context) do
            if not global[k] and not output[k] then var.global_context[k]=nil end
        end
        for k,v in pairs(var.inputs) do
            if not input[k] then
                if not output[k] then 
                    var.inputs[k]=nil
                else
                    var.outputs[k]=nil
                end
            end
        end
    end
    if cols then
        for k,v in pairs(cols) do var.columns[k]=v end
        for k,v in pairs(var.columns) do
            if not cols[k] then var.columns[k]=nil end
        end
    end
end

function var.backup_context()
    local global,input,output,cols=table.strong{},table.strong{},table.strong{},table.strong{}
    for k,v in pairs(var.global_context) do global[k]=v end
    for k,v in pairs(var.inputs) do input[k]=v end
    for k,v in pairs(var.outputs) do output[k]=v end
    for k,v in pairs(var.columns) do cols[k]=v end
    return global,input,output,cols
end

function var.setOutput(name,datatype,desc)
    if not name then
        return env.help.help("VAR")
    end

    name=name:upper()
    if not datatype then
        if var.outputs[name] then var.outputs[name]=nil end
        return
    end

    if desc then desc=var.update_text(desc) end

    datatype=datatype:upper():match("(%w+)")
    env.checkerr(var.types[datatype],'Unexpected data type['..datatype..']!')
    env.checkerr(name:match("^[%w%$_]+$"),'Unexpected variable name['..name..']!')
    var.inputs[name],var.outputs[name],var.desc[name]=nil,'#'..var.types[datatype],desc
end

function var.setInput(name,desc)
    if not name or name=="" then
        callback("ON_SHOW_INPUTS",var.inputs)
        print("Current defined variables:\n====================")
        for k,v in pairs(var.inputs) do
            if type(v)~="table" then
                print(k,'=',v)
            end
        end
        return
    end
    local value
    if not name:find('=') and desc then
        name,desc=name..(desc:sub(1,1)=="=" and '' or '=') ..desc,nil
    end
    name,value=name:match("^%s*([^=]+)%s*=%s*(.+)")
    if not name then env.raise('Usage: def name=<value> [description]') end
    value=value:gsub('^"(.*)"$','%1')
    name=name:upper()
    env.checkerr(name:match("^[%w%$_]+$"),'Unexpected variable name['..name..']!')
    var.inputs[name],var.outputs[name],var.desc[name]=value,nil,desc
end

function var.accept_input(name,desc)
    env.checkhelp(name)
    local uname,noprompt=name:upper()
    --if not var.inputs[uname] then return end
    if not desc then
        desc=var.desc[uname] or name
    else
        if desc:sub(1,7):lower()=="prompt " then
            desc=desc:sub(8)
            noprompt=false
        elseif desc:sub(1,9):lower()=="noprompt " then
            desc=desc:sub(10)
            var.inputs[uname]=''
            noprompt=true
        end
        desc=desc:gsub('^"(.*)"$','%1')
        if desc:sub(1,1)=='@' or desc:find('[\\/]') then
            local prefix=desc:sub(1,1)
            desc=prefix=='@' and desc:sub(2) or desc
            local typ,file=os.exists(desc,'sql')
            if typ~='file' then
                typ,file=os.exists(env.join_path(env._CACHE_PATH,desc),'sql')
            end
            if typ~='file' then
                if noprompt or prefix~='@' then return end
                env.raise("Cannot find file '"..desc.."'!")
            end
            local succ,txt=pcall(loader.readFile,loader,file,10485760)
            env.checkerr(succ,tostring(txt));
            var.inputs[uname]=txt
            return
        end
    end
    desc=desc:match("^[%s']*(.-)[%s':]*$")
    
    var.inputs[uname]=env.ask(desc)
    var.outputs[uname]=nil
end

function var.setInputs(name,args)
    var.inputs[name]=args
end

local var_pattern='%f[\\&](&+)([%w%_%$]+)(%.?)'
function var.update_text(item,pos,params)
    local org_txt
    if type(item)=="string" then
        org_txt,pos,item=item,1,{item}
    end

    callback("ON_SUBSTITUTION",item)

    if cfg.get("define")~='on' or not item[pos] then return end
    pos,params=pos or 1,params or {}
    local count=1
    local function repl(s,s2,s3)
        local v,s=s2:upper(),s..s2..s3
        v=params[v] or var.inputs[v] or var.global_context[v]
        if (v==nil or type(v)=='table') and tonumber(s2) then
            v="V"..s2
            v=params[v] or var.inputs[v] or var.global_context[v]
        end
        if v==nil or type(v)=='table' then return s end
        if v=='NEXT_ACTION' then print(env.callee(4)) end
        if v==db_core.NOT_ASSIGNED then v='' end
        count=count+1 
        env.log_debug("var",s,'==>',v==nil and "<nil>" or v=="" and '<empty>' or tostring(v))
        return v
    end

    while count>0 do
        count=0
        for k,v in pairs(params) do
            if type(v)=="string" then params[k]=v:gsub(var_pattern,repl) end
        end
    end

    count=1
    while count>0 do
        count=0
        item[pos]=item[pos]:gsub(var_pattern,repl)
    end

    if org_txt then return item[1] end
end

function var.before_db_exec(item)
    if cfg.get("define")~='on' then return end
    local db,sql,args,params=table.unpack(item)
    for i=1,3 do
        for name,v in pairs(i==1 and var.outputs or i==2 and var.inputs or var.global_context) do
            if type(v)~='table' then
                if i==1 and not args[name] then args[name]=v end
                if not params[name] then params[name]=v end
            end
        end
    end

    var.update_text(item,2,params)
end

function var.after_db_exec(item)
    local db,sql,args,_,params=table.unpack(item)
    local result,isPrint={},cfg.get("PrintVar")
    for k,v in pairs(params) do
        if var.inputs[k] and type(v) ~= "table" and v~=db_core.NOT_ASSIGNED then
            var.inputs[k]=v
        end
    end

    for k,v in pairs(var.outputs) do
        if v and k:upper()==k and args[k] and args[k]~=v then
            var.inputs[k],var.outputs[k]=args[k],nil
            if args[k]~=db_core.NOT_ASSIGNED then 
                result[k]=args[k]
            end
        end
    end

    var.current_db=db
    if isPrint=="on" then
        var.print(result)
    end
end

function var.print(name)
    local db=var.current_db
    if not name then return end
    if type(name)=="string" and name:lower()~='-a' then
        local verticals
        name=name:gsub('%s*\\G(%d*)%s*$', function(s) verticals=tonumber(s) or cfg.get("printsize");return '' end)
        local typ,f=os.exists(name)
        if typ=='file' then
            f=io.open(f,'r')
            if f then
                print(f:read("*a"))
                f:close()
            end
        else 
            name=name:upper()
            local obj=var.inputs[name]
            env.checkerr(obj,'Target variable[%s] does not exist!',name)
            if type(obj)=='userdata' and tostring(obj):find('ResultSet') then
                var.inputs[name]=db.resultset:print(obj,db.conn, var.desc[name] and (var.desc[name]..':\n'..string.rep('=',var.desc[name]:len()+1)),verticals)
                var.outputs[name]="#CURSOR"
            elseif type(obj)=='table' then
                grid.print(obj,nil,nil,nil,nil,prefix,"\n")
            elseif obj~=db_core.NOT_ASSIGNED then
                print(obj)
            end
        end
    else
        local list=type(name)=="table" and name or var.inputs
        local keys={}
        for k,v in pairs(list) do  keys[#keys+1]={type(v),k,v} end
        if #keys==0 then return end
        table.sort(keys,function(a,b)
            if a[1]==b[1] then return a[2]<b[2] end
            if a[1]=="userdata" or a[1]=="table" then return false end
            if b[1]=="userdata" or b[1]=="table" then return true end
            return a[1]<b[1]
        end)

        list={{'Variable','Value'}}
        for _,obj in ipairs(keys) do
            local name,value=obj[2],obj[3]
            if obj[1]=='userdata' and tostring(value):find('ResultSet') then
                var.inputs[name]=db.resultset:print(value,db.conn,var.desc[name] and (var.desc[name]..':\n'..string.rep('=',var.desc[name]:len()+1)))
                var.outputs[name]="#CURSOR"
            elseif type(value)=='table' then
                print('Variable "'..name..'":\n===================')
                grid.print(value,nil,nil,nil,nil,prefix,'\n')
            else
                list[#list+1]={var.desc[name] or name,value}
            end
        end
        if #list>1 then grid.print(list) end
    end
end

function var.save(name,file)
    env.checkerr(type(name)=="string",'Usage: save <variable> <file name>')
    if type(file)~="string" or var.outputs[file:upper()] then return end
    if var.inputs[file:upper()] then
        file=var.get_input(file)
        if file=='' or not file then return end
    end
    name=name:upper()
    env.checkerr(var.inputs[name],'Fail to save due to variable `%s` does not exist!',name)
    local obj=var.get_input(name)
    if not obj or obj=='' then return end
    if type(obj)=='userdata' and tostring(obj):find('ResultSet') then
        return print("Unsupported variable '%s'!", name);
    elseif type(obj)=='table' then
        obj=table.dump(obj)
    end

    if env.ansi then obj:strip_ansi() end
    file=env.write_cache(file,obj);
    print("Data saved to "..file);
end

function var.capture_before_cmd(cmd,args)
    if #env.RUNNING_THREADS>1 then return end
    if env._CMDS[cmd] and env._CMDS[cmd].FILE:find('var') then
        return
    end
    local sub=env._CMDS[cmd].ALIAS_TO or 'nil'
    if sub~=var.cmd1 and sub~=var.cmd2 and sub~=var.cmd3 and sub~=var.cmd4 and sub~='COL' and sub~='COLUMN' then
        env.log_debug("var","Backup variables")
        if not var._prevent_restore then
            var._backup,var._inputs_backup,var._outputs_backup,var._columns_backup=var.backup_context()
        end
    else
        var._backup,var._inputs_backup,var._outputs_backup,var._columns_backup=nil,nil,nil,nil
    end
end

function var.capture_after_cmd(cmd)
    if #env.RUNNING_THREADS>1 then return end
    if var._backup and not var._prevent_restore then
        env.log_debug("var","Reset variables")
        var.import_context(var._backup,var._inputs_backup,var._outputs_backup,var._columns_backup)
        var._backup,var._inputs_backup,var._outputs_backup,var._columns_backup=nil,nil,nil,nil
    end
end

function var.before_command(cmd)
    local name,args=table.unpack(cmd)
    args=type(args)=='string' and {args} or args
    if type(args)~='table' then return end
    for i=1,#args do var.update_text(args,i,{}) end
    if #env.RUNNING_THREADS==1 then var.capture_before_cmd(name,args) end
    return args
end

function var.format_function(fmt,next_fmt)
    local f,scale=fmt:match('^(.-)(%d*)$')
    scale=tonumber(scale) or 2
    local num_fmt="%."..scale.."f"
    local func
    local adj=0
    local f_fmt="%s"..num_fmt.."%s"
    local d_fmt='%s%d%s'
    local function to_fmt(sign,v,unit)
        return (v==0 and d_fmt or f_fmt):format(v==0 and '' or sign,v,unit),1
    end
    f=f:upper()
    if f=="KMG" or f=="TMB" then --KMGTP
        local units=f=="KMG" and {'   ',' KB',' MB',' GB',' TB',' PB',' EB',' ZB',' YB'} or {'  ',' K',' M',' B',' T',' Q'}
        local div=f=="KMG" and 1024 or 1000
        func=function(v)
            local s=tonumber(v)
            if not s then return v,1 end
            local prefix=s<0 and '-' or ''
            s=math.abs(s)
            for i=1,#units do
                v,s=math.round(s,scale),s/div
                if s<1 then return to_fmt(prefix,v,units[i]) end
            end
            return to_fmt(prefix,v,units[#units])
        end
    elseif f=="AUTO" then
        f=(next_fmt or ""):upper()
        if f=='' then return end
        adj=1
        local col=f
        local u1,u2,u3={'   ',' KB',' MB',' GB',' TB',' PB',' EB',' ZB',' YB'} , {'   ',' Ki',' Mi',' Bi',' Tr',' Qu'},{' us',' ms',' s ',' m ',' h ',' d '}
        local d1,d2,d3=1024,1000,{1000,1000,60,60,24,1}
        local c,p=nil
        local p1={
            byte={u1,1},
            ['(kb)']={u1,1024},
            ['(mb)']={u1,1024*1024},
            ['(gb)']={u1,1024*1024*1024},
            secs={u3,1e6},
            ['(us)']={u3,1},
            ['(ms)']={u3,1e3}
        }
        local p2={
            ['%Wkb$']={u1,1024},
            ['%Wmb$']={u1,1024*1024},
            ['%Wgb$']={u1,1024*1024*1024},
            ['%Ws$']={u3,1e6},
            ['%Wms$']={u3,1e3},
            ['%Wus$']={u3,1}
        }
        func=function(v,r,grid)
            local s,val=tonumber(v)
            if type(r)=='string' and type(grid)~='table' then
                val=r
            else
                local rows=grid.data
                if rows[1] and rows[1].colinfo then
                    c=rows[1].colinfo[col]
                elseif rows[1] and p~=rows[1] then
                    p=rows[1]
                    for k,v in ipairs(p) do
                        if type(v)=='string' and v:upper()==col then
                            c=k
                            break
                        end
                    end
                end
                local row=grid.__current_row
                if not c or not row then return v,1 end 
                val=row[c]
            end
            if s==0 then return '',1 end
            if not s or type(val)~='string' then return v,1 end
            local prefix=s<0 and '-' or ''
            s,val=math.abs(s),val:lower()
            local units
            for k,v in pairs(p1) do
                if val:find(k,1,true) then
                    units,s=v[1],s*v[2]
                    break
                end
            end
            if not units then
                for k,v in pairs(p2) do
                    if val:find(k) then
                        units,s=v[1],s*v[2]
                        break
                    end
                end
            end
            if not units then
                units=u2
            end
            local div=units==u1 and d1 or units==u3 and d3 or d2
            for i=1,#units do
                v,s=math.round(s,scale),s/(type(div)=='number' and div or div[i])
                if s<1 then return to_fmt(prefix,v,units[i]) end
            end
            return to_fmt(prefix,v,units[#units])
        end
    elseif f:find('^.SMHD$') or f=='SMHD' and fmt:find('%d$') then
        local div,units
        if f:sub(1,1)=='U' then
            units,div={'us','ms','s','m','h','d'},{1000,1000,60,60,24}
        elseif f:sub(1,1)=='M' then
            units,div={'ms','s','m','h','d'},{1000,60,60,24}
        else
            units,div={'s','m','h','d'},{60,60,24}
        end
        func=function(v)
            local s=tonumber(v)
            if not s then return v,1 end
            local prefix=s<0 and '-' or ''
            s=math.abs(s)
            for i=1,#units-1 do
                v,s=math.round(s,scale),s/div[i]
                if v==0 then return '0 ',1 end
                if s<1 then return to_fmt(prefix,v,units[i]) end
            end
            return to_fmt(prefix,v,units[#units])
        end
    elseif f=="SMHD" or f=="ITV" or f=="INTERVAL" then
        fmt=fmt=='SMHD' and '%dD %02dH %02dM %02dS' or
              f=='SMHD' and '%dd %02dh %02dm %02ds' or '%d %02d:%02d:%02d'
        func=function(v)
            if not tonumber(v) then return v,1 end
            local s,u=tonumber(v),{}
            local prefix=s<0 and '-' or ''
            s=math.abs(s)
            for i=1,2 do
                s,u[#u+1]=math.floor(s/60),s%60
            end
            u[#u+2],u[#u+1]=math.floor(s/24),s%24
            return prefix..fmt:format(u[4],u[3],u[2],u[1]):gsub("^0 ",''),1
        end
    elseif f=='PCT' or f=='PERCENTAGE' or f=='PERCENT' then
        local float_fmt="%."..scale.."f%%"
        func=function(v)
            local v1=tonumber(v)
            if not v1 then return v,1 end
            if scale>0 and math.floor(v*math.pow(10,scale))/math.pow(10,scale-2)==100 then
                return ("%."..(scale-1).."f%%"):format(v1*100),1
            end
            return float_fmt:format(v1*100),1
        end
    elseif (f:find("%",1,true) or 999)<#f or f=='K' then
        local f1,String=fmt,String
        local format=String.format
        if f=='K' then f1='%,.'..scale..'f' end
        local format_func=function(v)
            local v1= tonumber(v)
            if not v1 then return v,1 end
            local done,res=pcall(format,String,f1,cast(v,'java.math.BigDecimal'))
            if not done then
                env.raise('Cannot format double number "'..v..'" with "'..f1..'"!')
            end
            return res,1
        end
        local res,msg=pcall(format_func,999.99)
        env.checkerr(res,"Unsupported format %s",fmt)
        func=format_func
    end
    return func,adj
end

function var.define_column(col,...)
    env.checkhelp(col)
    if type(col)~="string" or col:trim()=="" then return end
    if col:find(',',1,true) then
        local cols=col:split("%s*,+%s*")
        for k,v in ipairs(cols) do var.define_column(v,...) end
        return
    end
    local gramma={
        {{'ALIAS','ALI'},'*'},
        {{'CLEAR','CLE'}},
        {'ENTMAP ',{'ON','OFF'}},
        {{'FOLD_AFTER','FOLD_A'}},
        {{'FOLD_BEFORE','FOLD_B'}},
        {{'FORMAT','FOR'}, '*'},
        {{'HEADING','HEA','HEAD'},'*'},
        {{'JUSTIFY','JUS'},{'LEFT','L','CENTER','C','RIGHT','R'}},
        {'LIKE','.+'},
        {{'NEWLINE','NEWL'}},
        {{'NEW_VALUE','NEW_V'},'*'},
        {{'NOPRINT','NOPRI','PRINT','PRI'}},
        {{'OLD_VALUE','OLD_V'},'*'},
        {{'NULL','NUL'},'*'},
        {{'ON','OFF'}},
        {{'WRAPPED','WRA','WORD_WRAPPED','WOR','TRUNCATED','TRU'}},
    }

    local args,arg={...}
    env.checkhelp(args[1])
    col=col:upper()
    var.columns[col]=var.columns[col] or {}
    local obj=var.columns[col]
    local valid=false
    local formats={}
    for i=1,#args do
        args[i],arg=args[i]:upper(),args[i+1] or ""
        local f,f1,scale=arg:upper(),arg:upper():match('(.-)(%d*)$')
        scale=tonumber(scale) or 2
        if args[i]=='NEW_VALUE' or args[i]=='NEW_V' then
            env.checkerr(arg,'Format:  COL[UMN] <column> NEW_V[ALUE] <variable> [PRINT|PRI|NOPRINT|NOPRI].')
            arg=arg:upper()
            var.setOutput(arg,'VARCHAR')
            obj.new_value=arg
            i=i+1
            valid=true
        elseif args[i]=="BREAK" then
            local isskip=nil
            if f=='SKIP' then
                i=i+1
                f=(args[i+1] or ""):upper()
                isskip=' '
            end
            if #f==1 then
                isskip=tonumber(f) and ' ' or f
                i=i+1
            end
            formats[#formats+1]=function(v,rownum,grid)
                if not rownum or env.printer.grep_text then return v end
                if type(v)=='string' and (v==' ' or v==f or v=='') then return v end
                if grid.break_groups[col]==nil or rownum<=1 then
                    obj._prev_value=v
                    grid.break_groups[col]=v
                    return v
                elseif obj._prev_value==v then
                    return ''
                else
                    grid.break_groups.__SEP__=isskip or grid.break_groups.__SEP__
                    obj._prev_value=v
                    return v
                end
            end
        elseif args[i]=='FORMAT' or args[i]=='FOR' then
            local func
            env.checkerr(arg,'Format:  COL[UMN] <column> FOR[MAT] [KMB|TMB|ITV|SMHD|<format>] JUS[TIFY] [LEFT|L|RIGHT|R].')
            if f:find('^A%d+') then
                local siz=tonumber(arg:match("%d+"))
                obj.format_dir='%-'..siz..'s'
                func=function(v) return tostring(v) and obj.format_dir:format(tostring(v):sub(1,siz)) or v end
            elseif f:find("^HEADING") then
                f = arg:match('^%w+%s+(.+)')
                if f then return var.define_column(col,'HEADING',f) end
            else
                local incr
                func,incr=var.format_function(arg,args[i+2])
                if func then i=i+incr end
            end
            if not func and not var.define_column(col,f) then
                local fmt=java.new("java.text.DecimalFormat")
                local format=fmt.format
                arg=arg:gsub('9','#'):gsub("^[fF][mM]","")
                local res,msg=pcall(fmt.applyPattern,fmt,arg)
                obj.format_dir='%'..#arg..'s'
                func=function(v)
                    if not tonumber(v) then return v,1 end
                    local done,res=pcall(obj.format_dir.format,obj.format_dir,format(fmt,cast(v,'java.math.BigDecimal')))
                    if not done then
                        env.raise('Cannot format double number "'..v..'" with "'..arg..'" on field "'..col..'"!')
                    end
                    return res:trim(),1
                end
                local res,msg=pcall(func,999.99)
                env.checkerr(res,"Unsupported format %s on field %s",arg,col)
            end
            formats[#formats+1]=func
            i=i+1
            valid=true
        elseif args[i]=="ADDRATIO" then
            obj.add_ratio={1,f1,scale}
            i=i+1
            valid=true
        elseif args[i]=='PRINT' or args[i]=='PRI' then
            obj.print=true
            valid=true
        elseif args[i]=='NOPRINT' or args[i]=='NOPRI' then
            obj.print=false
            valid=true
        elseif args[i]=='HEADING' or args[i]=='HEAD'  or args[i]=='HEA' then
            local arg=args[i+1]
            env.checkerr(arg,'Format:  COL[UMN] <column> HEAD[ING] <new name>.')
            obj.heading=arg
            i=i+1
            valid=true
        elseif args[i]=='JUSTIFY' or args[i]=='JUS' then
            local arg=arg and arg:upper()
            local dir
            if arg then
                dir=(arg=='L' and '-') or (arg=='R' and '') or (arg=='LEFT' and '-') or (arg=='RIGHT' and '')
            end
            env.checkerr(dir,'Format:  COL[UMN] <column> FOR[MAT] <format> JUS[TIFY] [LEFT|L|RIGHT|R].')
            if type(obj.format_dir)=="string" then
                obj.format_dir=obj.format_dir:gsub("-*(%d+)",dir..'%1')
            else
                local siz=0
                for _,c in ipairs((obj.heading or col):strip_ansi():split(' *| *')) do
                    local len=c:ulen()
                    siz=siz<len and len or siz
                end
                obj.format_dir='%'..dir..siz..'s'
                formats[#formats+1]=function(v)
                    if not v or v=='' then return v,1 end
                    return obj.format_dir:format(tostring(v)),1
                end
            end
            i=i+1
            valid=true
        elseif args[i]=='CLEAR' or args[i]=='CLE' then
            var.columns[col]=nil
            valid=true
        end
    end
    if #formats>0 then
        obj.format=function(v,rownum,grid)
            local org,is_number,v1,tmp=org
            for _,func in ipairs(formats) do
                v,tmp=func(v,rownum,grid)
                if tmp then is_number=true end
            end
            return v,is_number
        end
    end
    return valid
end


function var.trigger_column(field)
    local col,value,rownum,grid,rowind,row=table.unpack(field)
    local index
    if type(col)~="string" then return end
    col=col:upper()
    if not var.columns[col] then return end
    local obj=var.columns[col]

    if rownum==0 then
        index=obj.heading
        if index then
            field[2],var.columns[index:upper()]=index,obj
        end
        if obj.print==false then field[2]='' end
        --return
    elseif rownum>0 and grid and not grid.__var_parsed then
        grid.__var_parsed=true
        for col,config in pairs(var.columns) do
            if config.add_ratio then
                grid:add_calc_ratio(col,table.unpack(config.add_ratio))
                field.is_number=true
            end
        end
    end

    if not value then return end

    index=obj.format
    if index then
        if grid then grid.__current_row=row end
        field[2],field.is_number=index(value,rowind,grid)
        if grid then grid.__current_row=nil end
    end
    
    index=obj.new_value
    if index then
        var.inputs[index],var.outputs[index]=value or db_core.NOT_ASSIGNED,nil
        if obj.print==true then print(string.format("Variable %s == > %s",index,value or 'NULL')) end
    end

    if obj.print==false then field[2]='' end
end

function var.onload()
    snoop('BEFORE_DB_EXEC',var.before_db_exec)
    snoop('AFTER_DB_EXEC',var.after_db_exec)
    snoop('BEFORE_EVAL',function(item) if not env.pending_command() then var.update_text(item,1) end end)
    snoop('BEFORE_COMMAND',var.before_command)
    snoop("AFTER_COMMAND",var.capture_after_cmd)
    snoop("ON_COLUMN_VALUE",var.trigger_column)
    local fmt_help=[[
    Specifies display attributes for a given column. Usage: @@NAME <columns> [NEW_VALUE|FORMAT|HEAD|ADDRATIO|BREAK] <value> [<options>]
    Refer to SQL*Plus manual for the detail, below are the supported features:
        1) @@NAME <columns> NEW_V[ALUE] <var>    [PRINT|NOPRINT]
        2) @@NAME <columns> HEAD[ING]   <title>
        3) @@NAME <columns> FOR[MAT]    <format> [JUS[TIFY] LEFT|L|RIGHT|R]
        4) @@NAME <columns> CLE[AR]

    Other addtional features:
        1) @@NAME <columns> ADDRATIO <name>[scale]: Create an additional field to show the report_to_ratio value
        2) @@NAME <columns> FOR[MAT] KMG[scale]   : Cast number as KB/MB/GB/etc format
        3) @@NAME <columns> FOR[MAT] TMB[scale]   : Cast number as thousand/million/billion/etc format
        4) @@NAME <columns> FOR[MAT]  smhd<scale> : Cast number as '<number>[s|m|h|d]' format
        4) @@NAME <columns> FOR[MAT] msmhd<scale> : Cast number as '<number>[ms|s|m|h|d]' format
        4) @@NAME <columns> FOR[MAT] usmhd<scale> : Cast number as '<number>[us|ms|s|m|h|d]' format
        5) @@NAME <columns> FOR[MAT] SMHD         : Cast number as 'xxD xxH xxM xxS' format
        6) @@NAME <columns> FOR[MAT] smhd         : Cast number as 'xxd xxh xxm xxs' format
        7) @@NAME <columns> FOR[MAT] INTERVAL|ITV : Cast number as 'dd hh:mm:ss' format
        8) @@NAME <columns> FOR[MAT] <formatter>  : Use Java 'String.format()' to format the number
        9) @@NAME <columns> FOR[MAT] K<scale>     : Cast number in thousand seperated
       10) @@NAME <columns> BREAK [SKIP] [<char>] : Similar to the SQL*Plus BREAK command
       11) @@NAME <columns> FOR[MAT] AUTO <based> : Auto cast number as KMG/TMB based on column "<based>" of the same grid  

    type 'help -e var.columns' to show the existing settings

    Examples:
        @@NAME size for kmg1  :    111111 => 108.5 KB
        @@NAME size for tmb3  :    111111 => 111.111 K
        @@NAME size for usmhd2:    111111 => 111.11ms
        @@NAME size for smhd1 :    111111 => 1.3d
        @@NAME size for SMHD  :    111111 => 0D 30H 51M 51S
        @@NAME size for ITV   :    111111 => 30:51:51
        @@NAME size for %.2f%%:    11.111 => 11.11%
        @@NAME size for K1    :    1111.11=> 1,111.1
        @@NAME size1,size2 for %.2f%% :  11.111, 22.222 => 11.11%, 22.22%
        @@NAME size for smhd1 addration pct2:    
            SIZE   PTC
            ---- -----
            1.3d 26.12%
            1.2d 25.30%  
    ]]
    cfg.init({"VERIFY","PrintVar",'VER'},'on',nil,"db.core","Max size of historical commands",'on,off')
    cfg.init({var.cmd1,var.cmd2},'on',nil,"db.core","Defines the substitution character(&) and turns substitution on and off.",'on,off')
    env.set_command(nil,{"Accept","Acc"},'Assign user-input value into a existing variable. Usage: @@NAME <var> [[prompt] <prompt_text>|[noprompt] @<file>]',var.accept_input,false,3)
    env.set_command(nil,{var.cmd3,var.cmd4},var.helper,var.setOutput,false,4)
    env.set_command(nil,{var.cmd1,var.cmd2},"Define input variables, Usage: @@NAME <name>[=]<value> [description], or @@NAME <name> to remove definition",var.setInput,false,3)
    env.set_command(nil,{"COLUMN","COL"},fmt_help,var.define_column,false,30)
    env.set_command(nil,{"Print","pri"},'Display the values of bind variables or file.Usage: @@NAME <variable>|<file>|-a',var.print,false,3)
    env.set_command(nil,"Save","Save variable value into a specific file under folder 'cache'. Usage: @@NAME <variable> <file name>",var.save,false,3);
end

return var