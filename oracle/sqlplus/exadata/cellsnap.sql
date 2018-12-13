set verify off feed off termout off pages 9999
define sleeps=30
col cells new_value cells
col stype for a25
col name for a70
 
SELECT listagg(''''||a.cellname||''' as "'|| b.name||'"',',') WITHIN GROUP(ORDER BY b.name) cells
FROM   v$cell_config a,
       XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                NAME VARCHAR2(300) path 'name') b
WHERE  conftype = 'CELL';
set termout on
WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
    BEGIN
        IF ID=1 THEN RETURN SYSTIMESTAMP;END IF;
        SYS.DBMS_LOCK.sleep(greatest(1,86400*(target-sysdate)));
        RETURN SYSTIMESTAMP;
    END;
SELECT /*+monitor*/ * FROM(
    SELECT /*+ordered use_nl(timer stat)*/
            nvl(cell, '--TOTAL--') cell, stype,NAME, round(SUM(VALUE * DECODE(r, 1, -1, 1))/&sleeps,2) VALUE
    FROM   (SELECT /*+no_merge*/ROWNUM r, sysdate+numtodsinterval(&sleeps,'second') mr FROM XMLTABLE('1 to 2')) dummy,
            LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
            LATERAL (SELECT /*+no_merge pq_concurrent_union*/ cell, stype, NAME, SUM(VALUE) VALUE
                     FROM  (SELECT cell_name cell,'CELL GLOBAL' stype,METRIC_NAME NAME,metric_value VALUE
                            FROM   v$cell_global
                            UNION ALL
                            SELECT cell_name cell,'CELL DB - '||src_dbname stype,METRIC_NAME NAME,metric_value VALUE
                            FROM   v$cell_db
                            UNION ALL
                            SELECT cell_name cell,'CELL IOREASON ' stype,reason_name||' (bytes)' NAME,metric_value VALUE
                            FROM   v$cell_ioreason
                            WHERE  METRIC_TYPE='bytes'
                            UNION ALL
                            SELECT /*+ordered_predicates*/
                                   a.CELL_NAME cell, 'CELLSTATE - '||a.statistics_type stype,  '['||upper(nvl(ptype,pname))||'] '||b.name,b.value+0
                            FROM   v$cell_state a,
                                   XMLTABLE('//*[contains(name(),"stats")][stat]' PASSING XMLTYPE(a.statistics_value)
                                    COLUMNS pname VARCHAR2(128) PATH 'name()',
                                            ptype VARCHAR2(128) PATH '@name | @type',
                                            fvalue VARCHAR2(128) PATH '*[1]',
                                            n XMLTYPE PATH 'node()') c,
                                   XMLTABLE('stat' PASSING c.n
                                    COLUMNS NAME VARCHAR2(128) PATH '@name',
                                            VALUE VARCHAR2(128) PATH '.') b
                            WHERE  statistics_type NOT IN ('SENDPORT', 'THREAD', 'LOCK', 'IOREASON', 'CAPABILITY', 'RCVPORT','DBDES','PHASESTAT')
                            AND    regexp_like(fvalue, '^\d*$')
                            AND    regexp_like(VALUE, '^[1-9]\d*$'))
                     WHERE  timer.stime IS NOT NULL
                     GROUP  BY GROUPING SETS((stype, NAME),(cell, stype, NAME))) stat
    GROUP  BY cell, stype,NAME
    HAVING round(SUM(VALUE * DECODE(r, 1, -1, 1))/&sleeps,2)!=0)
PIVOT(SUM(VALUE) FOR cell IN('--TOTAL--' AS total,&cells.))
ORDER BY 1,2
/