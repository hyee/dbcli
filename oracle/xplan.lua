local db,cfg=env.getdb(),env.set
local xplan={}
local default_fmt,e10053,prof="ALLSTATS ALL -PROJECTION OUTLINE REMOTE"
function xplan.explain(fmt,sql)
    local ora,sqltext=db.C.ora
    local _fmt=default_fmt
    
    env.checkhelp(fmt)
    e10053=false
    if fmt:sub(1,1)=='-' then
        if not sql then return end
        fmt=fmt:sub(2)
        if fmt=='10053' then
            e10053,fmt=true,_fmt
            fmt=_fmt
        elseif fmt:lower()=="prof" then
            prof,fmt=true,_fmt
        end
    else
        sql=fmt..(not sql and "" or " "..sql)
        fmt=_fmt
    end

    if db.props.db_version>'12' then
        fmt = 'adaptive '..fmt
    end

    sql=env.COMMAND_SEPS.match(sql)

    if not sql:gsub("[\n\r]",""):match('(%s)') then
        sql=sql:gsub("[\n\r]","")
        sqltext=db:get_value([[SELECT * FROM(SELECT sql_text from dba_hist_sqltext WHERE sql_id=:1 AND ROWNUM<2
                               UNION ALL
                               SELECT sql_fulltext from gv$sqlarea WHERE sql_id=:1 AND ROWNUM<2) WHERE ROWNUM<2]],{sql})
        env.checkerr(sqltext,"Cannot find target SQL ID %s",sql)
        sql=sqltext
    else 
        sqltext=sql
    end
    
    local feed=cfg.get("feed")
    cfg.set("feed","off",true)
    cfg.set("printsize",9999,true)
    --db:internal_call("alter session set statistics_level=all")
    db:rollback()
    if e10053 then db:internal_call("ALTER SESSION SET EVENTS='10053 trace name context forever, level 1'") end
    local args={}
    sql=sql:gsub("(:[%w_$]+)",function(s) args[s:sub(2)]=""; return s end)
    try{function() db:internal_call("Explain PLAN SET STATEMENT_ID='INTERNAL_DBCLI_CMD' FOR "..sql,args) end,
        function(err)
            if type(err)=="string" and err:find("ORA-00942",1,true) then
                env.raise("Unable to EXPLAIN the SQL due to the inaccessibility of its depending objects, please make sure you've switched to the correct schema.")
            else
                env.raise_error(err)
            end
        end}
    sql=[[
        WITH /*INTERNAL_DBCLI_CMD*/ sql_plan_data AS
        (SELECT *
         FROM   (SELECT id, parent_id, plan_id, dense_rank() OVER(ORDER BY plan_id DESC) seq FROM plan_table WHERE STATEMENT_ID='INTERNAL_DBCLI_CMD')
         WHERE  seq = 1
         ORDER  BY id),
        qry AS (SELECT DISTINCT PLAN_id FROM sql_plan_data),
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
            FROM   (SELECT * FROM qry,TABLE(dbms_xplan.display('PLAN_TABLE', NULL, '@fmt@', 'plan_id=' || qry.plan_id))) x
            LEFT   OUTER JOIN ordered_hierarchy_data o
            ON     (o.id = CASE WHEN regexp_like(x.plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(x.plan_table_output, '[0-9]+')) END))
        select plan_table_output
        from   xplan_data
        model
             dimension by (rownum as r)
             measures (plan_table_output,id, maxid,pid,oid,rc,
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
                                                   end
                         )
        order  by r]]
    sql=sql:gsub('@fmt@',fmt)
    cfg.set("pipequery","off")
    db:query(sql)
    --db:rollback()
    if e10053==true then
        db:internal_call("ALTER SESSION SET EVENTS '10053 trace name context off'")
        oracle.C.tracefile.get_trace('default')
    elseif prof==true then
        oracle.C.sqlprof.extract_profile(nil,'plan',sqltext)
    end
    cfg.set("feed",feed,true)
end

function xplan.onload()
    local help=[[
    Explain SQL execution plan. Usage: @@NAME {[-<format>|-10053|-prof] <SQL statement|SQL ID>}
    Options:
            -<format>: Refer to the 'format' field in the document of 'dbms_xplan'.
                                 Default is ']]..default_fmt..[['
            -10053   : Generate the 10053 trace file after displaying the execution plan
            -prof    : Generate the SQL profile script after displaying the execution plan
    Parameters:
            <SQL Statement>: SELECT/DELETE/UPDATE/MERGE/etc that can produce the execution plan
            <SQL ID>       : The SQL ID that can be found in SQL area or AWR history
    ]]
    env.set_command(nil,{"XPLAIN","XPLAN"},help,xplan.explain,'__SMART_PARSE__',3,true)
end

return xplan