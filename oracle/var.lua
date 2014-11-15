local env=env
local grid,snoop,cfg=env.grid,env.event.snoop,env.set
local db=env.oracle
local var={inputs={},outputs={},desc={},global_context={}}

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

function var.import_context(ary)
    for k,v in pairs(ary) do var.global_context[k]=v end
end

function var.setOutput(name,datatype,desc)
    if not name then 
        return env.helper.helper("VAR")
    end
    
    name=name:upper()
    if not datatype then
        if var.outputs[name] then var.outputs[name]=nil end
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
    if name:find('=') then name,value=name:match("^%s*([^=]+)%s*=%s*(.+)") end
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
    item[pos]=item[pos]:gsub('%f[%w_%$&]&([%w%_%$]+)',function(s) 
        local v=s:upper()
        return params[v] or 
               var.inputs[v] or
               var.global_context[v] or 
               '&'..s 
    end)
end

function var.before_db_parse(item)
    update_text(item,2,item[3])
end

function var.before_print(item)
    update_text(item,1,{})
end

function var.before_db_exec(item)
    local db,sql,args=table.unpack(item)
    for k,v in pairs(var.outputs) do
        if not args[k] then
            args[k]=v
        end
    end

    for name,v in pairs(var.inputs) do
        if not args[name] then args[name]=v end
    end

    for name,v in pairs(var.global_context) do
        if not args[name] then args[name]=v end
    end     
end

function var.after_db_exec(db,sql,args)
    if db:is_internal_call(sql) then return end
    local result,isPrint={},cfg.get("PrintVar")
    for k,v in pairs(var.outputs) do
        if v and k:upper()==k and args[k] and args[k]~=v then
            var.inputs[k],var.outputs[k]=args[k],nil
            result[k]=args[k]            
        end
    end
    
    if isPrint=="on" then
        var.print(result)
    end
end

function var.print(name)
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

function var.onload()
    snoop('BEFORE_DB_STMT_PARSE',var.before_db_parse)
    snoop('BEFORE_ORACLE_EXEC',var.before_db_exec)
    snoop('AFTER_ORACLE_EXEC',var.after_db_exec)
    snoop('BEFORE_PRINT_TEXT' ,var.before_print)
    cfg.init("PrintVar",'on',nil,"oracle","Max size of historical commands",'on,off')
    cfg.init("Define",'on',nil,"oracle","Defines the substitution character(&) and turns substitution on and off.",'on,off')
    env.set_command(nil,{"Accept","Acc"},'Assign user-input value into a existing variable. Usage: accept <var> [prompt] [<prompt_text>]',var.accept_input,false,3)
    env.set_command(nil,{"variable","VAR"},var.helper,var.setOutput,false,4)
    env.set_command(nil,{"Define","DEF"},"Define input variables, Usage: def <name>=<value> [description], or def <name> to remove definition",var.setInput,false,4)
    env.set_command(nil,{"Print","pri"},'Displays the current values of bind variables(refer to command "VAR" and "DEF").Usage: print <variable|-a>',var.print,false,3)    
end    
return var