local env=env
local grid,cfg=env.grid,env.set
local login={list={}}
local file="password.dat"
local packer=env.MessagePack
function login.load()    
    login.list=env.load_data(file)
end

function login.save()
    env.save_data(file,login.list)    
end

function login.capture(db,url,props)
    local typ,url1=db.type or "default",url
    if cfg.get("SaveLogin")=="off" then return end
    props.password,props.url,props.lastlogin=env.packer.pack_str(props.password),url,os.date()
    url=url1:match("(%/%/[^&]+)")
    if not url then url=url1:match("(@.+)$") end
    url=url:gsub('([%.%:])([%w%-%_]+)',function(a,b)
        if a=='.' and b:match('^(%d+)$') then
            return a..b
        else
            return ''
        end
    end)
    login.load()
    url=(props.user..url):lower()    
    if not login.list[typ] then login.list[typ]={} end
    local list=login.list[typ]
    if list[url] then props.alias=list[url].alias end
    list[url]=props    
    login.save()
end


function login.login(db,id,filter)
    if cfg.get("SaveLogin")=="off" then 
        return print("Cannot login because the 'SaveLogin' option is 'off'!")
    end
    
    login.load()
    local typ=db.type or "default"
    local list=login.list[typ]
    local alias,alist=nil,{}

    id=(id or ""):lower()
    if id=="" then id= nil end

    if not list then
        return print("No available logins for '"..(id or "").."' in group '"..typ.."'.")
    end

    local keys={}
    for k,v in pairs(list) do
        keys[#keys+1]=k
        alist[v.alias or ""]=k      
    end
    alist[""]=nil

    table.sort(keys,function(a,b) return a:upper()<b:upper() end)

    local account,counter,hdl=nil,0,grid.new()
    filter=id and id:sub(1,1)=='-'  and filter and filter:lower() or id
    
    grid.add(hdl,{"#","Alias","Name","User","Url","Last Login"})

    
    if id=="-a" then
        local a=env.parse_args(2,filter)
        alias,filter=a[1],a[2]
        if not filter then
            return print('Usage: login -a <alias> <id|name>')
        end
        if list[alias] then
           return print('Usage: Cannot specify an alias that has been used by a name.') 
        end
        if not alias:match('^[a-z][%w_%$]+$') then
            return print('Unexpected alias name "'..alias..'".')
        end
    end

    local nfilter=filter and tonumber(filter) or -1

    if keys[nfilter] then
        counter = 1
        account=keys[nfilter]
    elseif list[filter or ""]  or alist[filter or ""] then
        counter = 1
        account=alist[filter] or filter       
    else
        for ind,k in pairs(keys) do
            local v=list[k]
            if not filter or k:find(filter,1,true) then
                counter=counter+1
                if counter==1 then account=k end
                grid.add(hdl,{ind,v.alias or "",k,v.user,v.url,v.lastlogin})
                if id=="-d" then
                    list[k]=nil
                end
            end
        end
    end

    if id=="-d" then
        if account then list[account]=nil end
        login.save()
        return
    elseif alias and counter==1 then
        if alist[alias] then
            list[alist[alias]].alias=nil
        end    
        list[account].alias=alias
        login.save()
        return
    end

    if counter > 1 or not id or id=="-s" then
        grid.sort(hdl,1,true)
        grid.print(hdl)
        return
    end
    
    if  account then
        db:connect(list[account])
    end
end    


env.event.snoop("AFTER_DB_CONNECT",login.capture)
cfg.init("SaveLogin","on",nil,"db.core","Determine if autosave logins.",'on,off')
login.load()
return login