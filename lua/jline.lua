local rawget,env=rawget,env
local reader=reader
local file='jline.dat'
local jline={}
local cfg
local color=setmetatable({
	BLK = "\27[30m", -- Black 
	RED = "\27[31m", -- Red 
	GRN = "\27[32m", -- Green 
	YEL = "\27[33m", -- Yellow 
	BLU = "\27[34m", -- Blue 
	MAG = "\27[35m", -- Magenta
	CYN = "\27[36m", -- Cyan 
	WHT = "\27[37m", -- White

	GRAY=  "\27[1;30;40m", --BG Light gray
	DCY=  "\27[0;36m", --Dark Cyan



	HIR = "\27[31m", -- Light Red 
	HIG = "\27[1;32m", -- Light Green
	HIY = "\27[1;33m", -- Light Yellow 
	HIB = "\27[1;34m", -- Light Blue 
	HIM = "\27[1;35m", -- Light Magenta 
	HIC = "\27[1;36m", -- Light Cyan 
	HIW = "\27[1;37m", -- Light White
	DEF = "\27[39m", -- default FG color 

	--background color
	HBRED = "\27[41;1m", -- BG Light Red  
	HBGRN = "\27[42;1m", -- BG Light Green
	HBYEL = "\27[43;1m", -- BG Light Yellow 
	HBBLU = "\27[44;1m", -- BG Light Blue  
	HBMAG = "\27[45;1m", -- BG Light Magenta 
	HBCYN = "\27[46;1m", -- BG Light Cyan 
	HBWHT = "\27[47;1m", -- BG Light White
	HBBLK = "\27[40;1m", -- BG Light Black
	HBGRY=  "\27[0;37;47m", --BG Light gray

	BBLK = "\27[40m", -- BG Black
	BRED = "\27[41m", -- BG Red
	BGRN = "\27[42m", -- BG Green 
	BYEL = "\27[43m", -- BG Yellow
	BBLU = "\27[44m", -- BG Blue
	BMAG = "\27[45m", -- BG Magenta 
	BCYN = "\27[46m", -- BG Cyan 
	BDEF = "\27[49m", -- default BG color 

	NOR = "\27[39;49;0m", -- Reset 

	BOLD = "\27[1m", -- Bold
	UDL = "\27[3m", -- ITalics
	UDL = "\27[4m", -- Underline
	BLINK = "\27[5m", -- Blink 
	REV = "\27[7m", -- Reverse
	HIREV = "\27[1;7m", -- Revers and light color	
	HIDE = "\27[8m", -- Hidden
	

	CLR = "\27[2J", -- Clear Screen
	HOME = "\27[H", -- Send cursor back 
	REFCLR = "\27[2J;H", -- clean and reset cursor	
	SAVEC = "\27[s", -- Save cursor position 
	REST = "\27[u", -- Restore cursor to saved position 
	
	FRTOP = "\27[2;25r", -- Freeze first line
	FRBOT = "\27[1;24r", -- Freeze last line
	UNFR = "\27[r", -- Free 1st/last lines 
		
	},{
	__index=function(self,k)
		return rawget(self,k:upper())
	end
})

local reader,writer,str_completer,arg_completer,add=reader

function jline.cfg(name,value)
	if not cfg then cfg={} end
	if not name then return cfg end
	if not value then return cfg[name] end
	cfg[name]=value
end

function jline.mask(codes,msg,continue)	
	if not reader then
		return msg 
	end
	local str
	for v in codes:gmatch("([^;%s\t,]+)") do
		v=v:upper()
		if not color[v] then v=jline.cfg(v) or "" end
		if color[v] then
			if not str then
				str=color[v] 
			else
				str=str:gsub("([%d;]+)","%1;"..color[v]:match("([%d;]+)"),1)
			end
		end
	end
	return str and (str..msg..(continue and "" or color.NOR)) or msg
end

function jline.addCompleter(name,args)
	if not reader then return end
	if type(name)~='table' then
		name={tostring(name)}		
	end

	local c=str_completer:new(table.unpack(name))
	for i,k in ipairs(name) do name[i]=tostring(k):lower() end
	c=str_completer:new(table.unpack(name))
	reader:addCompleter(c)
	if type(args)=="table" then
		for i,k in ipairs(args) do args[i]=tostring(k):lower() end
		for i,k in ipairs(name) do
			c=arg_completer:new(str_completer:new(k,table.unpack(args)))
			reader:addCompleter(c)
		end
	end
end

function jline.clear_sceen()
	print(color.CLR)
	print(color.HOME)
	reader:flush()
end

function jline.define_color(name,value,module,description)
	if not value or not reader then return end
	name,value=name:upper(),value:upper()	
	env.checkerr(not color[name],"Cannot define color ["..name.."] as a name!")
	if jline.mask(value,"")=="" then
		env.raise("Undefined color code ["..value.."]!")
	end

	if not jline.cfg(name) or not description then
		jline.cfg(name,value)
	end

	if description then
		env.set.init(name,value,jline.define_color,module,description)
		if value ~= jline.cfg(name) then
			env.set.doset(name,jline.cfg(name))
		end
	else
		jline.cfg(name,value)
		return value
	end
end

function jline.get_color(name)
	if not name or not reader then return "" end
	name=name:upper()
	if color[name] then return color[name] end
	return jline.cfg(name) and jline.mask(jline.cfg(name),"",true) or ""	
end	

function jline.onload()
	if not reader then return end
	writer=reader:getOutput()
	--print(reader:getTerminal().ANSI)
	jline.loaded=true
	str_completer=java.require("jline.console.completer.StringsCompleter",true)
	arg_completer=java.require("jline.console.completer.ArgumentCompleter",true)
	env.set_command(nil,"<tab>","Type tab(\\t) for auto completion",nil,false,99)
	env.set_command(nil,{"clear","cls"},"Clear screen ",jline.clear_sceen,false,1)		
end

function jline.strip_ansi(str)
	return str:gsub("[\27\93]+%[[[%d%s;]m","")
end

function jline.strip_len(str)
	return #jline.strip_ansi(str)
end


return jline