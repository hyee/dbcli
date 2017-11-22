local env,rawset=env,rawset
local grid,cfg,db_core=env.grid,env.set,env.db_core
local ARGS_COUNT=20

local scripter=env.class()

function scripter:ctor()
    self.script_dir,self.extend_dirs=nil,{}
    self.comment="/%*%s*%[%[(.*)%]%]%s*%*/"
    self.command='sql'
    self.usage="[-r|-h|-s|-g] | {[-p|<name[,name2[...]]>] [parameters]}"
    self.ext_name='sql'
    self.help_title=""
    self.help_ind=0
    self.db=env.getdb()
end

function scripter:get_command()
    return type(self.command)=="table" and self.command[1] or self.command
end

function scripter:trigger(func,...)
    if type(self[func])=="function" then
        return self[func](self,...)
    end
end

function scripter:format_version(version)
    return version:gsub("(%d+)",function(s) return s:len()<3 and string.rep('0',3-s:len())..s or s end)
end

function scripter:rehash(script_dir,ext_name,extend_dirs)
    local dirs={script_dir}
    if type(extend_dirs)=="table" then
        for k,v in pairs(extend_dirs) do dirs[#dirs+1]=v end
    else
        dirs[#dirs+1]=extend_dirs
    end
    local abbrs={}
    
    local key_list=os.list_dir(dirs,ext_name or self.ext_name or "sql",nil,function(event,file)
        if event=='ON_SCAN' then return 32767 end
        if not file.data then return end
        local desc,annotation
        if type(self.comment)=="string" then
            desc=file.data:match(self.comment)
        elseif type(self.comment)=="function" then
            desc=self.comment(file.data)
        end
        desc=desc or ""
        local function set_annotation(s) annotation=s;return ""; end
        if desc~="" then
            desc=desc:gsub("%-%-%[%[(.*)%]%]%-%-",set_annotation):gsub("%-%-%[%[(.*)%-%-%]%]",set_annotation)
            desc=desc:gsub("([\n\r]+%s*)%-%-","%1  ")
            desc=desc:gsub("([\n\r]+%s*)REM","%1   ")
            desc=desc:gsub("([\n\r]+%s*)rem","%1   ")
            desc=desc:gsub("([\n\r]+%s*)#","%1   ")
        end
        local attrs={path=file.fullname,desc=desc,short_desc=desc:match("([^\n\r]+)") or ""}
        if annotation then 
            local alias=("\n"..annotation):match("\n%s*@ALIAS[ \t]*:[ \t]*(%S+)")
            if alias then
                local abbr=alias:upper():split('[,; ]+')
                attrs.abbr=table.concat(abbr,',')
                for x,y in ipairs(abbr) do
                    abbrs[y]=attrs
                end
            end
        end
        return attrs
    end)

    local cmdlist,pathlist=setmetatable(table.new(1,#key_list+10),{__index=abbrs}),table.new(1,#key_list)

    local counter=0
    for _,file in ipairs(key_list) do
        local cmd=file.shortname:upper()
        if cmdlist[cmd] then
            local old_cmd=cmdlist[cmd]
            pathlist[old_cmd.path:lower()]=nil
            for abbr,attrs in pairs(abbrs) do
                if attrs==old_cmd then abbrs[abbr]=nil end
            end
            counter=counter-1
        end
        rawset(cmdlist,cmd,file.data)
        rawset(pathlist,file.fullname:lower(),cmd)
        counter=counter+1
    end
    
    local additions={
        {'-R','Rebuild the help info and available commands'},
        {'-P','Verify the paramters/templates of the target script, instead of running it. Usage: @@NAME <command> [<args>]'},
        {'-H','Show the help detail of the target command. Usage: @@NAME <command>'},
        {'-G','Print the content of the specific command. Usage: @@NAME <command>'},
        {'-L','Link this command to an extended directory'..(self.extend_dirs and ('(current is '..self.extend_dirs..')') or '')..". Usage: @@NAME <directory>"},
        {'-S','Search available commands with inputed keyword. Usage: @@NAME <keyword>'},
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
   Replacement:     from &V1 to &V9, used to replace the wildcards inside the SQL stmts
   Out   bindings:  :<alphanumeric>, the data type of output parameters should be defined in th comment scope
--]]--
function scripter:parse_args(sql,args,print_args,extend_dirs)

    local outputlist={}
    local outputcount=0

    --parse template
    local patterns,options={"(%b{})","([^\n\r]-)%s*[\n\r]"},{}

    local desc
    sql=sql:gsub(self.comment,function(item)
        desc=item:match("%-%-%[%[(.*)%]%]%-%-")
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

                    if prefix=="@" and k~="ALIAS" then
                        self.db:assert_connect()
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
        args[i],args[tostring(i)],args["V"..i]=nil,nil,args["V"..i] or args[i] or args[tostring(i)] or db_core.NOT_ASSIGNED
    end

    local arg1,ary={},{}
    for i=1,ARGS_COUNT do
        local k,v,cnt="V"..i,tostring(args["V"..i])
        ary[i]=v
        if v:sub(1,1)=="-"  then
            local idx,rest=v:sub(2):match("^([%w_]+)(.*)$")
            if idx then
                idx,rest=idx:upper(),rest:gsub('^"(.*)"$','%1')
                for param,text in pairs(options[idx] or {}) do
                    ary[i]=nil
                    local ary_idx=tonumber(param:match("^V(%d+)$"))
                    text,cnt=text:replace('&0',rest,true)
                    if cnt==0 then text=text..rest end
                    if args[param] and ary_idx then
                        ary[ary_idx]=nil
                        arg1[param]=text
                    else
                        setvalue(param,text,idx)
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
        if ary[i]=="." then ary[i]=db_core.NOT_ASSIGNED end
        setvalue(param,ary[i] or db_core.NOT_ASSIGNED)
        local option=args[param]:upper()
        local template=templates[param]
        if args[param]==db_core.NOT_ASSIGNED and template and not arg1[param] then
            setvalue(param,template[template['@default']] or db_core.NOT_ASSIGNED,template['@default'])
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
        --args[i],args[tostring(i)]=nil,args[param]
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
            local len=146
            text= (text:gsub("%s+"," ")):sub(1,len)
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

local echo_stack={}
function scripter.set_echo(name,value)
    local current_thead,_,level=env.register_thread()
    if level>1 then current_thead=env.RUNNING_THREADS[level-1] end
    value=value:lower()
    if value=="on" then
        echo_stack[current_thead]=true
    else
        echo_stack[current_thead]=nil
    end
    return value
end

local eval,var=env.eval_line,env.var
function scripter:run_sql(sql,args,cmds)
    if type(sql)=="table" then
        for i=1,#sql do scripter.run_sql(self,sql[i],args[i],cmds[i]) end
        return;
    end

    if not self.db or not self.db.is_connect then
        env.raise("Database connection is not defined!")
    end
    --self.db:assert_connect()
    local current_thead,_,level=env.register_thread()
    local sq="",cmd,params,pre_cmd,pre_params
    local cmds=env._CMDS

    local ary=env.var.backup_context()
    var.import_context(args)
    
    local echo=cfg.get("echo"):lower()=="on"
    cfg.set("define","on")
    for line in sql:gsplit("[\n\r]+") do
        if echo_stack[current_thead] or (echo_stack[env.RUNNING_THREADS[1]] and level==2) then
            print(line) 
        end
        eval(line)
    end

    if env.pending_command() then
        env.force_end_input()
    end
    env.var.import_context(ary)
end


function scripter:get_script(cmd,args,print_args)
    if not self.cmdlist or cmd=="-r" or cmd=="-R" then
        self.cmdlist=self:rehash(self.script_dir,self.ext_name,self.extend_dirs)
        local list,keys={},{}
        for _,cmd in pairs(type(self.command)=="table" and self.command or {self.command}) do
            list[cmd],env.root_cmds[cmd]=keys,keys
        end

        for k,v in pairs(self.cmdlist) do
            keys[k]=type(v)=="table" and v.desc or nil
        end
        if env.IS_ENV_LOADED then console:setSubCommands(list) end
    end

    if not cmd or cmd:match('^%s*$') then
        return env.helper.helper(self:get_command())
    end
    local org=cmd
    cmd=cmd:trim():upper()

    if cmd:sub(1,1)=='-' and args[1]=='@' and args[2] then
        args[2]='@'..args[2]
        table.remove(args,1)
    elseif cmd=='@' and args[1] then
        cmd=cmd..args[1]
        table.remove(args,1)
    end
    local is_get=false
    if cmd=="-R" then
        return
    elseif cmd=="-H" then
        return  env.helper.helper(self:get_command(),args[1])
    elseif cmd=="-G" then
        env.checkerr(args[1],"Please specify the command name!")
        cmd,is_get=args[1] and args[1]:upper() or "/",true
    elseif cmd=="-L" then
        env.checkerr(args[1],"Please specify the directory!")
        env.checkerr(os.exists(args[1])=='directory' or args[1]:lower()=="default","No such directory: %s",args[1])
        self.extend_dirs=env.set.save_config(self.__className..".extension",args[1])
        self.cmdlist=self:rehash(self.script_dir,self.ext_name,self.extend_dirs)
        if self.extend_dirs then
            print("Extended directory is set to '"..self.extend_dirs.."', and will take higher priority than '"..self.script_dir.."'.")
        else
            print("Extended directory is removed.")
        end
        return
    elseif cmd=="-P" then
        cmd,print_args=args[1] and args[1]:upper() or "/",true
        table.remove(args,1)
    elseif cmd=="-S" then
        return env.helper.helper(self:get_command(),"-S",table.unpack(args))
    end

    local file,f,target_dir
    if cmd:sub(1,1)=="@" then
        target_dir,file=self:check_ext_file(org:sub(2))
        env.checkerr(target_dir['./COUNT']>0,"Cannot find script "..org:sub(2))
        if not file then return env.helper.helper(self:get_command(),org) end
        cmd,file=file,target_dir[file].path
    elseif self.cmdlist[cmd] then
        file=self.cmdlist[cmd].path
    end
    env.checkerr(file,'Cannot find script "'..cmd..'" under folder "'..self.short_dir..'".')

    local f=io.open(file)
    env.checkerr(f,"Cannot find this script!")
    local sql=f:read(10485760)
    f:close()
    if is_get then return print(sql) end
    args=self:parse_args(sql,args,print_args)
    return sql,args,print_args,file,cmd
end

function scripter:run_script(cmds,...)
    local g_cmd,g_sql,g_args,g_files,index={},{},{},{},0
    for cmd in (cmds or ""):gsplit(',',true) do
        if cmd:sub(1,1)~='@' and cmd:find(env.PATH_DEL,1,true) then cmd='@'..cmd end
        local sql,args,print_args,file=self:get_script(cmd~='' and cmd or nil,{...},false)
        --remove comment
        if sql then
            sql=sql:gsub(self.comment,"",1)
            sql=('\n'..sql):gsub("\n[\t ]*%-%-[^\n]*","")
            sql=('\n'..sql):gsub("\n%s*/%*.-%*/",""):gsub("/%s*$","")
        end
        if args and not print_args then
            index=index+1
            g_cmd[index],g_sql[index],g_args[index],g_files[index]=cmd,sql,args,file
        end
    end
    if index==0 then return end
    env.set.set("SQLTERMINATOR","default")
    env.register_thread()
    self:run_sql(g_sql,g_args,g_cmd,g_files)
end

function scripter:after_script()
    if self._backup_context then
        env.var.import_context(self._backup_context)
        self._backup_context=nil
    end
end

function scripter:check_ext_file(cmd)
    local exist,c=os.exists(cmd,self.ext_name)
    env.checkerr(exist=='file',"Cannot find this file: "..cmd)
    local target_dir=self:rehash(c,self.ext_name)
    c=c:match('([^\\/]+)$'):match('[^%.%s]+'):upper()
    return target_dir,c
end

function scripter:helper(_,cmd,search_key)
    local help,cmdlist=""
    help=('%sUsage: %s %s \nAvailable commands:\n=================\n'):format(self.help_title,self:get_command(),self.usage)
    if env.IS_ENV_LOADED and not self.cmdlist then
        self:run_script('-r')
    end
    cmdlist=self.cmdlist
    if cmd and cmd:sub(1,1)=='@' then
        help=""
        cmdlist,cmd=self:check_ext_file(cmd:sub(2))
    end
    --[[
    format of cmdlist:  {cmd1={short_desc=<brief help>,desc=<help detail>},
                         cmd2={short_desc=<brief help>,desc=<help detail>},
                         ...}
    ]]
    if not cmd or cmd=="-S" then
        if not cmdlist then return help end
        local rows={{},{}}
        local undocs=nil
        local undoc_index=0
        for k,v in pairs(cmdlist) do
            if type(v)=="table" and v.abbr then k=k..','..v.abbr end
            if (not search_key or k:find(search_key:upper(),1,true)) and k:sub(1,2)~='./' and k:sub(1,1)~='_' then
                if search_key or not (v.path or ""):find('[\\/]test[\\/]') then
                    local desc=v.short_desc:gsub("^[ \t]+",""):gsub("@@NAME","@@NAME "..k:lower())
                    if desc and desc~="" then
                        table.insert(rows[1],k)
                        table.insert(rows[2],desc)
                    else
                        local flag=1
                        if v.path and v.path:lower():find(env.WORK_DIR:lower(),1,true) then
                            local _,degree=v.path:sub(env.WORK_DIR:len()+1):gsub('[\\/]+','')
                            if degree>3 then flag=0 end
                        end

                        if flag==1  then
                            undoc_index=undoc_index+1
                            undocs=(undocs or '')..k..', '
                            if math.fmod(undoc_index,10)==0 then undocs=undocs..'\n' end
                        end
                    end
                end
            end
        end
        if(undocs) then
            undocs=undocs:gsub("[\n%s,]+$",'')
            table.insert(rows[1],'_Undocumented_')
            table.insert(rows[2],undocs)
        end
        env.set.set("PIVOT",-1)
        env.set.set("HEADDEL",":")
        help=help..grid.tostring(rows)
        env.set.restore("HEADDEL")
        return help
    end
    cmd = cmd:upper()
    return cmdlist[cmd] and cmdlist[cmd].desc or "No such command["..cmd.."] !",cmd
end

function scripter:__onload()
    --env.checkerr(self.script_dir,"Cannot find the script dir for the '"..self:get_command().."' command!")
    self.db=self.db or env.db_core.__instance
    self.short_dir=self.script_dir:match('([^\\/]+)$')
    self.extend_dirs=env.set.get_config(self.__className..".extension")
    loader:mkdir(self.script_dir)
    if not cfg.exists("echo") then cfg.init("echo","off",scripter.set_echo,"core","Controls whether the START command lists each command in a script as the command is executed.","on,off") end
    if self.command and self.command~="" then
        env.set_command{obj=self,cmd=self.command, 
                        help_func={self.help_title.." Type '@@NAME' for more detail.",self.helper},
                        call_func={self.run_script,self.after_script},
                        is_multiline=false,parameters=ARGS_COUNT+1,color="HEADCOLOR"
                        }
    end
    env.event.snoop("ON_SEARCH",function(dir) dir[#dir+1]=self.extend_dirs end)
    --env.uv.thread.new(function(o) if not o.cmdlist then o:run_script("-r") end end,self)
    if not self.cmdlist then self:run_script("-r") end
end

return scripter