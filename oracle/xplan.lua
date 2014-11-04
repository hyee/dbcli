local db,cfg=env.oracle,env.set
local function explain(fmt,sql)
	--sql=sql:gsub("(%w+)","%1 /*+gather_plan_statistics*/",1)
	local ora=db.C.ora
	if not fmt then return end
	if fmt:sub(1,1)=='-' then
		fmt=fmt:sub(2)
		if not sql then return end
	else
		sql=fmt.." "..(sql or "")
		fmt="ALLSTATS ALL -PROJECTION OUTLINE"
	end
	sql=sql:gsub("(:[%w_$]+)",":V1")
	local feed=cfg.get("feed")
	cfg.set("feed","off",true)
	db:internal_call("alter session set statistics_level=all")
	db:exec("Explain PLAN /*INTERNAL_DBCLI_CMD*/ FOR "..sql,{V1=""})
	db:query("select /*INTERNAL_DBCLI_CMD*/ * from table(dbms_xplan.display('PLAN_TABLE',null,'"..fmt.."'))")
	db:rollback()
	cfg.set("feed",feed,true)
end
env.set_command(nil,"XPLAN","Explain SQL execution plan. Usage: xplan [-format] <DML statement>",explain,true,3)
return explain