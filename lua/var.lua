local env,string,java=env,string,java
local grid,snoop,cfg,db_core=env.grid,env.event.snoop,env.set,env.db_core
local var=env.class()
var.inputs,var.outputs,var.desc,var.global_context,var.columns={},{},{},{},{}
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
        Define output variables for db execution. Usage: "var <name> <data type> [description]", or "var <name>" to remove
            Define variable: var <name> <data_type> [description]
            Remove variable: var <name>
        Available Data types:
        ====================
        REFCURSOR CURSOR CLOB NUMBER CHAR VARCHAR VARCHAR2 NCHAR NVARCHAR2 BOOLEAN]]
    return help
end

function var.get_input(name)
    local res = var.inputs[name:upper()]
    return res~=db_core.NOT_ASSIGNED and res or nil
end

function var.import_context(global,input,output)
    for k,v in pairs(global) do var.global_context[k]=v end
    for k,v in pairs(input or {}) do var.inputs[k]=v end
    if input then
        for k,v in pairs(var.global_context) do
            if not global[k] and not output[k] then var.global_context[k]=nil end
        end
        for k,v in pairs(var.inputs) do
            if not input[k] and not output[k] then var.inputs[k]=nil end
        end
    end
end

function var.backup_context()
    local global,input,output={},{},{}
    for k,v in pairs(var.global_context) do global[k]=v end
    for k,v in pairs(var.inputs) do input[k]=v end
    for k,v in pairs(var.outputs) do output[k]=v end
    return global,input,output
end

function var.setOutput(name,datatype,desc)
    if not name then
        return env.helper.helper("VAR")
    end

    name=name:upper()
    if not datatype then
        if var.outputs[name] then var.outputs[name]=nil end
        return
    end

    datatype=datatype:upper():match("(%w+)")
    env.checkerr(var.types[datatype],'Unexpected data type['..datatype..']!')
    env.checkerr(name:match("^[%w%$_]+$"),'Unexpected variable name['..name..']!')
    var.inputs[name],var.outputs[name],var.desc[name]=nil,'#'..var.types[datatype],desc
end

function var.setInput(name,desc)
    if not name or name=="" then
        print("Current defined variables:\n====================")
        for k,v in pairs(var.inputs) do
            if type(v)~="table" then
                print("    ",k,'=',v)
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
    if not name then return end
    local uname=name:upper()
    if not var.inputs[uname] then return end
    if not desc then
        desc=var.desc[uname] or name
    else
        if desc:sub(1,7):lower()=="prompt " then
            desc=desc:sub(8)
        elseif desc:sub(1,1)=='@' then
            desc=desc:sub(2)
            if not desc:match('(%.%w+)$') then desc=desc..'.sql' end
            local f=io.open(desc)
            env.checkerr(f,"Cannot find file '"..desc.."'!")
            var.inputs[uname]=f:read('*a')
            f:close()
            return
        end
    end
    desc=desc:match("^[%s']*(.-)[%s':]*$")..': '
    env.printer.write(desc)
    var.inputs[uname]=io.read()
end

function var.setInputs(name,args)
    var.inputs[name]=args
end

local function update_text(item,pos,params)
    if cfg.get("define")~='on' then return end
    pos,params=pos or 1,params or {}
    local count=1
    local function repl(s,s2,s3)
        local v,s=s2:upper(),s..s2..s3
        v=params[v] or var.inputs[v] or var.global_context[v] or s
        if v~=s then
            if v=='NEXT_ACTION' then print(env.callee(4)) end
            if v==db_core.NOT_ASSIGNED then v='' end
            count=count+1 
            env.log_debug("var",s,'==>',v==nil and "<nil>" or v=="" and '<empty>' or tostring(v))
        end
        return v
    end

    while count>0 do
        count=0
        item[pos]=item[pos]:gsub('%f[%w_%$&](&+)([%w%_%$]+)(%.?)',repl)
    end
end

function var.before_command(cmd)
    local name,args=table.unpack(cmd)
    args=type(args)=='string' and {args} or args
    if type(args)~='table' then return end
    for i=1,#args do update_text(args,i,{}) end
    if #env.RUNNING_THREADS==1 then var.capture_before_cmd(name,args) end
    return args
end

function var.before_db_exec(item)
    if cfg.get("define")~='on' then return end
    local db,sql,args,params=table.unpack(item)
    for i=1,3 do
        for name,v in pairs(i==1 and var.outputs or i==2 and var.inputs or var.global_context) do
            if i==1 and not args[name] then args[name]=v end
            if not params[name] then params[name]=v end
        end
    end

    update_text(item,2,params)
end

function var.after_db_exec(item)
    local db,sql,args=table.unpack(item)
    local result,isPrint={},cfg.get("PrintVar")
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
        name=name:upper()
        local obj=var.inputs[name]
        env.checkerr(obj,'Target variable[%s] does not exist!',name)
        if type(obj)=='userdata' and tostring(obj):find('ResultSet') then
            if var.desc[name] then print(var.desc[name]..':\n'..string.rep('=',var.desc[name]:len()+1)) end
            db.resultset:print(obj,db.conn)
        else
            print(obj)
        end
    else
        local list=type(name)=="table" and name or var.inputs
        local keys={}
        for k,v in pairs(list) do  keys[#keys+1]={type(v),k,v} end
        if #keys==0 then return end
        table.sort(keys,function(a,b)
            if a[1]==b[1] then return a[2]<b[2] end
            if a[1]=="userdata" then return false end
            if b[1]=="userdata" then return true end
            return a[1]<b[1]
        end)

        list={{'Variable','Value'}}
        for _,obj in ipairs(keys) do
            local name,value=obj[2],obj[3]
            if obj[1]=='userdata' and tostring(value):find('ResultSet') then
                if var.desc[name] then print(var.desc[name]..':\n'..string.rep('=',var.desc[name]:len()+1)) end
                db.resultset:print(value,db.conn)
                var.inputs[name]=nil
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
        file=var.inputs[file:upper()]
        if file=='' then return end
    end
    name=name:upper()
    local obj=var.inputs[name]
    env.checkerr(obj,'Target variable[%s] does not exist!',name)
    if not var.get_input(name) then return end
    if type(obj)=='userdata' and tostring(obj):find('ResultSet') then
        return print("Unsupported variable '%s'!", name);
    end
    file=env.write_cache(file,obj);
    print("Data saved to "..file);
end

function var.capture_before_cmd(cmd,args)
    if cmd~=var.cmd1 and cmd~=var.cmd2 and cmd~=var.cmd3 and cmd~=var.cmd4 then
        env.log_debug("var","Backup variables")
        var._backup,var._inputs_backup,var._outputs_backup=var.backup_context()
    else
        var._backup,var._inputs_backup,var._outputs_backup=nil,nil,nil
    end
end

function var.capture_after_cmd(cmd)
    if #env.RUNNING_THREADS>1 then return end
    if var._backup then
        env.log_debug("var","Reset variables")
        var.import_context(var._backup,var._inputs_backup,var._outputs_backup)
        var._backup,var._inputs_backup,var._outputs_backup=nil,nil,nil
    end
end

function var.define_column(col,...)
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

    local args={...}
    env.checkerr(args[1],env.helper.helper,env.CURRENT_CMD)
    col=col:upper()
    var.columns[col]=var.columns[col] or {}
    for i=1,#args do
        args[i]=args[i]:upper()
        if args[i]=='NEW_VALUE' or args[i]=='NEW_V' then
            local arg=args[i+1]
            env.checkerr(arg,'Format:  COL[UMN] <column> NEW_V[ALUE] <variable> [PRINT|PRI|NOPRINT|NOPRI].')
            col,arg=col:upper(),arg:upper()
            var.setOutput(arg,'VARCHAR')
            var.columns[col].new_value=arg
            i=i+1
        elseif args[i]=='FORMAT' or args[i]=='FOR' then
            local arg=args[i+1]
            env.checkerr(arg,'Format:  COL[UMN] <column> FOR[MAT] <format> JUS[TIFY] [LEFT|L|RIGHT|R].')
            if arg:upper():find('^A') then
                var.columns[col].format='%-'..tonumber(arg:match("%d+"))..'s'
            else
                local fmt=java.new("java.text.DecimalFormat")
                arg=arg:gsub('9','#')
                local res,msg=pcall(fmt.applyPattern,fmt,arg)
                env.checkerr(res,"Invalid format %s: %s",arg,tostring(msg))
                var.columns[col].format=fmt
                var.columns[col].num_len='%'..#arg..'s'
            end
            i=i+1
        elseif args[i]=='PRINT' or args[i]=='PRI' then
            var.columns[col].print=true
        elseif args[i]=='NOPRINT' or args[i]=='NOPRI' then
            var.columns[col].print=false
        elseif args[i]=='HEADING' or args[i]=='HEAD'  or args[i]=='HEA' then
            local arg=args[i+1]
            env.checkerr(arg,'Format:  COL[UMN] <column> HEAD[ING] <new name>.')
            var.columns[col].heading=arg
        elseif args[i]=='JUSTIFY' or args[i]=='JUS' and var.columns[col].format then
            local arg=args[i+1] and args[i+1]:upper()
            local dir
            if arg then
                dir=(arg=='L' and '-') or (arg=='R' and '') or (arg=='LEFT' and '-') or (arg=='RIGHT' and '')
            end
            env.checkerr(dir,'Format:  COL[UMN] <column> FOR[MAT] <format> JUS[TIFY] [LEFT|L|RIGHT|R].')
            if type(var.columns[col].format)=="string" then
                var.columns[col].format=var.columns[col].format:gsub("-*(%d+)",dir..'%1')
            else
                var.columns[col].num_len=var.columns[col].num_len:gsub("-*(%d+)",dir..'%1')
            end
        end
    end
end


function var.trigger_column(field)
    local col,value,rownum,index=table.unpack(field)
    col=col:upper()
    if not var.columns[col] then return end
    if rownum==0 then
        index=var.columns[col].heading
        if index then
            field[2],var.columns[index:upper()]=index,var.columns[col]
        end
        return 
    end
    
    if not value then return end
    index=var.columns[col].format
    if index then
        if type(index)=="string" then
            field[2]=index:format(tostring(value))
        else
            value=tonumber(value)
            field[2]=var.columns[col].num_len:format(value and index:format(java.cast(value,'double')) or field[2])
        end
    end

    index=var.columns[col].new_value
    if index then
        var.inputs[index],var.outputs[index]=value or db_core.NOT_ASSIGNED,nil
        if var.columns[col].print==true then print(string.format("Variable %s == > %s",index,value or 'NULL')) end
    end
end

function var.onload()
    snoop('BEFORE_DB_EXEC',var.before_db_exec)
    snoop('AFTER_DB_EXEC',var.after_db_exec)
    snoop('BEFORE_EVAL',update_text)
    snoop('BEFORE_COMMAND',var.before_command)
    snoop("AFTER_COMMAND",var.capture_after_cmd)
    snoop("ON_COLUMN_VALUE",var.trigger_column)
    cfg.init("PrintVar",'on',nil,"db.core","Max size of historical commands",'on,off')
    cfg.init(var.cmd1,'on',nil,"db.core","Defines the substitution character(&) and turns substitution on and off.",'on,off')
    env.set_command(nil,{"Accept","Acc"},'Assign user-input value into a existing variable. Usage: accept <var> [[prompt] <prompt_text>|@<file>]',var.accept_input,false,3)
    env.set_command(nil,{var.cmd3,var.cmd4},var.helper,var.setOutput,false,4)
    env.set_command(nil,{var.cmd1,var.cmd2},"Define input variables, Usage: def <name>[=]<value> [description], or def <name> to remove definition",var.setInput,false,3)
    env.set_command(nil,{"COLUMN","COL"},'Specifies display attributes for a given column, refer to SQL*Plus manual.',var.define_column,false,30)
    env.set_command(nil,{"Print","pri"},'Displays the current values of bind variables.Usage: print <variable|-a>',var.print,false,3)
    env.set_command(nil,"Save","Save variable value into a specific file under folder 'cache'. Usage: save <variable> <file name>",var.save,false,3);
end

return var