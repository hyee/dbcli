local env=env
local enc,grid,cfg=env.enc,env.grid,env.set
local password={list={}}
local file=env.WORK_DIR.."data"..env.PATH_DEL.."password.dat"
local packer=env.MessagePack
function password.load()
	packer.set_array("always_as_map")	
	local f=io.open(file)
	if not f then
		f=io.open(file,'w')
		if not f then error("Error: Unable to open "..file) end
		f:close()
		return
	end
	local txt=f:read("*a")	
	f:close()
	if not txt then return end
	password.list=packer.unpack(txt)
end

function password.save()
	packer.set_array("always_as_map")
	local txt=packer.pack(password.list)
	local f=io.open(file,'w')
	if not f then
		error("Error: Unable to open "..file)
	end
	f:write(txt)
	f:close()
end

function password.capture(db,url,props)
	local type=db.type or "default"
	if cfg.get("SaveLogin")=="off" then return end
	props.password,props.url,props.lastlogin=enc.encrypt_str(props.password),url,os.date()
	url=props.user..url:match("(@.+)$")
	if not password.list[type] then password.list[type]={} end
	password.list[type][url:lower()]=props
	password.save()
end


function password.login(db,id,filter)
	if cfg.get("SaveLogin")=="off" then 
		return print("Cannot login because the 'SaveLogin' option is 'off'!")
	end
	local type=db.type or "default"
	local list=password.list[type]
	id=(id or ""):lower()
	if id=="" then id= nil end

	if not list then
		return print("No available logins for '"..(id or "").."' in group '"..type.."'.")
	end
	local login
	
	local filter,counter=id and id:sub(1,1)=='-'  and filter and filter:lower() or id,0
	local hdl=grid.new()
	grid.add(hdl,{"Name","User","Url","LastLogin"})
	for k,v in pairs(list) do
		if not filter or k:find(filter,1,true) then
			counter=counter+1
			if counter==1 then login=k end
			grid.add(hdl,{k,v.user,v.url,v.lastlogin})
			if id=="-d" then
				list[k]=nil
			end
		end
	end

	if id=="-d" then
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
cfg.init("SaveLogin","off",nil,"db.core","Determine if autosave logins.",'on,off')
password.load()
return password