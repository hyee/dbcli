/*[[Search for the SQLs in AWR snapshots that reference the specific object. Usage: @@NAME <name|obj#|dataobj#> [<sort_by>] [yymmddhhmi] [yymmddhhmi] 
    <sort_by>: Sort the records with specific order, available options:
        ela  : elapsed time (default)
        exe  : executions
        id   : sql_id
        text : sql_text
        op   : operation name
    -phf     : group by plan_hash_full instead of plan_hash_value
    -g       : query gv$ views instead of dba_hist_ views
    --[[
        &V3  : default={&starttime}
        &V4  : default={&endtime}
        @ARGS: 1
        @11G : 11.2={} DEFAULT={--}
        @12c : 19.1={} DEFAULT={--}
        @CON : 12.1={,CON_DBID} DEFAULT={}
        &phf:  default={plan_hash} phf={plan_full}
        &typ:  d={d} g={g}
        &seg : {
                    d={(select * from &check_access_pdb.Seg_stat_obj where DBID='&dbid')}
                    g={(select a.*,&dbid dbid,object_id obj#,data_object_id dataobj# from all_objects a)}
            }
        &plan: d={&check_access_pdb.SQL_PLAN} g={(select &dbid dbid,a.* from gv$sql_plan a)}
        @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_}
    ]]--
]]*/

set printsize 100 feed off
COL "SEG|SCANS,IM|SCANS,BUFF|READS,BUFF|BUSY,PHY_RD|REQS,PHY_OPT|READS,PHY|READS,PHY_WR|REQS,PHY|WRITES" FOR TMB
COL "BLOCK|CHANGES,BLOCK|IM-CHG,GC-BUF|BUSY,GC-CR|BLKS,GC-CU|BLKS,ITL|WAITS,ROW_LK|WAITS,REMOTE|GRANTS,CHAIN_ROW|EXCESS,EXECS" FOR TMB
COL "SPACE|USED,SPACE|ALLOC,IM|MEM" FOR KMG
COL "PHY_OPT|READS,READS|DIRECT,WRITES|DIRECT,Weight" FOR PCT2
COL TIME smhd2
COL TOTAL_ELA,AVG_ELA FOR usmhd2
var c1 refcursor;
var c2 refcursor;
DECLARE
    xml   xmltype;
    stmt  VARCHAR2(32767);
BEGIN
    stmt := q'~
        WITH plans AS(
            SELECT a.*
            FROM   &plan a
            WHERE  upper('&V1') IN(a.object_name,''||a.object#,a.object_owner||'.'||a.object_name)
            AND    a.dbid='&dbid'
        )
        SELECT a.dbid,
               a.id,
               a.sorttype,
               a.sq_id,
               a.plan_full,
               a.plan_hash,
               a.obj,
               a.object_name,
               a.options,
               a.operation,
               substr(a.preds||nvl2(b.sql_id,'Join  Filter: '||nvl(b.access_predicates,b.filter_predicates),''),1,3500) join_preds
        FROM (
            SELECT row_number() OVER(PARTITION BY dbid,sq_id,plan_hash_value,id ORDER BY flag) seq_,
                   a.dbid,
                   a.id,
                   parent_,
                   nvl(lower(''),'total') sorttype,
                   sq_id,
                   sql_id,
                   plan_full,
                   a.plan_hash_value plan_hash,
                   a.object# obj,
                   a.object_name,
                   a.options,a.operation,
                   CASE WHEN prefix = 'Table' AND flag=1 THEN
                            decode(b_options,
                                    'FULL SCAN',
                                    'FFS',
                                    'RANGE SCAN',
                                    'RS',
                                    'UNIQUE SCAN',
                                    'US',
                                    'RANGE SCAN DESCENDING',
                                    'RSD',
                                    'TO ROWIDS',
                                    'BITMAP',
                                    b_options)||'('||nvl(b_search_columns,0) || '): ' || b_object_name
                        WHEN prefix = 'Index' AND flag=1 THEN
                            decode(a.options,
                                    'FULL SCAN',
                                    'FFS',
                                    'RANGE SCAN',
                                    'RS',
                                    'UNIQUE SCAN',
                                    'US',
                                    'RANGE SCAN DESCENDING',
                                    'RSD',
                                    'TO ROWIDS',
                                    'BITMAP',
                                    a.options)||'('||nvl(a.search_columns,0) || '): ' || b_object_name
                   ELSE a.options END op,
                   replace(CASE WHEN a.access_predicates IS NOT NULL THEN nvl(prefix,'Table')||' Access: '||substr(a.access_predicates,1,800)||chr(10) END ||
                           CASE WHEN a.filter_predicates IS NOT NULL THEN nvl(prefix,'Table')||' Filter: '||substr(a.filter_predicates,1,800)||chr(10) END ||
                           CASE WHEN b_access_predicates IS NOT NULL AND flag=1 THEN decode(prefix,'Index','Table','Index')||' Access: '||substr(b_access_predicates,1,800)||chr(10) END ||
                           CASE WHEN b_filter_predicates IS NOT NULL AND flag=1 THEN decode(prefix,'Index','Table','Index')||' Filter: '||substr(b_filter_predicates,1,800)||chr(10) END
                        ,'"') preds
            FROM (
                SELECT  /*+outline_leaf use_hash(a b) */
                        a.*,
                        least(b.parent_id,a.parent_id) parent_,
                        decode(a.plan_hash_value,0,a.sql_id) sq_id,
                        nvl(max(0+nvl2(b.other_xml,nullif(to_char(regexp_substr(b.other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'0'),'')) OVER(PARTITION BY a.dbid,a.plan_hash_value),a.plan_hash_value) plan_full,
                        b.access_predicates b_access_predicates,
                        b.filter_predicates b_filter_predicates,
                        b.options b_options,
                        b.object_name b_object_name,
                        b.search_columns b_search_columns,
                        CASE WHEN a.id!=b.id
                            AND  b.id BETWEEN a.id - 1 AND a.id + 1
                            AND  nvl(a.object_alias,' ')=nvl(b.object_alias,' ')
                            AND  nvl(a.qblock_name,' ')=nvl(b.qblock_name,' ')
                            AND (a.prefix='Index' AND b.options LIKE '%INDEX ROWID%' AND
                                 b.depth=a.depth-1 AND (a.parent_id=b.id OR a.parent_id!=b.id-1)
                              OR a.prefix='Table' AND b.operation LIKE 'INDEX%' AND
                                 b.depth=a.depth+1 AND (b.parent_id=a.id OR b.parent_id!=a.id-1))
                        THEN 1 ELSE 2 END flag
                FROM (SELECT /*+NO_MERGE*/ a.*,CASE WHEN operation LIKE 'INDEX%' THEN 'Index' WHEN options LIKE '%INDEX ROWID%' THEN 'Table' END prefix FROM  plans a) a
                JOIN &plan b
                ON   b.dbid = a.dbid
                AND  a.sql_id = b.sql_id
                AND  a.plan_hash_value = b.plan_hash_value
            ) a) a
        LEFT JOIN &plan b
        ON   b.dbid = a.dbid
        AND  a.sql_id = b.sql_id
        AND  a.plan_hash = b.plan_hash_value
        AND  a.parent_=b.id
        AND  regexp_like(b.operation,'HASH|NESTED|MERGE')
        AND  nvl(b.access_predicates,b.filter_predicates) IS NOT NULL
        WHERE seq_=1~';
    xml := dbms_xmlgen.getxmltype(stmt);
    stmt :=q'~
        WITH ops AS(
            SELECT *
            FROM xmltable('/ROWSET/ROW' PASSING :xml 
                COLUMNS dbid INT PATH 'DBID',
                        id INT PATH 'ID',
                        sorttype VARCHAR2(30) PATH 'SORTTYPE',
                        sq_id    VARCHAR2(30) PATH 'SQ_ID',
                        plan_full INT PATH 'PLAN_FULL',
                        plan_hash INT PATH 'PLAN_HASH',
                        obj INT PATH 'OBJ',
                        object_name VARCHAR2(30) PATH 'OBJECT_NAME',
                        operation VARCHAR2(300) PATH 'OPERATION',
                        options VARCHAR2(300) PATH 'OPTIONS',
                        op VARCHAR2(300) PATH 'OP',
                        preds VARCHAR2(4000) PATH 'JOIN_PREDS'
            )
        ),~';
    IF '&typ' ='d' THEN
        stmt := stmt||q'~@qry@
                FROM  (
                      SELECT b.*,plan_full,a.plan_hash,a.op,trim(chr(10) FROM preds) preds
                      FROM  (SELECT /*+no_merge*/ DISTINCT dbid,plan_hash,plan_full,coalesce(op,operation,options) op,preds FROM ops WHERE plan_hash>0) a
                      JOIN  &check_access_pdb.sqlstat b
                      ON     a.dbid=b.dbid
                      AND    a.plan_hash=b.plan_hash_value
                      AND    b.dbid='&dbid'
                      UNION  ALL
                      SELECT b.*,0,0,a.op,NULL
                      FROM  (SELECT /*+no_merge*/ DISTINCT dbid,sq_id,coalesce(op,operation,options) op FROM ops WHERE sq_id IS NOT NULL) a
                      JOIN  &check_access_pdb.sqlstat b
                      ON     a.dbid=b.dbid
                      AND    a.sq_id=b.sql_id
                      AND    b.dbid='&dbid'
                      AND    b.plan_hash_value=0) hs
                JOIN &check_access_pdb.snapshot s USING(dbid,snap_id,instance_number)
                WHERE s.begin_interval_time BETWEEN to_timestamp(coalesce('&V3', to_char(sysdate - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') 
                AND   to_timestamp(coalesce('&V4', to_char(sysdate+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')~';
    ELSE
        stmt := stmt||q'~@qry@
                FROM  (
                      SELECT b.*,elapsed_time elapsed_time_delta,executions executions_delta,&dbid dbid,plan_full,a.plan_hash,a.op,trim(chr(10) FROM preds) preds
                      FROM  (SELECT /*+no_merge*/ DISTINCT dbid,plan_hash,plan_full,coalesce(op,operation,options) op,preds FROM ops WHERE plan_hash>0) a
                      JOIN  gv$sqlstats b
                      ON     a.plan_hash=b.plan_hash_value
                      UNION  ALL
                      SELECT b.*,elapsed_time elapsed_time_delta,executions executions_delta,&dbid dbid,0,0,a.op,NULL
                      FROM  (SELECT /*+no_merge*/ DISTINCT dbid,sq_id,coalesce(op,operation,options) op FROM ops WHERE sq_id IS NOT NULL) a
                      JOIN   gv$sqlstats b
                      ON     a.sq_id=b.sql_id
                      AND    b.plan_hash_value=0) hs
                WHERE nvl(hs.last_active_time,sysdate) BETWEEN to_date(coalesce('&V3', to_char(sysdate - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') 
                AND   to_date(coalesce('&V4', to_char(sysdate+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')~';        
    END IF;

    OPEN :C1 FOR replace(stmt,'@qry@',q'~
        stats AS (
            SELECT max(&phf) KEEP(dense_rank LAST ORDER BY total_ela) top_plan,
                   count(DISTINCT plan_hash) "Plans",
                   max(sql_id) KEEP(dense_rank LAST ORDER BY total_ela) top_sql,
                   count(DISTINCT sql_id) "SQLs",
                   sum(total_ela) total_ela,
                   ratio_to_report(sum(total_ela)) OVER() weight,
                   sum(execs) execs,
                   round(sum(total_ela)/greatest(sum(execs),1),2) avg_ela,
                   op,max(preds) preds
            FROM (
                SELECT /*+outline_leaf ordered use_hash(hs s) opt_param('_optimizer_cartesian_enabled' 'false')  opt_param('_optimizer_mjc_enabled' 'false') */
                       hs.sql_id,dbid &con,
                       sum(elapsed_time_delta) total_ela,
                       sum(executions_delta) execs,
                       plan_full,plan_hash,op,preds~')
        || q'~
                GROUP  BY hs.sql_id, dbid &con,plan_full,plan_hash,op,preds)
            WHERE trim(preds) IS NOT NULL
            GROUP BY op,preds)
        SELECT * FROM stats
        ORDER  BY 0+decode(nvl(lower('&V2'),'total'),'total',total_ela,'ela',avg_ela,'exe',execs,'sqls',"SQLs",0) DESC NULLS LAST,total_ela DESC~'
    USING xml;

    OPEN :C2 FOR replace(stmt,'@qry@',q'~
        stats AS (
            SELECT &phf,dbid &con, 
                   max(sql_id) KEEP(dense_rank LAST ORDER BY total_ela) sql_id,
                   count(DISTINCT sql_id) ids,
                   sum(total_ela) total_ela,
                   ratio_to_report(sum(total_ela)) OVER() weight,
                   sum(execs) execs,
                   round(sum(total_ela)/greatest(sum(execs),1),2) avg_ela
            FROM (
                SELECT /*+outline_leaf ordered use_hash(hs s) opt_param('_optimizer_cartesian_enabled' 'false')  opt_param('_optimizer_mjc_enabled' 'false') */
                       hs.sql_id,dbid &con,
                       sum(elapsed_time_delta) total_ela,
                       sum(executions_delta) execs,
                       plan_full,plan_hash~')
        || q'~
                GROUP  BY hs.sql_id, dbid &con,plan_full,plan_hash)
            GROUP BY &phf,dbid &con,CASE WHEN plan_hash=0 THEN sql_id END)
        SELECT &phf,id plan#,sql_id top_sql_id,ids "SQLs",obj,
               coalesce(op,operation||' '||options) operation,total_ela,weight,avg_ela,execs,
               substr(regexp_replace(trim(to_char(substr(sql_text, 1, 500))),'[[:space:][:cntrl:]]+',' '),1,200) text
        FROM  ops a
        JOIN  stats b USING(dbid,&phf)
        LEFT JOIN &check_access_pdb.sqltext USING(dbid &con,sql_id)
        WHERE sql_id=nvl(a.sq_id,sql_id)
        ORDER  BY 0+decode(sorttype,'total',total_ela,'ela',avg_ela,'exe',execs,0) DESC NULLS LAST,
                  decode(sorttype,'sql',sql_id,'text',text)~'
    USING xml;
END;
/
