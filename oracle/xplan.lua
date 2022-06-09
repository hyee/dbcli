local db,cfg=env.getdb(),env.set
local xplan={}
local default_fmt,e10053,prof,sqldiag="ALLSTATS ALL -ALIAS -PROJECTION OUTLINE REMOTE"
function xplan.explain(fmt,sql)
    local ora,sqltext=db.C.ora
    local _fmt=default_fmt
    local sql_id
    env.checkhelp(fmt)
    e10053,sqldiag=false

    env.checkerr(db.props and db.props.db_version,"Database is not connected!")
    if fmt:sub(1,1)=='-' then
        if not sql then return end
        fmt=fmt:sub(2)
        if fmt=='10053' then
            e10053,fmt=true,_fmt
            fmt=_fmt
        elseif fmt:lower()=="prof" then
            prof,fmt=true,_fmt
        elseif fmt:lower()=="diag" then
            env.checkerr(db:check_access('sys.v$sql_diag_repository',1),"You don't have access to sys.v$sql_diag_repository, operation is cancelled.")
            sqldiag,fmt=true,_fmt
        else
            fmt,sql_id=_fmt,fmt
        end
    else
        sql=fmt..(not sql and "" or " "..sql)
        fmt=_fmt
    end

    if db.props.version>=12 then
        fmt = 'adaptive '..fmt
    end

    sql=env.COMMAND_SEPS.match(sql)
    local sql1= sql:gsub("\r?\n","")
    
    if tonumber(sql1) then
        sql=sql1
        if sql=='-1' then return end
        sql_id=sql_id or sql
    elseif not sql1:match('(%s)') then
        sql=sql1
        sqltext=db:get_value([[SELECT /*INTERNAL_DBCLI_CMD*/ * FROM(SELECT sql_text from dba_hist_sqltext WHERE sql_id=:1 AND ROWNUM<2
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
    if e10053 then
        pcall(db.internal_call,db,[[alter session set "_fix_control"='16923858:5']])
        db:internal_call("ALTER SESSION SET tracefile_identifier='"..math.random(1e6).."' EVENTS='10053 trace name context forever, level 1'") 
    end
    local args={}
    sql=sql:gsub("(:[%w_$]+)",function(s) args[s:sub(2)]=""; return s end)
    sql_id=sql_id or loader:computeSQLIdFromText(sql)
    local is_tee=printer.tee_hdl
    try{function()
            if not tonumber(sql) then
                sql1="Explain PLAN SET STATEMENT_ID='INTERNAL_DBCLI_CMD' FOR "..sql
                if sqldiag then
                    sqldiag=loader:computeSQLIdFromText(sql1)
                    pcall(db.internal_call,db,[[alter session set "_sql_diag_repo_retain" = true]])
                    if not is_tee then env.printer.tee('sql_diag_'..sql_id..'.txt','') end
                end
                db:internal_call("DELETE PLAN_TABLE WHERE STATEMENT_ID='INTERNAL_DBCLI_CMD' AND TIMESTAMP<SYSDATE-1/144") 
                db:internal_call(sql1,args) 
            end
        end,
        function(err)
            if type(err)=="string" and err:find("ORA-00942",1,true) then
                env.raise("Unable to EXPLAIN the SQL due to the inaccessibility of its depending objects, please make sure you've switched to the correct schema.")
            else
                env.raise_error(err)
            end
        end,
        function(err)
            if sqldiag then 
                pcall(db.internal_call,db,[[alter session set "_sql_diag_repo_retain" = false]])
                if not err then
                    local msg="Explain SQL Id: "..sqldiag..'    Source SQL Id: '..sql_id
                    print(msg..'\n'..string.rep('=',#msg))
                    db:query([[/*INTERNAL_DBCLI_CMD dbcli_ignore*/
                        SELECT /*+ordered use_hash(a b)*/DISTINCT
                               a.child#,
                               min(a.repo#) over(partition by a.type,a.state,a.feature,a.reason) repo#,
                               count(1) over(partition by a.type,a.state,a.feature,a.reason) seens,
                               a.type,
                               a.state,
                               a.feature,
                               a.reason,
                               b.description feature_description,
                               C,E,S
                        FROM (
                            SELECT /*+no_merge ordered use_hash(a b)*/
                                   max(a.child_number) over() child#,
                                   a.type,
                                   a.sql_diag_repo_id repo#,
                                   a.feature,
                                   a.state,
                                   b.reason,
                                   b.compilation_origin C,
                                   b.execution_origin E,
                                   b.slave_origin S,
                                   a.child_number CN
                            FROM   v$sql_diag_repository a, v$sql_diag_repository_reason b
                            WHERE  a.sql_id = b.sql_id(+)
                            AND    a.child_number = b.child_number(+)
                            AND    a.sql_diag_repo_id = b.sql_diag_repo_id(+)
                            AND    a.sql_id = :sql_id) a,v$sql_feature b
                        WHERE cn=child#
                        AND   a.feature=b.sql_feature(+)
                        ORDER BY feature,repo#]],{sql_id=sqldiag})
                else
                    if not is_tee then env.printer.tee_after() end
                end
            end
        end}
    sql=[[
        WITH /*INTERNAL_DBCLI_CMD*/ sql_plan_data AS
        (SELECT /*+materialize*/
                a.*,
                qblock_name qb,
                replace(object_alias,'"') alias,
                @proj@,
                access_predicates ap,filter_predicates fp,search_columns sc,
                max(nvl2(other_xml,regexp_substr(regexp_substr(to_char(substr(other_xml,1,512)),'<info type="dop" note="y">\d+</info>'),'\d+')/1.1111,1)) over(partition by plan_id) dop
         FROM   (SELECT a.*, decode(parent_id,-1,id-1,parent_id) pid, dense_rank() OVER(ORDER BY TIMESTAMP DESC,plan_id DESC) seq FROM plan_table a WHERE STATEMENT_ID='INTERNAL_DBCLI_CMD') a
         WHERE  seq = 1
         ORDER  BY id),
        hierarchy_data AS
         (SELECT /*+CONNECT_BY_COMBINE_SW NO_CONNECT_BY_FILTERING*/
                 id, pid,qb,alias,io_cost,rownum r_,ap,fp,dop,nvl(nullif(sc,0),keys) sc,nvl2(rowsets,'R'||rowsets||nvl2(proj,'/P'||proj,''),proj) proj
          FROM   sql_plan_data
          START  WITH id = 0
          CONNECT BY PRIOR id = pid
          ORDER  SIBLINGS BY position desc,id DESC),
        ordered_hierarchy_data AS
         (SELECT /*+materialize*/A.*,
                CASE 
                    WHEN nvl(ap,sc) IS NOT NULL THEN 'A'
                END||CASE 
                    WHEN sc IS NOT NULL THEN sc
                    WHEN ap IS NOT NULL THEN 
                      (SELECT count(distinct regexp_substr(regexp_substr(replace(ap,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level),'".*"'))
                       FROM   dual
                       connect by regexp_substr(replace(ap,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level) IS NOT NULL)
                END||CASE 
                    WHEN fp IS NOT NULL THEN
                    (SELECT 'F'||count(distinct regexp_substr(regexp_substr(replace(fp,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level),'".*"'))
                     FROM dual
                     connect by regexp_substr(replace(fp,al),'([^.]|^)"([a-zA-Z0-9#_$]+)([^.]|$)"',1,level) IS NOT NULL) 
                END pred
           FROM(SELECT A.*,
                       '"'||regexp_substr(NVL(ALIAS,FIRST_VALUE(ALIAS IGNORE NULLs) OVER(ORDER BY r_ ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)),'[^@]+')||'".' al,
                       row_number() over(ORDER BY r_ DESC) AS OID,
                       MAX(id) over() AS maxid
                FROM   hierarchy_data A) a),
        xplan_data AS
         (SELECT /*+inline ordered use_nl(o) no_merge*/
                 x.r,
                 x.plan_table_output AS plan_table_output,
                 o.id,
                 o.pid,qb,alias,pred,proj,
                 o.oid,
                 o.maxid,
                 nvl(trim(dbms_xplan.format_number(CASE 
                     WHEN REGEXP_LIKE(x.plan_table_output,'(TABLE ACCESS [^|]*(FULL|SAMPLE)|INDEX .*FAST FULL)') THEN
                         greatest(1,floor(io_cost*nvl(dop*1.009,1)/@mbrc@)) 
                     ELSE
                         io_cost
                 END)),' ') blks,
                 COUNT(*) over() AS rc
            FROM   (SELECT rownum r,x.* FROM TABLE(dbms_xplan.display('PLAN_TABLE', NULL, '@fmt@', 'PLAN_ID=(select max(plan_id) from plan_table WHERE STATEMENT_ID=''INTERNAL_DBCLI_CMD'')')) x) x
            LEFT   OUTER JOIN ordered_hierarchy_data o
            ON     (o.id = CASE WHEN regexp_like(x.plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(x.plan_table_output, '[0-9]+')) END))
        select plan_table_output
        from   xplan_data
        model
            dimension by (r)
            measures (plan_table_output,id, maxid,pid,oid,rc,qb,alias,pred,proj,blks,
                      greatest(max(length(maxid)) over () + 3, 6) as csize,
                      nvl(greatest(max(length(pred)) over () + 3, 7),0) as psize,
                      nvl(greatest(max(length(qb)) over () + 3, 6),0) as qsize,
                      nvl(greatest(max(length(alias)) over () + 3, 8),0) as asize,
                      nvl(greatest(max(length(proj)) over () + 3, 7),0) as jsize,
                      greatest(max(length(blks)) over () + 2,7) bsize,
                      cast(null as varchar2(128)) as inject)
            rules sequential order (
                inject[r] = case
                      when plan_table_output[cv()] like '------%' then 
                           rpad('-', csize[cv()]+psize[cv()]+jsize[cv()]+qsize[cv()]+asize[cv()]+bsize[cv()]+1, '-') || '{PLAN}' 
                      when id[cv()+2] = 0 then
                           '|' || lpad('Ord ', csize[cv()]) || '{PLAN}'
                               || rpad(' Blks',bsize[cv()]-1)||'|'
                               || decode(psize[cv()],0,'',rpad(' Pred', psize[cv()]-1)||'|')
                               || lpad('Proj |', jsize[cv()]) 
                               || decode(qsize[cv()],0,'',rpad(' Q.B', qsize[cv()]-1)||'|')
                               || decode(asize[cv()],0,'',rpad(' Alias', asize[cv()]-1)||'|')
                      when id[cv()] is not null then
                           '|' || lpad(oid[cv()]||' ', csize[cv()]) || '{PLAN}'
                               || lpad(blks[cv()],bsize[cv()]-1)  ||'|'
                               || decode(psize[cv()],0,'',rpad(' '||pred[cv()], psize[cv()]-1)||'|')
                               || lpad(proj[cv()] || ' |', jsize[cv()]) 
                               || decode(qsize[cv()],0,'',rpad(' '||qb[cv()], qsize[cv()]-1)||'|')
                               || decode(asize[cv()],0,'',rpad(' '||alias[cv()] , asize[cv()]-1)||'|')
                      when plan_table_output[cv()] like 'Plan hash value%' then
                            'SQL Id: @sql@    {PLAN}'
                  end,
                plan_table_output[r] = case
                     when inject[cv()] is not null then
                          replace(inject[cv()], '{PLAN}',plan_table_output[cv()])
                     else plan_table_output[cv()]
                 end)
        order  by r]]
    sql=sql:gsub('@fmt@',fmt):gsub('@sql@',sql_id):gsub('@mbrc@',db.props.mbrc)
    sql=sql:gsub('@proj@',db.props.version>11.1 and 
          [[nullif(regexp_count(projection,'\[[A-Z0-9,]+\](,|$)'),0) proj,nvl2(access_predicates,0+regexp_substr(projection,'#keys=(\d+)',1,1,'i',1),null) keys,0+regexp_substr(projection,'rowset=(\d+)',1,1,'i',1) rowsets]] 
      or  [[(select nullif(count(1),0) from dual connect by regexp_substr(projection,'\[[A-Z0-9,]+\](,|$)',1,level) is not null) proj,nullif(0,0) keys,nullif(0,0) rowsets]])
    cfg.set("pipequery","off")
    --db:rollback()
    if e10053==true then
        db:internal_call("ALTER SESSION SET EVENTS='10053 trace name context off'")
        db:query(sql)
        oracle.C.tracefile.get_trace('default','64')
        db:internal_call("ALTER SESSION SET tracefile_identifier=''")
    else
        db:query(sql)
        if sqldiag then
            if not is_tee then env.printer.tee_after() end
        elseif prof==true then
            oracle.C.sqlprof.extract_profile(nil,'plan',sqltext)
        end
    end
    cfg.set("feed",feed,true)
end

function xplan.onload()
    local help=[[
    Explain SQL execution plan. Usage: @@NAME {[-<format>|-10053|-prof|diag] "<SQL Text>"|<SQL ID>}
    Options:
        -<format>: Refer to the 'format' field in the document of 'dbms_xplan'.
                       Default is ']]..default_fmt..[['
        -10053   : Generate the 10053 trace file after displaying the execution plan
        -prof    : Generate the SQL profile script after displaying the execution plan
        -diag    : Enable _sql_diag_repo_retain and print the result, refer to https://mauro-pagano.com/2017/07/30/sql-diag-repository/
    Parameters:
        <SQL Text> : SELECT/DELETE/UPDATE/MERGE/etc that can produce the execution plan
        <SQL ID>   : The SQL ID that can be found in SQL area or AWR history
    ]]
    env.set_command(nil,{"XPLAIN","XPLAN"},help,xplan.explain,'__SMART_PARSE__',3,true)
end

return xplan