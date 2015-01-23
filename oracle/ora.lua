local env=env
local db,grid=env.oracle,env.grid
local cfg=env.set
local ora={script_dir=env.WORK_DIR.."oracle"..env.PATH_DEL.."ora"}
ora.comment="/%*[\t\n\r%s]*%[%[(.*)%]%][\t\n\r%s]*%*/"
local ARGS_COUNT=20
function ora.rehash(script_dir,ext_name)
    local keylist=env.list_dir(script_dir,ext_name or "sql",ora.comment)
    local cmdlist={}
    for k,v in ipairs(keylist) do
        local desc=v[3] and v[3]:gsub("^[\n\r%s\t]*[\n\r]+","") or ""
        desc=desc:gsub("%-%-%[%[(.*)%]%]%-%-",""):gsub("%-%-%[%[(.*)%-%-%]%]","")
        cmdlist[v[1]:upper()]={path=v[2],desc=desc,short_desc=desc:match("([^\n\r]+)") or ""}
    end

    local additions={
        {'-R','Reflash the help file and available commands'},
        {'-P','Verify the paramters/templates of the target script, instead of running it. Usage:  -p <cmd> [<args>]'},
        {'-H','Show the help detail of the target command. Usage:  -h <command>'},
        {'-S','Search available command with inputed keyword. Usage:  -s <keyword>'},
        {'@','Run scripts that not belongs to the "ora" directory. Usage:  -s <keyword>'},
    }

    for k,v in ipairs(additions) do
        cmdlist[v[1]]={desc=v[2],short_desc=v[2]}
    end    

    return cmdlist
end

--[[
Available parameters:
   Input bindings:  from :V1 to :V9
   Replacement:     from &V1 to &V9, used to replace the wildchars inside the SQL stmts
   Out   bindings:  :<alphanumeric>, the data type of output parameters should be defined in th comment scope
--]]-- 
function ora.parse_args(sql,args,print_args)
    
    local outputlist={}
    local outputcount=0
        
    --parse template
    local patterns,options={"(%b{})","([^\n\r]-)%s*[\n\r]"},{}
    
    local desc
    sql=sql:gsub(ora.comment,function(item) 
        desc=item:match("%-%-%[%[(.+)%]%]%-%-")
        if not desc then desc=item:match("%-%-%[%[(.*)%-%-%]%]") end    
        return "" 
    end,1)

    local function format_version(version)
        return version:gsub("(%d+)",function(s) return s:len()<3 and string.rep('0',3-s:len())..s or s end)
    end
        
    args=args or {}
    local orgs,templates={},{}
    
    local sub_pattern=('w_.$#/'):gsub('(.)',function(s) return '%'..s end)
    sub_pattern='(['..sub_pattern..']+)%s*=%s*(%b{})'

    local function setvalue(param,value,mapping)
        if not orgs[param] then orgs[param]={args[param] or ""} end
        args[param],orgs[param][2]=value,mapping and (param..'['..mapping..']') or ""
    end

    if desc then    
        --Parse the  &<V1-V30> and :<V1-V30> grammar, refer to ashtop.sql
        for _,p in ipairs(patterns) do
            for prefix,k,v in desc:gmatch('([&:@])([%w_]+)%s*:%s*'..p) do
                k=k:upper()                
                if not templates[k] then--same variable should not define twice
                    templates[k]={}
                    local check_flag,default,expect,expect_name=0
                    for option,text in v:gmatch(sub_pattern) do
                        option,text=option:upper(),text:sub(2,-2)
                        default=default and default or option
                        if prefix=="@" then                            
                            --check database version
                            if k=="CHECK_USER" then--check user
                                check_flag=3
                                expect_name="user"
                                if db.props.db_user ~= option and option~="DEFAULT" then default=nil end
                                expect=option
                            elseif k=="CHECK_ACCESS" then--objects are sep with the / symbol
                                check_flag=2
                                expect_name="access"
                                for obj in option:gmatch("([^/%s]+)") do
                                    if not db:check_obj(obj) then
                                        default=nil
                                        expect='the accesses to: '.. option
                                        break
                                    end
                                end
                            else--check version                                
                                local check_ver=option:match('^([%d%.]+)$')
                                if check_ver then
                                    check_flag=1
                                    expect_name="database version"
                                    local db_version=format_version(db.props.db_version or "8.0.0.0.0")
                                    if db_version<format_version(check_ver) then default=nil end
                                    expect=option
                                end
                            end
                        else
                            if not options[option] then options[option]={} end
                            options[option][k]=text
                        end
                        templates[k][option]=text
                    end

                    if not default and check_flag>0 then 
                        env.raise("This command doesn't support current %s %s, expected as %s!",
                            expect_name,
                            check_flag==1 and db.props.db_version 
                                or check_flag==2 and "rights"
                                or check_flag==3 and db.props.db_user,
                            expect)                            
                    end

                    templates[k]['@default']=default

                    if not k:match("^(V%d+)$") then
                        setvalue(k,templates[k][templates[k]['@default']],default)
                        templates[k]['@choose']=default
                    end                    
                end
            end
        end
    end

    --Start to assign template value to args
    for i=1,ARGS_COUNT do 
        args[i],args[tostring(i)],args["V"..i]=nil,nil,args["V"..i] or args[i] or args[tostring(i)] or ""
    end

    local arg1,ary={},{}
    for i=1,ARGS_COUNT do    
        local k,v="V"..i,args["V"..i]
        ary[i]=v        
        if v:sub(1,1)=="-"  then
            local idx,rest=v:sub(2):match("^([%w_]+)(.*)$")
            if idx then
                idx,rest=idx:upper(),rest:gsub('^"(.*)"$','%1')
                for param,text in pairs(options[idx] or {}) do
                    ary[i]=nil
                    local ary_idx=tonumber(param:match("^V(%d+)$"))
                    if args[param] and ary_idx then                    
                        ary[ary_idx]=nil                    
                        arg1[param]=text..rest
                    else
                        setvalue(param,text..rest,idx)
                    end

                    if templates[param] then
                        templates[param]['@choose']=idx
                    end
                end
            end      
        end    
    end

    for i=ARGS_COUNT,1,-1 do
        if not ary[i] then table.remove(ary,i) end
    end

    for i=1,ARGS_COUNT do
        local param="V"..i
        if arg1[param] then 
            table.insert(ary,i,arg1[param])
        end
        if ary[i]=="." then ary[i]="" end
        setvalue(param,ary[i] or "")
        local option=args[param]:upper()
        local template=templates[param]
        if args[param]=="" and template and not arg1[param] then
            setvalue(param,template[template['@default']] or "",template['@default'])
            template['@choose']=template['@default']
        else
            local idx,rest=option:match("^([%w_]+)(.*)$")
            if idx then
                idx,rest=idx:upper(),rest:gsub('^"(.*)"$','%1')               
                if options[idx] and options[idx][param] then
                    setvalue(param,options[idx][param]..rest,idx)            
                    template['@choose']=idx
                end
            end
        end
    end

    if print_args then
        local rows={{"Variable","Option","Default?","Choosen?","Value"}}
        local rows1={{"Variable","Origin","Mapping","Final"}}
        local keys={}
        for k,v in pairs(args) do
            keys[#keys+1]=k
        end

        table.sort(keys,function(a,b)
            local a1,b1=tostring(a):match("^V(%d+)$"),tostring(b):match("^V(%d+)$")
            if a1 and b1 then return tonumber(a1)<tonumber(b1) end
            if a1 then return true end
            if b1 then return false end
            if type(a)==type(b) then return a<b end
            return tostring(a)<tostring(b)
        end)

        local function strip(text)
            len=146
            text= (text:gsub("[\t%s\n\r]+"," ")):sub(1,len)
            if text:len()==len then text=text..' ...' end
            return text
        end

        for _,k in ipairs(keys) do
            local ind=0
            local new,template,org=args[k],templates[k],orgs[k] or {}
            if type(template)=="table" then
                local default,select=template['@default'],template['@choose']
                for option,text in pairs(template) do                    
                    if option~="@default" and option~="@choose" then
                        ind=ind+1
                        rows[#rows+1]={ind==1 and k or "",
                                       option,
                                       default==option and "Y" or "N",
                                       select==option and "Y" or "N",
                                       strip(text)}
                    end                
                end
                if #rows>1 then rows[#rows+1]={""} end
            end
            rows1[#rows1+1]={k,strip(org[1] or ""),(org[2] or ''),strip(new)}
        end

        for k,v in pairs(db.C.var.inputs) do
            if type(k)=="string" and k:upper()==k and type(v)=="string" then
                rows1[#rows1+1]={k,v,"cmd 'def'",v}
            end
        end

        print("Templates:\n================")
        --grid.sort(rows,1,true)
        grid.print(rows)

        print("\nInputs:\n================")
        grid.print(rows1)
    end
    return args
end

function ora.run_sql(sql,args,print_args)
    if not db:is_connect() then
        env.raise("database is not connected !")
    end
    args=ora.parse_args(sql,args,print_args)
    if print_args or not args then return end

    --remove comment
    sql=sql:gsub(ora.comment,"",1)
    sql=('\n'..sql):gsub("\n[\t%s]*%-%-[^\n]*","")
    sql=('\n'..sql):gsub("\n%s*/%*.-%*/",""):gsub("/[\n\r\t%s]*$","")
    local sq="",cmd,params,pre_cmd,pre_params
    local cmds=env._CMDS
    
    local backup=cfg.backup()
    cfg.set("HISSIZE",0)
    db.C.var.import_context(args)
    local eval=env.eval_line
    for line in sql:gsplit("[\n\r]+") do
        eval(line)
    end
    if env.pending_command() then
        eval("/")
    end

    cfg.restore(backup)
end

function ora.run_script(cmd,...)
    if not ora.cmdlist or cmd=="-r" or cmd=="-R" then
        ora.cmdlist=ora.rehash(ora.script_dir)
        local keys={}
        for k,_ in pairs(ora.cmdlist) do
            keys[#keys+1]=k
        end 
        env.ansi.addCompleter("ORA",keys)
    end

    if not cmd then
        return env.helper.helper("ORA")
    end

    cmd=cmd:upper()    
    local args,print_args={...},false
    if cmd=="-R" then
        return
    elseif cmd=="-H" then
        return  env.helper.helper("ORA",args[1])
    elseif cmd=="-P" then
        cmd,print_args=args[1] and args[1]:upper() or "/",true
        table.remove(args,1)
    elseif cmd=="-S" then
        return env.helper.helper("ORA","-S",...)
    elseif cmd:sub(1,1)=="@" then
        local file
        if cmd:len()>1 then
            file=cmd:sub(2):gsub('^"(.*)"$','%1')
        else
            file=args[1] 
            table.remove(args,1)
        end
        if not file then return end        
        if not file:match('(%.%w+)$') then file=file..'.sql' end
        local f=io.open(file)
        env.checkerr(f,"Cannot find this script '"..file.."'!")
        local sql=f:read('*a')
        f:close()
        return ora.run_sql(sql,args,print_args)
    end

    env.checkerr(ora.cmdlist[cmd],"Cannot find this script!")    
    local f=io.open(ora.cmdlist[cmd].path)
    env.checkerr(f,"Script file is missing during runtime!")
    local sql=f:read('*a')
    f:close()
    ora.run_sql(sql,args,print_args)
end

local help_ind=0
function ora.helper(_,cmd,search_key)    
    local help='Run SQL script under the "ora" directory. Usage: ora [<script_name>|-r|-p|-h|-s] [parameters]\nAvailable commands:\n=================\n'
    help_ind=help_ind+1
    if help_ind==2 and not ora.cmdlist then
        ora.run_script('-r')
    end
    return env.helper.get_sub_help(cmd,ora.cmdlist,help,search_key)    
end

function ora.onload()
    env.set_command(nil,"ora", ora.helper,ora.run_script,false,ARGS_COUNT+1)
end

return ora