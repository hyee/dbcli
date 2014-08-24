--The encryption function is someway useless, however you may feel better by comparing to plain text :)

local string=string
local enc={}

local function rechar(str,offset)
	local byte=string.byte(str)
	return 	string.char(byte+offset<128 and byte+offset or byte)
end

function enc.encrypt_fun(func)
	local str=string.dump(func,true)
	local obj={}
	for i=1,#str,2 do
		obj[#obj+1]=rechar(str:sub(i,i),1)
	end
	for i=2,#str,2 do
		obj[#obj+1]=rechar(str:sub(i,i),1)
	end
	return "FUNC:"..table.concat(obj,"")
end

function enc.decrypt_fun(str)
	if str:sub(1,5)~= "FUNC:" then
		return
	end
	str=str:sub(6)
	local ind=#str
	local half,start=math.floor(ind/2),math.ceil(ind/2)
	local obj={}
	for i=1,half,1 do
		obj[#obj+1]=rechar(str:sub(i,i),-1)
		obj[#obj+1]=rechar(str:sub(i+start,i+start),-1)
	end
	if half~=start then
		obj[#obj+1]=rechar(str:sub(start,start),-1)
	end
	str=loadstring(table.concat(obj,""))
	return str
end

function enc.encrypt_str(str)
	local func=loadstring("return function() local tmp=[["..tostring({}).."]];return [["..str.."]] end")()
	return enc.encrypt_fun(func)
end

function enc.decrypt_str(str)
	return enc.decrypt_fun(str)()
end

return enc

