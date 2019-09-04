/*[[
    Show GES resource hash bucket info. Usage: @@NAME {[ADDR] [Bucket#]} | {<sample secs> [-avg]} 
    
    Mainly used to diagnostic below the "latch: ges resource hash list" events

    Examples:
    =========
    SQL> SYS GESBUCKETS . 191
    INST_ID       RHT        LMDID GROUPID BUCKET# ITEMS MAX_ITEMS NO_WAITS FAILED_WAITS   WAITS   Waits(%)|          ORADEBUG
    ------- ---------------- ----- ------- ------- ----- --------- -------- ------------ --------- --------+----------------------------
          1 0000002B592A0A58     0       0     191     2        53    160            0   137.175 K   55.31%| oradebug lkdebug -B 0 0 191
          3 0000002B592A0A58     0       0     191     3        53    125           11    37.395 K   15.08%| oradebug lkdebug -B 0 0 191
          2 0000002B592A0A58     0       0     191     5        33    124            0    36.625 K   14.77%| oradebug lkdebug -B 0 0 191
          4 0000002B519E4000     1       0     191     1         7     90           39    14.361 K    5.79%| oradebug lkdebug -B 1 0 191

    SQL> SYS GESBUCKETS 10 -avg
    INST_ID       RHT        LMDID GROUPID BUCKET# ITEMS MAX_ITEMS NO_WAITS FAILED_WAITS  WAITS  Waits(%)|           ORADEBUG
    ------- ---------------- ----- ------- ------- ----- --------- -------- ------------ ------- --------+------------------------------
          4 0000002B519E4000     1       0    1032     1         6      0          135   9.261 K    4.78%| oradebug lkdebug -B 1 0 1032
          4 0000002B5977D2C0     0       0    7379     4         5      0          101   8.116 K    4.19%| oradebug lkdebug -B 0 0 7379
          4 0000002B4A0A1538     2       0    8267     4         6      0           96   8.016 K    4.14%| oradebug lkdebug -B 2 0 8267
          4 0000002B4A0A1538     2       0    2531     3         7      0           91   7.966 K    4.11%| oradebug lkdebug -B 2 0 2531
          4 0000002B519E4000     1       0   10925     3         5      0           77   7.435 K    3.84%| oradebug lkdebug -B 1 0 10925
          4 0000002B519E4000     1       0   13029     1         5      0           72   7.356 K    3.80%| oradebug lkdebug -B 1 0 13029
    --[[
        &adj: default={1} avg={&V1}
        @CHECK_ACCESS_SL: SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
    --]]
]]*/
col No_Waits,Failed_waits,Waits for tmb3
set feed off verify off
VAR cur REFCURSOR
VAR secs NUMBER;

exec :secs:=regexp_substr('&V1','^\d+$')

DECLARE
    cur   SYS_REFCURSOR;
    V1    VARCHAR2(100):=:V1;
    V2    VARCHAR2(100):=:V2;
    secs  INT :=regexp_substr('&V1','^\d+$');
BEGIN
    IF dbms_db_version.version>11 AND secs IS NOT NULL THEN
        OPEN cur FOR q'[
            WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
                BEGIN
                    IF ID=1 THEN RETURN SYSTIMESTAMP;END IF;
                    &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
                    RETURN SYSTIMESTAMP;
                END;
            SELECT a.*,'|' "|",' oradebug lkdebug -B ' || lmdid || ' ' || groupid || ' ' || BUCKET# oradebug 
            FROM (
                SELECT inst_id,
                       RHT,
                       LMDID,
                       GROUPID,
                       BUCKETIDX  BUCKET#,
                       MAX(CNT)        Items,
                       MAX(MAXCNT)     Max_Items,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*NOWAITCNT)/&adj,2)  No_Waits,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*FAILEDWCNT)/&adj,2) Failed_waits,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*WAITCNT)/&adj,2)    Waits,
                       to_char(100*ratio_to_Report(SUM(DECODE(r, 1, -1, 1)*WAITCNT)) over(),'990.00')||'%' "Waits(%)"
                FROM   (SELECT /*+no_merge ordered use_nl(timer stat)*/ROWNUM r, 
                                sysdate+numtodsinterval(&secs,'second') mr FROM XMLTABLE('1 to 2')) dummy,
                        LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                        LATERAL (SELECT /*+no_merge*/ * FROM table(gv$(cursor(select * from X$KJRTBCFP))) WHERE timer.stime IS NOT NULL) stat
                GROUP  BY inst_id,RHT,LMDID,GROUPID,BUCKETIDX
                HAVING ROUND(SUM(DECODE(r, 1, -1, 1)*WAITCNT)/&adj,2)>0
                ORDER BY Waits DESC
            )  A WHERE ROWNUM<=50]';
    ELSE
        OPEN cur FOR
            SELECT A.*,'|' "|",' oradebug lkdebug -B ' || lmdid || ' ' || groupid || ' ' || BUCKET# oradebug
            FROM   (SELECT A.*, to_char(100*ratio_to_Report(Waits) over(),'990.00')||'%' "Waits(%)"
                    FROM   TABLE(gv$(CURSOR(
                              SELECT inst_id,
                                     RHT,
                                     LMDID,
                                     GROUPID,
                                     BUCKETIDX  BUCKET#,
                                     CNT        Items,
                                     MAXCNT     Max_Items,
                                     NOWAITCNT  No_Waits,
                                     FAILEDWCNT Failed_waits,
                                     WAITCNT    Waits
                              FROM   X$KJRTBCFP
                              WHERE (V1 IS NULL OR ADDR LIKE '%'||upper(V1) or RHT like '%'||upper(V1))
                              AND   (V2 IS NULL OR BUCKETIDX=V2)
                              ORDER  BY waits DESC))) A
                    ORDER  BY waits DESC) A
            WHERE  rownum <= 30;
    END IF;
    :cur := cur;
END;
/
print cur