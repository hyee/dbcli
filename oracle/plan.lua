local db,cfg=env.oracle,env.set
local function explain(sql)
	--sql=sql:gsub("(%w+)","%1 /*+gather_plan_statistics*/",1)
	local ora=db.C.ora
	sql=sql:gsub("(:[%w_$]+)",":V1")
	local feed=cfg.get("feed")
	cfg.set("feed","off",true)
	db:internal_call("alter session set statistics_level=all")
	db:exec("Explain PLAN /*INTERNAL_DBCLI_CMD*/ FOR "..sql,{V1=""})
	db:query("select /*INTERNAL_DBCLI_CMD*/ * from table(dbms_xplan.display('PLAN_TABLE',null,'ALLSTATS ALL -PROJECTION OUTLINE'))")
	db:rollback()
	cfg.set("feed",feed,true)
end
env.set_command(nil,"PLAN","Explain SQL execution plan. Usage: plan <DML statement>",explain,true,2)
return explain