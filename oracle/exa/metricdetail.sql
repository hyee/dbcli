/*[[
    Show the detail cell metric based on external table EXA$METRIC. Usage: @@NAME {[<keyword>] [-r]} {[-vw]  | <seconds> [-avg]}
    Refer to page https://docs.oracle.com/en/engineered-systems/exadata-database-machine/sagug/exadata-storage-server-monitoring.html#GUID-B52267F8-FAD9-4A86-9D84-81792A914C94
    This script relies on external table EXA$METRIC which is created by shell script "oracle/shell/create_exa_external_tables.sh" with the oracle user
    
    Parameters:
       <keyword> :  case-insensitive expression
       -r        :  the keyword is a Regular expression instead of a LIKE expression
       -vw       :  query EXA$METRIC_VW instead of EXA$METRIC_AGG
       <seconds> :  take 2 snapshots with the specific seconds, then print the delta stats
       -avg      :  when <seconds> is specified, devide the delta stats with <seconds> instead of the total stats

    --[[
        @check_access_obj: EXA$METRIC_VW={}
        @CHECK_ACCESS_SL : SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
        &vw              : agg={EXA$METRIC_AGG} vw={EXA$METRIC_VW}
        &avg             : default={1} avg={&V2}
        &filter          : {
            like={upper(DESCRIPTION||','||a.OBJECTTYPE || ',' || a.NAME || ',' ||  METRICTYPE ) LIKE upper('%&V1%')}
            r={regexp_like(DESCRIPTION||','||a.OBJECTTYPE || ',' || a.NAME || ',' || METRICTYPE,'&V1','i')}
        }
    --]]
]]*/
COL METRICVALUE FOR K2
set verify off feed off sep4k on
var cur refcursor
DECLARE
    v_pivot VARCHAR2(4000);
    v_stmt VARCHAR2(32767);
BEGIN
    IF regexp_like(:V2,'^\d+$') THEN
        SELECT listagg(''''||b.name||''' "CELL#'||regexp_substr(b.name,'\d+$')||'"',',') within group(order by b.name) pivots
        INTO   v_pivot
        FROM   v$cell_config a,
               XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS NAME VARCHAR2(300) path 'name') b
        WHERE  conftype = 'CELL'; 

        v_stmt :=replace(q'[
            WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
                BEGIN
                    IF ID=1 THEN RETURN SYSTIMESTAMP;END IF;
                    &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
                    RETURN SYSTIMESTAMP;
                END;
            SELECT /*+use_hash(a b) opt_param('parallel_force_local' 'true')*/ a.*,b.description FROM (
                SELECT * FROM ( 
                    SELECT OBJECTTYPE,
                           NAME,
                           UNIT,
                           nvl(CELLNODE, 'TOTAL') c,
                           round(DECODE(IS_AVG, 1, AVG(v), SUM(v)/DECODE(MAX(METRICTYPE),'Cumulative',&AVG,1)), 2) v
                    FROM (
                        SELECT CELLNODE,OBJECTTYPE,NAME,METRICTYPE,UNIT,METRICOBJECTNAME,
                               CASE WHEN trim(UNIT) IN ('us/request', '%', 'C') THEN 1 ELSE 0 END IS_AVG,
                               DECODE(trim(METRICTYPE),'Cumulative', SUM(METRICVALUE*DECODE(r, 1, -1, 1)),MAX(METRICVALUE) KEEP(DENSE_RANK LAST ORDER BY r)) v
                        FROM   (SELECT /*+no_merge ordered use_nl(timer stat)*/ROWNUM r, 
                                        sysdate+numtodsinterval(&V2,'second') mr FROM XMLTABLE('1 to 2')) dummy,
                                LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                                LATERAL (SELECT /*+no_merge*/ * from EXA$METRIC a WHERE timer.stime IS NOT NULL) stat
                        GROUP  BY CELLNODE,OBJECTTYPE,NAME,METRICTYPE,UNIT,METRICOBJECTNAME
                    ) a
                    WHERE v!=0
                    GROUP BY NAME,OBJECTTYPE,IS_AVG,UNIT,ROLLUP(CELLNODE)
                )
                PIVOT(MAX(v) FOR c IN('TOTAL' TOTAL, @pivots))
                WHERE total!=0) a, exa$metric_desc B
            WHERE  a.name=b.name and a.objecttype=b.objecttype
            AND   (&filter)
            ORDER  BY 1, 2, 3, 4    
            ]','@pivots',v_pivot);
        --dbms_output.put_line(v_stmt);
        OPEN :cur FOR v_stmt;
    ELSE
        OPEN :cur FOR
            SELECT /*+opt_param('parallel_force_local' 'true')*/ *
            FROM   &vw a
            WHERE  &filter
            AND    rownum <= 256;
    END IF;
END;
/
print cur