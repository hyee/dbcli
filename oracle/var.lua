local env=env
local grid,snoop,cfg=env.grid,env.event.snoop,env.set
local db=env.oracle
local var={inputs={},outputs={},output_result={}}

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
        Define output variables for db execution. Usage: "var <name> <data type>", or "var <name>" to remove
            Define variable: var <name> <data_type>
            Remove variable: var <name>
        Available Data types:
        ====================
        REFCURSOR CURSOR CLOB NUMBER CHAR VARCHAR VARCHAR2 NCHAR NVARCHAR2 BOOLEAN]]
    return help
end


function var.setOutput(name,datatype)
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
    --env.checkerr(not if var.inputs[name],"The name["..name.."] has been defined as input parameter!")
    if var.inputs[name] then var.inputs[name]=nil end
    var.outputs[name]='#'..var.types[datatype]
end

function var.setInput(name)
    if not name or name=="" then
        print("Current defined variables:\n====================")
        for k,v in pairs(var.inputs) do
            if type(v)~="table" then
                print("    ",k,'=',v)
            end
        end
        return
    end

    if name:find('=') then 
        name,value=name:match("^([^=%s]+)%s*=%s*(.*)")
        if not value then return end
    elseif name:find(' ') then     
        name,value=name:match("^([^=%s]+)%s+(.*)")
        if not value then return end
    end

    name=name:upper()
    env.checkerr(name:match("^[%w%$_]+$"),'Unexpected variable name['..name..']!')    
    --if var.outputs[name] then  return print("The name["..name.."] has ben defined as  output parameter!") end
    if var.outputs[name] then var.outputs[name]=nil end
    var.setInputs(name,value)    
end

function var.setInputs(name,args)
    if not args then
        if var.inputs[name] then var.inputs[name]=nil end
        return
    end
    var.inputs[name]=args
end

function var.before_db_exec(db,sql,args)
    for k,v in pairs(var.outputs) do
        if not args[k] then
            args[k]=v
        end
    end

    for name,v in pairs(var.inputs) do
        if type(v)=="table" then
            for i,j in pairs(v) do
                if not args[i] then args[i]=j end
            end
        elseif not args[name] then
            args[name]=v
        end
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
        env.checkerr(obj,'Target variable does not exist!')   
        if type(obj)=='userdata' and tostring(obj):find('ResultSet') then 
            db.resultset:print(obj,db.conn)
        else 
            print(obj)
        end
    else 
        local list=type(name)=="table"  and name or var.inputs
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
            local item=obj[3]
            if obj[1]=='userdata' and tostring(item):find('ResultSet') then 
                db.resultset:print(item,db.conn)
            else
                list[#list+1]={obj[2],item}
            end
        end
        if #list>1 then grid.print(list) end
    end
end

function var.onload()
    snoop('BEFORE_ORACLE_EXEC',var.before_db_exec)
    snoop('AFTER_ORACLE_EXEC' ,var.after_db_exec)
    cfg.init("PrintVar",'on',nil,"oracle","Max size of historical commands",'on,off')
    env.set_command(nil,{"variable","VAR"},var.helper,var.setOutput,false,3)
    env.set_command(nil,{"Print","pri"},'Displays the current values of bind variables(refer to command "VAR" and "DEF").Usage: print <variable|-a>',var.print,false,3)
    env.set_command(nil,{"Define","DEF"},"Define input variables, Usage: def <name>=<value>, or def <name> to remove definition",var.setInput,false,2)
end    
return var