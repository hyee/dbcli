/*[[
    Show the detail of "cellsrvstat" based on external table EXA$CELLSRVSTAT. Usage: @@NAME {[<keyword>] [-r]} {[-agg] | <seconds> [-avg]}
    This script relies on external table EXA$CELLSRVSTAT which is created by shell script "oracle/shell/create_exa_external_tables.sh" with the oracle user
    
    Parameters:
       <keyword> :  case-insensitive expression
       -r        :  the keyword is a Regular expression instead of a LIKE expression
       -agg      :  query EXA$CELLSRVSTAT_AGG instead of EXA$CELLSRVSTAT
       <seconds> :  take 2 snapshots with the specific seconds, then print the delta stats
       -avg      :  when <seconds> is specified, devide the delta stats with <seconds> instead of the total stats

    --[[
        @check_access_obj: EXA$CELLSRVSTAT={}
        @CHECK_ACCESS_SL : SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
        &vw              : vw={EXA$CELLSRVSTAT} agg={EXA$CELLSRVSTAT_AGG}
        &cell            : vw={CELLNODE||','||OFFLOAD_GROUP || ',' ||} agg={}
        &avg             : default={1} avg={&V2}
        &filter          : {
            like={upper(&cell  NAME || ',' || CATEGORY || ',' || ITEM) LIKE upper('%&V1%')}
            r={regexp_like(&cell NAME || ',' || CATEGORY || ',' || ITEM,'&V1','i')}
        }
    --]]
]]*/
COL VALUE FOR K2
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
            SELECT /*+opt_param('parallel_force_local' 'true')*/ * FROM ( 
                SELECT CATEGORY,NAME,ITEM,
                       nvl(CELLNODE, 'TOTAL') c,
                       DECODE(IS_AVG,1,'NO','YES') Cumulative,
                       DECODE(IS_LAST,1,'NO','YES') "DELTA",
                       round(DECODE(IS_AVG, 1, AVG(v), SUM(v)/DECODE(IS_LAST,1,1,&AVG)), 2) v
                FROM (
                    SELECT CELLNODE,CATEGORY,
                           REPLACE(NAME,'(KB)','(MB)') NAME,
                           OFFLOAD_GROUP,ITEM,IS_LAST,
                           CASE
                             WHEN regexp_like(NAME, '(avg|average|percentage)', 'i') OR (LOWER(NAME) LIKE '%util%' AND lower(NAME) NOT LIKE '% rate %util%') THEN
                              1
                             ELSE
                              0
                            END IS_AVG,
                            DECODE(IS_LAST,0,SUM(VALUE*DECODE(r, 1, -1, 1)),MAX(VALUE) KEEP(DENSE_RANK LAST ORDER BY r))/decode(instr(NAME,'(KB)'),0,1,1024) v
                    FROM   (SELECT /*+no_merge ordered use_nl(timer stat)*/ROWNUM r, 
                                    sysdate+numtodsinterval(&V2,'second') mr FROM XMLTABLE('1 to 2')) dummy,
                            LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                            LATERAL (SELECT /*+no_merge*/ A.*,CASE WHEN REGEXP_LIKE(name,'^(Number of|# of|num|Size of|CC IOs|Total|Flash disk|Hard disk|SI|Allocations|Write-Heavy CC|CC Regions) ','i') THEN 0 ELSE 1 END IS_LAST from EXA$CELLSRVSTAT a WHERE timer.stime IS NOT NULL) stat
                    GROUP  BY CELLNODE,CATEGORY,NAME,OFFLOAD_GROUP,ITEM,IS_LAST
                )
                WHERE V!=0 AND (&FILTER)
                GROUP BY CATEGORY,NAME,ITEM,IS_AVG,IS_LAST,ROLLUP(CELLNODE)
            )
            PIVOT(MAX(v) FOR c IN('TOTAL' TOTAL, @pivots))
            WHERE total!=0
            ORDER  BY 1, 2, 3, 4    
            ]','@pivots',v_pivot);
        --dbms_output.put_line(v_stmt);
        OPEN :cur FOR v_stmt;
    ELSE
        OPEN :cur FOR
            SELECT /*+opt_param('parallel_force_local' 'true')*/ *
            FROM   &vw
            WHERE  &filter
            AND    rownum <= 256;
    END IF;
END;
/
print cur