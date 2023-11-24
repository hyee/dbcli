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
    xml := dbms_xmlgen.getxmltype(q'~
        WITH plans AS(
            SELECT A.*
            FROM   &plan a
            WHERE  UPPER('&V1') IN(a.OBJECT_NAME,''||a.object#)
            AND    A.DBID='&dbid'
        )
        SELECT * FROM (
            SELECT row_number() over(partition by dbid,sq_id,plan_hash_value,id order by flag) seq_,
                   a.dbid,
                   a.id,
                   nvl(lower('&V2'),'total') sorttype,
                   sq_id,
                   plan_full,
                   a.plan_hash_value plan_hash,
                   a.object# obj,
                   a.object_name,
                   a.options,a.operation,
                   CASE WHEN prefix = 'Table' AND flag=1 THEN
                            DECODE(b_options,
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
                                    b_options)||'('||NVL(b_SEARCH_COLUMNS,0) || '): ' || b_object_name
                        WHEN prefix = 'Index' AND flag=1 THEN
                            DECODE(a.options,
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
                                    a.options)||'('||NVL(a.SEARCH_COLUMNS,0) || '): ' || b_object_name
                   ELSE a.OPTIONS END OP,
                   REPLACE(CASE WHEN a.ACCESS_PREDICATES IS NOT NULL THEN nvl(prefix,'Table')||' Access: '||substr(a.ACCESS_PREDICATES,1,800)||chr(10) END ||
                           CASE WHEN a.FILTER_PREDICATES IS NOT NULL THEN nvl(prefix,'Table')||' Filter: '||substr(a.FILTER_PREDICATES,1,800)||chr(10) END ||
                           CASE WHEN b_ACCESS_PREDICATES IS NOT NULL AND flag=1 THEN decode(prefix,'Index','Table','Index')||' Access: '||substr(b_ACCESS_PREDICATES,1,800)||chr(10) END ||
                           CASE WHEN b_FILTER_PREDICATES IS NOT NULL AND flag=1 THEN decode(prefix,'Index','Table','Index')||' Filter: '||substr(b_FILTER_PREDICATES,1,800) END
                        ,'"') PREDS
            FROM (
                SELECT  /*+outline_leaf use_hash(a b) */
                        A.*,
                        decode(a.plan_hash_value,0,a.sql_id) sq_id,
                        nvl(max(0+nvl2(b.other_xml,nullif(to_char(regexp_substr(b.other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'0'),'')) over(partition by a.dbid,a.plan_hash_value),a.plan_hash_value) plan_full,
                        b.ACCESS_PREDICATES B_ACCESS_PREDICATES,
                        b.FILTER_PREDICATES B_FILTER_PREDICATES,
                        b.options B_OPTIONS,
                        B.object_name B_object_name,
                        B.SEARCH_COLUMNS B_SEARCH_COLUMNS,
                        CASE WHEN a.id!=b.id
                            AND  b.id BETWEEN a.id - 1 AND a.id + 1
                            AND  nvl(a.OBJECT_ALIAS,' ')=nvl(b.OBJECT_ALIAS,' ')
                            AND  nvl(a.QBLOCK_NAME,' ')=nvl(b.QBLOCK_NAME,' ')
                            AND (a.prefix='Index' AND B.options like '%INDEX ROWID%' AND 
                                 b.depth=a.depth-1 and (a.parent_id=b.id or a.parent_id!=b.id-1)
                              OR a.prefix='Table' AND B.operation like 'INDEX%' AND 
                                 b.depth=a.depth+1 and (b.parent_id=a.id or b.parent_id!=a.id-1))
                        THEN 1 ELSE 2 END FLAG
                FROM (SELECT /*+NO_MERGE*/ A.*,CASE WHEN OPERATION LIKE 'INDEX%' THEN 'Index' WHEN options LIKE '%INDEX ROWID%' THEN 'Table' END prefix FROM  plans a) a
                JOIN &plan b
                ON   b.dbid = a.dbid
                AND  a.sql_id = b.sql_id
                AND  a.plan_hash_value = b.plan_hash_value
            ) a
        ) WHERE seq_=1~');
    stmt :=q'~
        WITH ops AS(
            SELECT *
            FROM XMLTABLE('/ROWSET/ROW' PASSING :xml 
                COLUMNS DBID INT PATH 'DBID',
                        ID INT PATH 'ID',
                        SORTTYPE VARCHAR2(30) PATH 'SORTTYPE',
                        SQ_ID    VARCHAR2(30) PATH 'SQ_ID',
                        PLAN_FULL INT PATH 'PLAN_FULL',
                        PLAN_HASH INT PATH 'PLAN_HASH',
                        OBJ INT PATH 'OBJ',
                        OBJECT_NAME VARCHAR2(30) PATH 'OBJECT_NAME',
                        OPERATION VARCHAR2(300) PATH 'OPERATION',
                        OPTIONS VARCHAR2(300) PATH 'OPTIONS',
                        OP VARCHAR2(300) PATH 'OP',
                        PREDS VARCHAR2(4000) PATH 'PREDS'
            )
        ),~';
    IF '&typ' ='d' THEN
        stmt := stmt||q'~@qry@
                FROM  (
                      SELECT b.*,plan_full,a.plan_hash,a.op,trim(chr(10) from PREDS) preds
                      FROM  (select /*+no_merge*/ distinct dbid,plan_hash,plan_full,coalesce(op,operation,options) op,PREDS from ops where plan_hash>0) a
                      JOIN  &check_access_pdb.Sqlstat b
                      ON     a.dbid=b.dbid
                      AND    a.plan_hash=b.plan_hash_value
                      AND    b.dbid='&dbid'
                      UNION  ALL
                      SELECT b.*,0,0,a.op,null
                      FROM  (select /*+no_merge*/ distinct dbid,sq_id,coalesce(op,operation,options) op from ops where sq_id IS NOT NULL) a
                      JOIN  &check_access_pdb.Sqlstat b
                      ON     a.dbid=b.dbid
                      AND    a.sq_id=b.sql_id
                      AND    b.dbid='&dbid'
                      AND    b.plan_hash_value=0) hs
                JOIN &check_access_pdb.snapshot s USING(dbid,snap_id,instance_number)
                WHERE s.begin_interval_time BETWEEN to_timestamp(coalesce('&V3', to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') 
                AND   to_timestamp(coalesce('&V4', to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')~';
    ELSE
        stmt := stmt||q'~@qry@
                FROM  (
                      SELECT b.*,elapsed_time elapsed_time_delta,executions executions_delta,&dbid dbid,plan_full,a.plan_hash,a.op,trim(chr(10) from PREDS) preds
                      FROM  (select /*+no_merge*/ distinct dbid,plan_hash,plan_full,coalesce(op,operation,options) op,PREDS from ops where plan_hash>0) a
                      JOIN  gv$Sqlstats b
                      ON     a.plan_hash=b.plan_hash_value
                      UNION  ALL
                      SELECT b.*,elapsed_time elapsed_time_delta,executions executions_delta,&dbid dbid,0,0,a.op,null
                      FROM  (select /*+no_merge*/ distinct dbid,sq_id,coalesce(op,operation,options) op from ops where sq_id IS NOT NULL) a
                      JOIN   gv$Sqlstats b
                      ON     a.sq_id=b.sql_id
                      AND    b.plan_hash_value=0) hs
                WHERE nvl(hs.last_active_time,sysdate) BETWEEN to_date(coalesce('&V3', to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') 
                AND   to_date(coalesce('&V4', to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')~';        
    END IF;

    OPEN :C1 FOR replace(stmt,'@qry@',q'~
        Stats AS (
            SELECT max(&phf) keep(dense_rank last order by total_ela) top_plan,
                   count(distinct plan_hash) "Plans",
                   max(sql_id) keep(dense_rank last order by total_ela) top_sql,
                   count(distinct sql_id) "SQLs",
                   sum(total_ela) total_ela,
                   ratio_to_report(sum(total_ela)) over() weight,
                   sum(execs) execs,
                   round(sum(total_ela)/greatest(sum(execs),1),2) avg_ela,
                   op,PREDS
            FROM (
                SELECT /*+outline_leaf ordered use_hash(hs s) opt_param('_optimizer_cartesian_enabled' 'false')  opt_param('_optimizer_mjc_enabled' 'false') */
                       hs.sql_id,dbid &con,
                       SUM(elapsed_time_delta) TOTAL_ELA,
                       SUM(executions_delta) execs,
                       plan_full,plan_hash,op,PREDS~')
        || q'~
                GROUP  BY hs.sql_id, dbid &con,plan_full,plan_hash,op,PREDS)
            WHERE trim(preds) IS NOT NULL
            GROUP BY op,PREDS)
        SELECT * FROM Stats
        ORDER  BY 0+decode(nvl(lower('&V2'),'total'),'total',total_ela,'ela',avg_ela,'exe',execs,'sqls',"SQLs",0) DESC NULLS LAST,total_ela desc~'
    USING XML;

    OPEN :C2 FOR replace(stmt,'@qry@',q'~
        Stats AS (
            SELECT &phf,dbid &con, 
                   max(sql_id) keep(dense_rank last order by total_ela) sql_id,
                   count(distinct sql_id) ids,
                   sum(total_ela) total_ela,
                   ratio_to_report(sum(total_ela)) over() weight,
                   sum(execs) execs,
                   round(sum(total_ela)/greatest(sum(execs),1),2) avg_ela
            FROM (
                SELECT /*+outline_leaf ordered use_hash(hs s) opt_param('_optimizer_cartesian_enabled' 'false')  opt_param('_optimizer_mjc_enabled' 'false') */
                       hs.sql_id,dbid &con,
                       SUM(elapsed_time_delta) TOTAL_ELA,
                       SUM(executions_delta) execs,
                       plan_full,plan_hash~')
        || q'~
                GROUP  BY hs.sql_id, dbid &con,plan_full,plan_hash)
            GROUP BY &phf,dbid &con,case when plan_hash=0 THEN sql_id END)
        SELECT &phf,id plan#,sql_id top_sql_id,ids "SQLs",obj,
               coalesce(op,operation,options) operation,total_ela,weight,avg_ela,execs,
               substr(regexp_replace(trim(to_char(SUBSTR(sql_text, 1, 500))),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) text
        FROM  ops a
        JOIN  stats b USING(dbid,&phf)
        LEFT JOIN &check_access_pdb.sqltext USING(dbid &con,sql_id)
        WHERE sql_id=nvl(a.sq_id,sql_id)
        ORDER  BY 0+decode(sorttype,'total',total_ela,'ela',avg_ela,'exe',execs,0) DESC NULLS LAST,
                  decode(sorttype,'sql',sql_id,'text',text)~'
    USING XML;
END;
/
