local db,cfg=env.oracle,env.set
local function explain(fmt,sql)
    local ora=db.C.ora
    local default_fmt,e10053="ALLSTATS ALL -PROJECTION OUTLINE"
    if not fmt then return end
    if fmt:sub(1,1)=='-' then        
        if not sql then return end
        fmt=fmt:sub(2)
        if fmt=='10053' then
           e10053=true           
           fmt=default_fmt
        end
    else
        sql=fmt..(not sql and "" or " "..sql)
        fmt=default_fmt
    end

    if not sql:gsub("[\n\r]",""):match('(%s)') then
        sql=sql:gsub("[\n\r]","")
        sql=db:get_value([[SELECT * FROM(SELECT sql_text from dba_hist_sqltext WHERE sql_id=:1 AND ROWNUM<2
                      UNION ALL
                      SELECT sql_fulltext from gv$sqlarea WHERE sql_id=:1 AND ROWNUM<2) WHERE ROWNUM<2]],{sql})
        if not sql or sql=="" then return end
    end
    local args={}
    sql=sql:gsub("(:[%w_$]+)",function(s) args[s:sub(2)]=""; return s end)
    local feed=cfg.get("feed")
    cfg.set("feed","off",true)
    cfg.set("printsize",9999,true)
    --db:internal_call("alter session set statistics_level=all")
    if e10053 then db:internal_call("ALTER SESSION SET EVENTS='10053 trace name context forever, level 1'") end
    db:internal_call("Explain PLAN /*INTERNAL_DBCLI_CMD*/ FOR "..sql,args)
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
    if e10053==true then
        db:internal_call("ALTER SESSION SET EVENTS '10053 trace name context off'")
        oracle.C.tracefile.get_trace('default')
    end
end
env.set_command(nil,"XPLAN","Explain SQL execution plan. Usage: xplan [-format|-10053] <DML statement|SQL ID>",explain,true,3)
return explain