/*[[get cell state. Usage: @@NAME [secs|<keyword>] [-avg]
   --[[
        &adj: default={1} avg={&V1}
        &V1: default={30}
        @CHECK_ACCESS_SL: SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
   --]]
]]*/
set verify off feed off termout off printsize 3000 sep4k on
col cells new_value cells noprint;
col kw   new_value kw noprint;
SELECT listagg(''''||a.cellname||''' as "'|| b.name||'"',',') WITHIN GROUP(ORDER BY b.name) cells,
       lower(:v1) kw
FROM   v$cell_config a,
       XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                NAME VARCHAR2(300) path 'name') b
WHERE  conftype = 'CELL'; 

set termout on feed off
var cur refcursor
var c2  refcursor
DECLARE
    cur  SYS_REFCURSOR;
    v1   VARCHAR2(3000):=lower(:V1);
    secs INT:= regexp_substr(V1,'^\d+$');
BEGIN
    IF secs IS NOT NULL THEN
        OPEN cur FOR q'{
        WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
            BEGIN
                IF ID=1 THEN RETURN SYSTIMESTAMP;END IF;
                &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
                RETURN SYSTIMESTAMP;
            END;
        SELECT * FROM(
            SELECT /*+ordered use_nl(timer stat) outline_leaf*/
                    nvl(cell, '--TOTAL--') cell, stype,NAME, round(SUM(VALUE * DECODE(r, 1, -1, 1))/&adj,2) VALUE
            FROM   (SELECT ROWNUM r, sysdate+numtodsinterval(&V1,'second') mr FROM XMLTABLE('1 to 2')) dummy,
                    LATERAL (SELECT do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                    LATERAL (SELECT /*+pq_concurrent_union*/ cell, stype, NAME, SUM(VALUE) VALUE
                            FROM   (SELECT cell_name cell,'CELL GLOBAL' stype,METRIC_NAME NAME,metric_value VALUE 
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
                                           a.CELL_NAME cell, 'CELLSTATE - '||a.statistics_type stype, pname||NULLIF('[' || ptype|| ']','[]') || NULLIF('/'||b.name,'/') name,b.value+0
                                    FROM   v$cell_state a,
                                           XMLTABLE('//*[contains(name(),"stats")][stat]' PASSING XMLTYPE(a.statistics_value) 
                                            COLUMNS pname VARCHAR2(128) PATH 'name()',
                                                    ptype VARCHAR2(128) PATH '@name | @type',
                                                    fvalue VARCHAR2(128) PATH '*[1]',
                                                    n XMLTYPE PATH 'node()') c,
                                           XMLTABLE('stat' PASSING c.n 
                                            COLUMNS NAME VARCHAR2(128) PATH '@name | @type',
                                                    VALUE VARCHAR2(128) PATH '.') b
                                    WHERE  statistics_type NOT IN ('PHASESTAT','SENDPORT', 'THREAD', 'LOCK', 'IOREASON', 'CAPABILITY', 'RCVPORT','DBDES')
                                    AND    regexp_like(fvalue, '^\d*$')
                                    AND    regexp_like(VALUE, '^[1-9]\d*$'))
                            WHERE  timer.stime IS NOT NULL
                            GROUP  BY GROUPING SETS((stype, NAME),(cell, stype, NAME))) stat
            GROUP  BY cell, stype,NAME
            HAVING round(SUM(VALUE * DECODE(r, 1, -1, 1))/&adj,2)!=0)
        PIVOT(SUM(VALUE) FOR cell IN('--TOTAL--' AS total,&cells)) 
        ORDER BY 1,2}';
    ELSE
        v1 := '//*[contains(lower-case(@name),"'||v1||'") or contains(lower-case(@group),"'||v1||'") or contains(lower-case(@type),"'||v1||'") or contains(lower-case(local-name()), "'||v1||'")]';
        OPEN cur FOR
            WITH STAT AS (
                SELECT /*+MATERIALIZE*/ 
                       nvl(cell, '--TOTAL--') cell, stype, name,  
                       SUM(value) value
                       --DECODE(max(flag) over(partition by stype,name), chr(1), to_char(SUM(VALUE)), MAX(VALUE)) VALUE
                FROM   (SELECT a.*,
                               CASE WHEN regexp_like(VALUE, '^-?[0-9\.]+$') THEN chr(1) ELSE VALUE END flag
                        FROM   (SELECT a.CELL_NAME cell,
                                       'CELLSTATE - ' || a.statistics_type stype,
                                       pname||NULLIF('[' || ptype|| ']','[]') || nvl2(b.tag,' / '||tag||NULLIF('[' || b.name|| ']','[]'),'') name,
                                       nvl2(b.tag,nvl(b.value,'0'),to_char(substr(c.n.getclobval(),1,128))) VALUE
                                FROM   v$cell_state a,
                                       XMLTABLE(v1
                                                PASSING(XMLTYPE(a.statistics_value)) 
                                                COLUMNS pname VARCHAR2(128) PATH 'name()',
                                                        ptype VARCHAR2(128) PATH '@name[contains(lower-case(.),"&kw")] | @type[contains(lower-case(.),"&kw")] | @group[contains(lower-case(.),"&kw")]',
                                                        n XMLTYPE PATH 'node()') c,
                                       XMLTABLE('//*[not(*)]' PASSING c.n 
                                                COLUMNS tag VARCHAR2(128) PATH 'name()',
                                                        NAME VARCHAR2(128) PATH '@name | @type', 
                                                        VALUE VARCHAR2(128) PATH '.')(+) b) a)
                where flag=chr(1)
                GROUP  BY stype, name,flag, ROLLUP(CELL))
            SELECT * FROM STAT PIVOT(MAX(VALUE) FOR cell IN('--TOTAL--' AS total,&cells))
            ORDER  BY 1,2;

        OPEN :C2 FOR
            WITH Stat1 AS(
                SELECT nvl(cell_name, '--TOTAL--') cell,
                       'CELL GLOBAL' stype,
                       metric_name name,
                       SUM(metric_value) value
                FROM   v$cell_global
                WHERE  instr(lower(metric_name),lower(:kw))>0
                GROUP  BY metric_name,rollup(cell_name)
                UNION ALL
                SELECT nvl(cell_name, '--TOTAL--') cell,
                       'CELL IOREASON' style,
                       reason_name||nvl2(metric_type,'('||metric_type||')','') name,
                       SUM(metric_value) value
                FROM   v$cell_ioreason
                WHERE  instr(lower(reason_name),lower(:kw))>0
                GROUP  BY reason_name,metric_type,rollup(cell_name))
            SELECT * FROM STAT1 PIVOT(MAX(VALUE) FOR cell IN('--TOTAL--' AS total,&cells)) 
            ORDER BY 1,2;
    END IF;

    :cur := cur;
END;
/

print cur
print c2

