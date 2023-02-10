/*[[Show database level high water mark
    --[[
        @did : 12.2={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
        @con : 12.1={,con_id} default={}
    --]]
]]*/
SET FEED OFF
COL HIGHWATER,LAST_VALUE FOR AUTO DESCRIPTION
PRO dba_high_water_mark_statistics
PRO ==============================
SELECT * FROM dba_high_water_mark_statistics WHERE DBID=&did ORDER BY 2;
VAR c1 REFCURSOR "gv$resource_limit"
VAR c2 REFCURSOR "gv$latch_children"
COL WAIT_TIME FOR USMHD2
COL GETS,MISSES FOR TMB2
DECLARE 
    COLS VARCHAR2(32767);
    COL1 VARCHAR2(32767);
    CNT  INT;
BEGIN
    SELECT LISTAGG(REPLACE('#P#,#I#,#V#)) "##I#"','#I#',INST_ID),',') WITHIN GROUP(ORDER BY INST_ID),COUNT(1)
    INTO   COLS,CNT
    FROM   GV$INSTANCE;

    COLS := ','||REPLACE(COLS,'#P#','SUM(DECODE(INST_ID');
    OPEN :C1 FOR '
        SELECT RESOURCE_NAME,''|'' "|",
               SUM(CURRENT_UTILIZATION) "CURRENT" '||replace(COLS,'#V#','CURRENT_UTILIZATION')||',''|'' "|",
               SUM(MAX_UTILIZATION) "MAX" '||replace(COLS,'#V#','MAX_UTILIZATION')||q'~,'|' "|",
               nvl(''||MIN(nullif(trim(INITIAL_ALLOCATION),'UNLIMITED')),'UNLIMITED') INITIAL_ALLOCATION,
               nvl(''||MIN(nullif(trim(LIMIT_VALUE),'UNLIMITED')),'UNLIMITED') LIMIT_VALUE &con
        FROM   gv$resource_limit
        GROUP  BY RESOURCE_NAME &CON
        ORDER BY 1 &CON~';

    COL1 := REGEXP_REPLACE(REPLACE(COLS,'SUM(','ROUND(100*SUM('),'"(#\d+)"','/NULLIF(SUM(#V#),0),1) "\1 %"');
    OPEN :C2 FOR '
        SELECT NAME LATCH_NAME,''|'' "|"
               '||replace(COLS,'#V#','CNT')||',''|'' "|",
               SUM(GETS) "GETS" '||replace(COL1,'#V#','GETS')||',''|'' "|",
               SUM(MISSES) "MISSES" '||replace(COL1,'#V#','MISSES')||',''|'' "|",
               SUM(WAIT_TIME) "WAIT_TIME" '||replace(COL1,'#V#','WAIT_TIME')||q'~
        FROM   TABLE(GV$(CURSOR(
                   SELECT USERENV('INSTANCE') INST_ID,
                          NAME,
                          COUNT(1) CNT, 
                          SUM(WAIT_TIME) WAIT_TIME,
                          SUM(GETS) GETS,
                          SUM(MISSES) MISSES
                   FROM   V$LATCH_CHILDREN
                   WHERE  (GETS+MISSES)>0
                   GROUP  BY NAME))) 
        JOIN   (SELECT NAME FROM (SELECT NAME,SUM(GETS/30+MISSES) C FROM V$LATCH_CHILDREN WHERE (GETS+MISSES)>0 GROUP BY NAME ORDER BY 2 DESC) WHERE ROWNUM<=30)
        USING  (NAME)
        GROUP  BY NAME
        ORDER  BY GETS/30+MISSES DESC~';
END;
/
