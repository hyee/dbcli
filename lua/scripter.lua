local env=env
local grid,cfg=env.grid,env.set
local ARGS_COUNT=20
local cfg_backup

local scripter=env.class()

function scripter:ctor()
    self.script_dir,self.extend_dirs=nil,{}
    self.comment="/%*[\t\n\r%s]*%[%[(.*)%]%][\t\n\r%s]*%*/"
    self.command='sql'
    self.ext_name='sql'
    self.help_title=""
    self.help_ind=0
end

function scripter:trigger(func,...)
    if type(self[func])=="function" then
        return self[func](self,...)
    end
end

function scripter:format_version(version)
    return version:gsub("(%d+)",function(s) return s:len()<3 and string.rep('0',3-s:len())..s or s end)
end

function scripter:rehash(script_dir,ext_name)
    local keylist=env.list_dir(script_dir,ext_name or self.ext_name or "sql",self.comment)
    local cmdlist,pathlist={},{}
    local counter=0
    for k,v in ipairs(keylist) do
        local desc=v[3] and v[3]:gsub("^[\n\r%s\t]*[\n\r]+","") or ""
        desc=desc:gsub("%-%-%[%[(.*)%]%]%-%-",""):gsub("%-%-%[%[(.*)%-%-%]%]","")
        local cmd=v[1]:upper()
        if cmdlist[cmd] then 
            pathlist[cmdlist[cmd].path:lower()]=nil
        end
        cmdlist[cmd]={path=v[2],desc=desc,short_desc=desc:match("([^\n\r]+)") or ""}
        pathlist[v[2]:lower()]=cmd
        counter=counter+1
    end

    local additions={
        {'-R','Rebuild the help file and available commands'},
        {'-P','Verify the paramters/templates of the target script, instead of running it. Usage:  -p <cmd> [<args>]'},
        {'-H','Show the help detail of the target command. Usage:  -h <command>'},
        {'-S','Search available command with inputed keyword. Usage:  -s <keyword>'},
        {'@','Run scripts that not belongs to the "'..self.short_dir..'" directory.'},
    }

    for k,v in ipairs(additions) do
        cmdlist[v[1]]={desc=v[2],short_desc=v[2]}
    end

    cmdlist['./PATH'],cmdlist['./COUNT']=pathlist,counter 

    return cmdlist
end

--[[
Available parameters:
   Input bindings:  from :V1 to :V9
   Replacement:     from &V1 to &V9, used to replace the wildchars inside the SQL stmts
   Out   bindings:  :<alphanumeric>, the data type of output parameters should be defined in th comment scope
--]]-- 
function scripter:parse_args(sql,args,print_args)
    
    local outputlist={}
    local outputcount=0
        
    --parse template
    local patterns,options={"(%b{})","([^\n\r]-)%s*[\n\r]"},{}
    
    local desc
    sql=sql:gsub(self.comment,function(item) 
        desc=item:match("%-%-%[%[(.+)%]%]%-%-")
        if not desc then desc=item:match("%-%-%[%[(.*)%-%-%]%]") end    
        return "" 
    end,1)
        
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
                    local keys,default={}
                    for option,text in v:gmatch(sub_pattern) do
                        option,text=option:upper(),text:sub(2,-2)
                        default=default or option
                        if prefix~="@" then                                                   
                            if not options[option] then options[option]={} end
                            options[option][k]=text
                        else
                            keys[#keys+1]=option
                        end
                        templates[k][option]=text
                    end

                    if prefix=="@" then
                        env.checkerr(self.db:is_connect(),'Database is not connected!')
                        default=self:trigger('validate_accessable',k,keys,templates[k])
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

        for k,v in pairs(env.var.inputs) do
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

function scripter:run_sql(sql,args,print_args)
    if not self.db or not self.db.is_connect then 
        env.raise("Database connection is not defined!")
    end

    env.checkerr(self.db:is_connect(),"Database is not connected!")
    
    if print_args or not args then return end
    --remove comment
    sql=sql:gsub(self.comment,"",1)
    sql=('\n'..sql):gsub("\n[\t%s]*%-%-[^\n]*","")
    sql=('\n'..sql):gsub("\n%s*/%*.-%*/",""):gsub("/[\n\r\t%s]*$","")
    local sq="",cmd,params,pre_cmd,pre_params
    local cmds=env._CMDS
    
    cfg_backup=cfg.backup()
    cfg.set("HISSIZE",0)
    env.var.import_context(args)
    local eval=env.eval_line
    for line in sql:gsplit("[\n\r]+") do
        eval(line)
    end

    if env.pending_command() then
        env.force_end_input()
    end    
end

function scripter:get_script(cmd,args,print_args)
    if not self.cmdlist or cmd=="-r" or cmd=="-R" then
        self.cmdlist,self.extend_dirs=self:rehash(self.script_dir,self.ext_name),{}
        local keys={}
        for k,_ in pairs(self.cmdlist) do
            keys[#keys+1]=k
        end 
    end

    if not cmd then
        return env.helper.helper(self.command)
    end

    cmd=cmd:upper()

    if cmd:sub(1,1)=='-' and args[1]=='@' and args[2] then
        args[2]='@'..args[2]
        table.remove(args,1)
    elseif cmd=='@' and args[1] then 
        cmd=cmd..args[1]
        table.remove(args,1)
    end

    if cmd=="-R" then
        return
    elseif cmd=="-H" then
        return  env.helper.helper(self.command,args[1])
    elseif cmd=="-P" then
        cmd,print_args=args[1] and args[1]:upper() or "/",true
        table.remove(args,1)
    elseif cmd=="-S" then
        return env.helper.helper(self.command,"-S",table.unpack(args))
    end

    local file,f,target_dir
    if cmd:sub(1,1)=="@" then   
        target_dir,file=self:check_ext_file(cmd)
        env.checkerr(target_dir['./COUNT']>0,"Cannot find this script!")
        if not file then return env.helper.helper(self.command,cmd) end
        file=target_dir[file].path
    elseif self.cmdlist[cmd] then
        file=self.cmdlist[cmd].path
    end
    env.checkerr(file,"Cannot find this script!")
    
    local f=io.open(file)
    env.checkerr(f,"Cannot find this script!")
    local sql=f:read('*a')
    f:close()
    args=self:parse_args(sql,args,print_args)
    return sql,args,print_args
end

function scripter:run_script(cmd,...)
    local args,print_args,sql={...},false
    sql,args,print_args=self:get_script(cmd,args,print_args)
    if not args then return end
    self:run_sql(sql,args,print_args)
end

function scripter:after_script()
    if cfg_backup then
        cfg.restore(cfg_backup)
        cfg_backup=nil
    end
end

function scripter:check_ext_file(cmd)
    local target_dir
    cmd=cmd:lower():gsub('^@["%s]*(.-)["%s]*$','%1')
    target_dir=self.extend_dirs[cmd]
    
    if not target_dir then
        for k,v in pairs(self.extend_dirs) do
            if cmd:find(k,1,true) then
                target_dir=self.extend_dirs[k]
                break
            end
        end

        if not target_dir then
            if not cmd:match('[\\/]([^\\/]+)[\\/]') then env.raise('The target script cannot under root folder!') end
            self.extend_dirs[cmd]=self:rehash(cmd,self.ext_name)
            target_dir=self.extend_dirs[cmd]
        end
    end

    if env.file_type(cmd)=='folder' then
        --Remove the settings that only contains one file
        for k,v in pairs(self.extend_dirs) do
            if k:find(cmd,1,true) and v['./COUNT']==1 then
                self.extend_dirs[k]=nil
            end
        end
        return target_dir,nil 
    end
    cmd=cmd:match('([^\\/]+)$'):match('[^%.%s]+'):upper()
    return target_dir,cmd
end

function scripter:helper(_,cmd,search_key)
    local help,target_dir=""
    help=self.help_title ..' [<script_name>|-r|-p|-h|-s] [parameters]\nAvailable commands:\n=================\n'
    self.help_ind=self.help_ind+1
    if self.help_ind==2 and not self.cmdlist then
        self:run_script('-r')
    end
    target_dir=self.cmdlist

    if cmd and cmd:sub(1,1)=='@' then
        help=""
        target_dir,cmd=self:check_ext_file(cmd)
    end

    return env.helper.get_sub_help(cmd,target_dir,help,search_key)    
end

function scripter:__onload()
    env.checkerr(self.script_dir,"Cannot find the script dir for the '"..self.command.."' command!")
    self.db=self.db or env.db_core.__instance
    self.short_dir=self.script_dir:match('([^\\/]+)$')
    env.set_command(self,self.command, self.helper,{self.run_script,self.after_script},false,ARGS_COUNT+1)
end

return scripter