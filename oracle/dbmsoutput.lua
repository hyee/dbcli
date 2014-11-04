local env=env
local snoop,cfg,default_db=env.event.snoop,env.set,env.db
local flag = 1

local output={}
local prev_transaction

function output.setOutput(db)
	local flag=cfg.get("ServerOutput")
	local stmt="begin dbms_output."..(flag=="on" and "enable(null)" or "disable()")..";end;"
	pcall(function() (db or default_db):internal_call(stmt) end)
end

function output.getOutput(db,sql)
	local stmt=[[	
			DECLARE/*INTERNAL_DBCLI_CMD*/
			    l_line   VARCHAR2(32767);
			    l_done   PLS_INTEGER:=32767;
			    l_buffer VARCHAR2(32767);	 
			    l_arr    dbms_output.chararr;   
			BEGIN
			    dbms_output.get_lines(l_arr,l_done);
			    for i in 1..l_done loop
			    	l_buffer := l_buffer || l_arr(i) || chr(10);
			    	exit when lengthb(l_buffer) + 255 > 32400;
			    end loop;	   
			    :1 := l_buffer;
			    :2 := dbms_transaction.local_transaction_id;
			END;]]
	if not db:is_internal_call(sql) then
		local args={"#VARCHAR","#VARCHAR"}
		db:internal_call(stmt,args)		
		if args[1] and args[1]:match("[^\n%s]+") and cfg.get("ServerOutput") == "on" then
			local result=args[1]:gsub("[\n\r]","\n")
			print(result)
		end

		if prev_transaction~=args[2] then
			prev_transaction = args[2]
			local addtional_title=prev_transaction and ("    TXN_ID: "..prev_transaction) or ""
			env.set_title(db.session_title..addtional_title)
		end
	end	
end

snoop("AFTER_ORACLE_CONNECT",output.setOutput)
snoop("AFTER_ORACLE_EXEC",output.getOutput,nil,1)

cfg.init("ServerOutput",
	"on",
	function(name,value)		
		output.setOutput(nil)
		return value
	end,
	"oracle",
	"Print Oracle dbms_output after each execution",
	"on,off")

return output