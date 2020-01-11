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

    env.checkerr(db.props and db.props.db_version,"Database is not connected!")

    if db.props.version>11 then
        fmt = 'adaptive '..fmt
    end

    sql=env.COMMAND_SEPS.match(sql)
    local sql1= sql:gsub("\r?\n","")
    if not sql1:match('(%s)') then
        sql=sql1
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
        (SELECT a.*,
                qblock_name qb,
                object_alias alias,
                @proj@ proj,
                nvl2(access_predicates,'A','')||nvl2(filter_predicates,'F','')||NULLIF(search_columns,0) pred
         FROM   (SELECT a.*, decode(parent_id,-1,id-1,parent_id) pid, dense_rank() OVER(ORDER BY plan_id DESC) seq FROM plan_table a WHERE STATEMENT_ID='INTERNAL_DBCLI_CMD') a
         WHERE  seq = 1
         ORDER  BY id),
        hierarchy_data AS
         (SELECT id, pid,qb,alias,pred,proj
            FROM   sql_plan_data
            START  WITH id = 0
            CONNECT BY PRIOR id = pid
            ORDER  SIBLINGS BY id DESC),
        ordered_hierarchy_data AS
         (SELECT id,
                 pid,qb,alias,pred,proj,
                 row_number() over(ORDER BY rownum DESC) AS OID,
                 MAX(id) over() AS maxid
            FROM   hierarchy_data),
        xplan_data AS
         (SELECT /*+materialize ordered use_nl(o) */
                 x.r,
                 x.plan_table_output AS plan_table_output,
                 o.id,
                 o.pid,qb,alias,pred,proj,
                 o.oid,
                 o.maxid,
                 COUNT(*) over() AS rc
            FROM   (select rownum r,x.* from (SELECT * FROM TABLE(dbms_xplan.display('PLAN_TABLE', NULL, '@fmt@', 'PLAN_ID=(select max(plan_id) from plan_table WHERE STATEMENT_ID=''INTERNAL_DBCLI_CMD'')'))) x) x
            LEFT   OUTER JOIN ordered_hierarchy_data o
            ON     (o.id = CASE WHEN regexp_like(x.plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(x.plan_table_output, '[0-9]+')) END))
        select plan_table_output
        from   xplan_data
        model
            dimension by (rownum as r)
            measures (plan_table_output,id, maxid,pid,oid,rc,qb,alias,pred,proj,
                      greatest(max(length(maxid)) over () + 3, 6) as csize,
                      nvl(greatest(max(length(pred)) over () + 3, 7),0) as psize,
                      nvl(greatest(max(length(qb)) over () + 3, 6),0) as qsize,
                      nvl(greatest(max(length(alias)) over () + 3, 8),0) as asize,
                      nvl(greatest(max(length(proj)) over () + 3, 7),0) as jsize,
                      cast(null as varchar2(128)) as inject)
            rules sequential order (
                inject[r] = case
                      when plan_table_output[cv()] like '------%' then rpad('-', csize[cv()]+psize[cv()]+jsize[cv()]+qsize[cv()]+asize[cv()]+1, '-')
                      when id[cv()+2] = 0
                      then '|' || lpad('Ord ', csize[cv()]) || '{PLAN}' 
                               || lpad('Pred |', psize[cv()]) 
                               || lpad('Proj |', jsize[cv()]) 
                               || lpad('Q.B |', qsize[cv()])  
                               || lpad('Alias |', asize[cv()]) 
                      when id[cv()] is not null
                      then '|' || lpad(oid[cv()]||' ', csize[cv()]) || '{PLAN}'  
                               || lpad(pred[cv()] || ' |', psize[cv()]) 
                               || lpad(proj[cv()] || ' |', jsize[cv()]) 
                               || lpad(qb[cv()] || ' |', qsize[cv()])
                               || lpad(alias[cv()] || ' |', asize[cv()]) 
                  end,
                plan_table_output[r] = case
                     when inject[cv()] like '---%'
                     then inject[cv()] || plan_table_output[cv()]
                     when inject[cv()] is not null
                     then replace(inject[cv()], '{PLAN}',plan_table_output[cv()])
                     else plan_table_output[cv()]
                 END)
        order  by r]]
    sql=sql:gsub('@fmt@',fmt)
    sql=sql:gsub('@proj@',db.props.version>10 and [[nvl2(projection,1+regexp_count(regexp_replace(projection,'\[.*?\]'),', "'),null)]] or 'cast(null as number)')
    cfg.set("pipequery","off")
    --db:rollback()
    if e10053==true then
        db:internal_call("ALTER SESSION SET EVENTS '10053 trace name context off'")
        db:query(sql)
        oracle.C.tracefile.get_trace('default')
    elseif prof==true then
        db:query(sql)
        oracle.C.sqlprof.extract_profile(nil,'plan',sqltext)
    else
        db:query(sql)
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