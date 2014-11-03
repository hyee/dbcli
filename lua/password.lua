local env=env
local grid,cfg=env.grid,env.set
local password={list={}}
local file="password.dat"
local packer=env.MessagePack
function password.load()	
	password.list=env.load_data(file)
end

function password.save()
    env.save_data(file,password.list)	
end

function password.capture(db,url,props)
	local type=db.type or "default"
	if cfg.get("SaveLogin")=="off" then return end
	props.password,props.url,props.lastlogin=env.packer.pack_str(props.password),url,os.date()
	url=props.user..url:match("(@.+)$")
	if not password.list[type] then password.list[type]={} end
	password.list[type][url:lower()]=props	
	password.save()
end


function password.login(db,id,filter)
	if cfg.get("SaveLogin")=="off" then 
		return print("Cannot login because the 'SaveLogin' option is 'off'!")
	end
	local typ=db.type or "default"
	local list=password.list[typ]

	id=(id or ""):lower()
	if id=="" then id= nil end

	if id=="-r" then
		return password.load()
	end

	if not list then
		return print("No available logins for '"..(id or "").."' in group '"..typ.."'.")
	end

	local keys={}
	for k,_ in pairs(list) do
		keys[#keys+1]=k		
	end
	table.sort(keys,function(a,b) return a:upper()<b:upper() end)

	local login,counter,hdl=nil,0,grid.new()
	filter=id and id:sub(1,1)=='-'  and filter and filter:lower() or id
	
	grid.add(hdl,{"#","Name","User","Url","LastLogin"})

	if keys[filter and tonumber(filter) or -1] then
		counter = 1
		login=keys[tonumber(filter)]
	elseif list[filter or ""] then
		counter = 1
		login=filter		
	else
		for ind,k in pairs(keys) do
			local v=list[k]
			if not filter or k:find(filter,1,true) then
				counter=counter+1
				if counter==1 then login=k end
				grid.add(hdl,{ind,k,v.user,v.url,v.lastlogin})
				if id=="-d" then
					list[k]=nil
				end
			end
		end
	end

	if id=="-d" then
		if login then list[login]=nil end
		password.save()
		return
	end

	if counter > 1 or not id or id=="-s" then
		grid.sort(hdl,1,true)
		grid.print(hdl)
		return
	end
	
	if  login then
		db:connect(list[login])
	end
end	


env.event.snoop("AFTER_DB_CONNECT",password.capture)
cfg.init("SaveLogin","on",nil,"db.core","Determine if autosave logins.",'on,off')
password.load()
return password