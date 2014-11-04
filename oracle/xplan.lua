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
	sql=[[
		WITH sql_plan_data AS
		 (SELECT /*INTERNAL_DBCLI_CMD*/*
		  FROM   (SELECT id, parent_id, plan_id, dense_rank() OVER(ORDER BY plan_id DESC) seq FROM plan_table)
		  WHERE  seq = 1
		  ORDER  BY id),
		qry AS
		 (SELECT DISTINCT PLAN_id FROM sql_plan_data),
		hierarchy_data AS
		 (SELECT id, parent_id
		  FROM   sql_plan_data
		  START  WITH id = 0
		  CONNECT BY PRIOR id = parent_id
		  ORDER  SIBLINGS BY id DESC),
		ordered_hierarchy_data AS
		 (SELECT id,
		         parent_id AS pid,
		         row_number() over(ORDER BY rownum DESC) AS OID,
		         MAX(id) over() AS maxid
		  FROM   hierarchy_data),
		xplan_data AS
		 (SELECT /*+ ordered use_nl(o) */
		           rownum AS r,
		           x.plan_table_output AS plan_table_output,
		           o.id,
		           o.pid,
		           o.oid,
		           o.maxid,
		           COUNT(*) over() AS rc
		  FROM   (SELECT *
		          FROM   qry,
		                 TABLE(dbms_xplan.display('PLAN_TABLE', NULL, '@fmt@', 'plan_id=' || qry.plan_id))) x
		  LEFT   OUTER JOIN ordered_hierarchy_data o
		  ON     (o.id = CASE
		             WHEN regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|') THEN
		              to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
		         END))
		select plan_table_output
		from   xplan_data
		model
		   dimension by (rownum as r)
		   measures (plan_table_output,
		             id,
		             maxid,
		             pid,
		             oid,
		             rc,
		             greatest(max(length(maxid)) over () + 3, 6) as csize,
		             cast(null as varchar2(128)) as inject)
		   rules sequential order (
		          inject[r] = case
		                         when id[cv()+1] = 0
		                         or   id[cv()+3] = 0
		                         or   id[cv()-1] = maxid[cv()-1]
		                         then rpad('-', csize[cv()]*2, '-')
		                         when id[cv()+2] = 0
		                         then '|' || lpad('Pid |', csize[cv()]) || lpad('Ord |', csize[cv()])
		                         when id[cv()] is not null
		                         then '|' || lpad(pid[cv()] || ' |', csize[cv()]) || lpad(oid[cv()] || ' |', csize[cv()]) 
		                      end, 
		          plan_table_output[r] = case
		                                    when inject[cv()] like '---%'
		                                    then inject[cv()] || plan_table_output[cv()]
		                                    when inject[cv()] is not null
		                                    then regexp_replace(plan_table_output[cv()], '\|', inject[cv()], 1, 2)
		                                    else plan_table_output[cv()]
		                                 END
		         )
		order  by r]]
	sql=sql:gsub('@fmt@',fmt)	
	db:query(sql)
	db:rollback()
	cfg.set("feed",feed,true)
end
env.set_command(nil,"XPLAN","Explain SQL execution plan. Usage: xplan [-format] <DML statement>",explain,true,3)
return explain