local env=env
local snoop,cfg,default_db=env.event.snoop,env.set,env.db
local flag = 1

local output={}
function output.setOutput(db)
	local flag=cfg.get("ServerOutput")
	local stmt="begin dbms_output."..(flag=="on" and "enable(null)" or "disable()")..";end;"
	pcall(function() (db or default_db):internal_call(stmt) end)
end

function output.getOutput(db,sql)
	if cfg.get("ServerOutput") == "off" then return end
	local stmt=[[	
	DECLARE/*INTERNAL_DBCLI_CMD*/
	    l_line   VARCHAR2(255);
	    l_done   PLS_INTEGER;
	    l_buffer VARCHAR2(32767);
	BEGIN
	    LOOP	        
	        dbms_output.get_line(l_line, l_done);
	        EXIT WHEN length(l_buffer) + 255 > 32500 OR l_done = 1;
	        l_buffer := l_buffer || l_line || chr(10);
	    END LOOP;
	    :1 := l_buffer;
	END;]]
	if not db:is_internal_call(sql) then
		local args={"#VARCHAR"}
		db:internal_call(stmt,args)		
		if args[1] and args[1]:match("[^\n%s]+") then
			local result=args[1]:gsub("[\n\r]","\n")
			print(result)
		end
	end	
end

snoop("AFTER_ORACLE_CONNECT",output.setOutput)
snoop("AFTER_ORACLE_EXEC",output.getOutput,nil,1)

cfg.init("ServerOutput",
	"on",
	function(name,value)		
		setOutput(nil)
		return value
	end,
	"oracle",
	"Print Oracle dbms_output after each execution",
	"on,off")

return output