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
    url=url:gsub('[%.%:]([%w%-%_]+)','')
	url=props.user..url    
	if not login.list[typ] then login.list[typ]={} end
	login.list[typ][url:lower()]=props	
	login.save()
end


function login.login(db,id,filter)
	if cfg.get("SaveLogin")=="off" then 
		return print("Cannot login because the 'SaveLogin' option is 'off'!")
	end
	local typ=db.type or "default"
	local list=login.list[typ]

	id=(id or ""):lower()
	if id=="" then id= nil end

	if id=="-r" then
		return login.load()
	end

	if not list then
		return print("No available logins for '"..(id or "").."' in group '"..typ.."'.")
	end

	local keys={}
	for k,_ in pairs(list) do
		keys[#keys+1]=k		
	end
	table.sort(keys,function(a,b) return a:upper()<b:upper() end)

	local account,counter,hdl=nil,0,grid.new()
	filter=id and id:sub(1,1)=='-'  and filter and filter:lower() or id
	
	grid.add(hdl,{"#","Name","User","Url","LastLogin"})

	if keys[filter and tonumber(filter) or -1] then
		counter = 1
		account=keys[tonumber(filter)]
	elseif list[filter or ""] then
		counter = 1
		account=filter		
	else
		for ind,k in pairs(keys) do
			local v=list[k]
			if not filter or k:find(filter,1,true) then
				counter=counter+1
				if counter==1 then account=k end
				grid.add(hdl,{ind,k,v.user,v.url,v.lastlogin})
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