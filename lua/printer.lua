local env=env

local writer=writer
local out=writer
local pro={rawprint=print}
local io=io
if not out then out=java.system.out end
function pro.print(...)	
	local output=""
	table.foreach({...},function(k,v) output=output..tostring(v)..' ' end)
	output=env.space..output:gsub("(\r?\n\r?)","%1"..env.space)
	 if writer then
        out:print("\27[39;49;0m")
    end
	out:println(output)
	out:flush()
	if pro.hdl then
		pcall(pro.hdl.write,pro.hdl,output.."\n")
	end
end

function pro.onunload()
	pro.print=pro.rawprint
	_G.print=pro.print
	if pro.hdl then
		pcall(pro.hdl.close,pro.hdl)
		pro.hdl=nil
		pro.file=file
	end
end

function pro.spool(file,option)
	option=option and option:upper() or "CREATE"
	if not file then
		if pro.hdl then 
			pro.rawprint(env.space..'Output is writing to "'..pro.file..'".') 
		else
			print("SPOOL is OFF.")
		end
		return
	end
	if file:upper()=="OFF" or option=="OFF" or pro.hdl then
		if pro.hdl then pcall(pro.hdl.close,pro.hdl) end
		pro.hdl=nil
		pro.file=nil
		if file:upper()=="OFF" or option=="OFF" then return end
	end
	local err
	if not file:find("[\\/]") then
		file=env.WORK_DIR..'cache'..env.PATH_DEL..file
	end
	pro.hdl,err=io.open(file,(option=="APPEND" or option=="APP" ) and "a+" or "w")
	if not pro.hdl then
		print("Failed to open the target file :"..file)
		return
	end
	pro.file=file
end

_G.print=pro.print
_G.rawprint=pro.rawprint
env.set_command(nil,{"Prompt","pro"}, "Prompt messages. Usage: PRO[MPT] <message>",pro.print,false,2)
env.set_command(nil,{"SPOOL","SPO"}, "Stores query results in a file. Usage: SPO[OL] [file_name[.ext]] [CRE[ATE]] | APP[END]] | OFF]",pro.spool,false,3)
return pro
