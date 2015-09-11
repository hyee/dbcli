local env=env
local grid,cfg=env.grid,env.set
local login={list={}}
local file="password.dat"
local packer=env.MessagePack
function login.load()
    login.list=env.load_data(file)
end

function login.save()
    if cfg.get("SaveLogin")=="off" then return end
    local list=env.load_data(file)
    local res,err=pcall(env.save_data,file,login.list)
    if not res then
        env.save_data(file,list)
        error(err)
    end
end

function login.generate_name(url,props)
    local url1=url
    url=url1:match("//([^&]+)")
    if not url then url=('@'..url1):match("@/?([^@]+)$") end

    url=url:gsub('([%.%:])([%w%-%_]+)',function(a,b)
        if a=='.' and b:match('^(%d+)$') then
            return a..b
        else
            return ''
        end
    end)
    return (props.user..'@'..url):lower()
end

function login.capture(db,url,props)
    local typ=env.set.get("database")

    login.load()
    url=login.generate_name(url,props)
    props.password,props.lastlogin=env.packer.pack_str(props.password),os.date()
    if not login.list[typ] then login.list[typ]={} end
    local list=login.list[typ]
    if list[url] then
        props.alias=list[url].alias
        props.ssh_link=list[url].ssh_link
        props.forwards=list[url].forwards
    end
    if type(db)=="string" then props.connect_object=db end
    list[url]=props
    login.save()
    return url
end

function login.search(id,filter,url_filter)
    if cfg.get("SaveLogin")=="off" then
        return print("Cannot login because the 'SaveLogin' option is 'off'!")
    end

    login.load()
    local typ=env.set.get("database")
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

    grid.add(hdl,{"#","Alias","Name","User","SSH Link","Url","Last Login"})


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
            if (not filter and not url_filter) or (k:find(filter or "",1,true)  and v.url:find(url_filter or "",1,true)) then
                counter=counter+1
                if counter==1 then account=k end
                grid.add(hdl,{ind,v.alias or "",k,v.user,v.ssh_link or "",v.url,v.lastlogin})
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

    if account then return list[account],account end
end


function login.trigger_login(...)
    local list,account=login.search(...)
    if not account then return end
    env.event.callback("TRIGGER_LOGIN",account,list)
end

function login.onload()
    env.event.snoop("TRIGGER_CONNECT",login.capture)
    cfg.init("SaveLogin","on",nil,"core","Determine if autosave logins.",'on,off')
    local help_login=[[
        Login with saved accounts. Usage: login [ -d | -a |<number|account_name>]
            login                     : list all saved a/c
            login -d <num|name|alias> : delete matched a/c
            login <num|name|alias>    : login a/c
            login -a <alias> <id|name>: set alias to an existing account]]
    env.set_command(nil,"login",help_login,login.trigger_login,false,3)
    login.load()
end

return login