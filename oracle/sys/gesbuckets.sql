/*[[
    Show GES resource hash bucket info. Usage: @@NAME {[RHT] [Bucket#]} | {<sample secs> [-avg]} 
    
    Mainly used to diagnostic below the "latch: ges resource hash list" events, output similar command with "oradebug lkdebug -a hashcount"
    
    Refer to bug# 29878037/29922435
    Relative parameters:
      _ges_server_processes : number of LMD processes
      _lm_res_hash_buckets  : (64k in 11g and 32k in 18c)
      _lm_res_tm_hash_bucket: unit is percentage of resource hash bucket(_lm_res_hash_buckets) used for tm enqueue

    Examples:
    =========
    SQL> SYS GESBUCKETS . 191
    INST_ID       RHT        LMDID GROUPID BUCKET# ITEMS MAX_ITEMS NO_WAITS Fails   WAITS   Waits(%)|          ORADEBUG
    ------- ---------------- ----- ------- ------- ----- --------- -------- ------------ --------- --------+----------------------------
          1 0000002B592A0A58     0       0     191     2        53    160            0   137.175 K   55.31%| oradebug lkdebug -B 0 0 191
          3 0000002B592A0A58     0       0     191     3        53    125           11    37.395 K   15.08%| oradebug lkdebug -B 0 0 191
          2 0000002B592A0A58     0       0     191     5        33    124            0    36.625 K   14.77%| oradebug lkdebug -B 0 0 191
          4 0000002B519E4000     1       0     191     1         7     90           39    14.361 K    5.79%| oradebug lkdebug -B 1 0 191

    SQL> SYS GESBUCKETS 10 -avg
    INST_ID       RHT        LMDID GROUPID BUCKET# ITEMS MAX_ITEMS NO_WAITS Fails  WAITS  Waits(%)|           ORADEBUG
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
        @VER: 12={}
    --]]
]]*/
col No_Waits,Fails,Waits,sleeps,spins for tmb3
col wait_time for usmhd2
col groupid noprint
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
            SELECT A.*,'|' "|",decode(RHT,'|',
                  ' Avg Waits='||rpad(round(Waits/BUCKET#,3),6)||' Free(%)='|| ROUND(100*(BUCKET#-BUSYS)/BUCKET#,2),
                  ' oradebug lkdebug -B ' || lmdid || ' ' || groupid || ' ' || BUCKET#) memo
            FROM   (
                SELECT decode(grouping_id(lmdid),1,'$REV$$UDL$')||lpad(inst_id,4) inst,
                       NVL(''||RHT,'|') RHT,
                       ''||LATCH# LATCH#,
                       Nvl(''||LMDID,'*') LMDID,
                       Nvl(''||GROUPID,'*') GROUPID,
                       NVL(BUCKETIDX,COUNT(1)/2) BUCKET#,
                       decode(grouping_id(LMDID,RHT),
                           0,SIGN(SUM(DECODE(r, 1, -1, 1)*(NOWAITCNT+FAILEDWCNT+WAITCNT))),
                           1,SUM(SIGN(SUM(DECODE(r, 1, -1, 1)*(NOWAITCNT+FAILEDWCNT+WAITCNT)))) OVER(PARTITION BY INST_ID,LMDID ORDER BY LATCH#),
                           3,SUM(SIGN(SUM(DECODE(r, 1, -1, 1)*(NOWAITCNT+FAILEDWCNT+WAITCNT)))) OVER(PARTITION BY INST_ID ORDER BY LMDID,LATCH#)-1) BUSYS,
                       nvl2(RHT,MAX(CNT),ROUND(SUM(CNT)/2)) Items,
                       nvl2(RHT,MAX(MAXCNT),ROUND(SUM(MAXCNT)/2)) Max_Items,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*NOWAITCNT)/&adj,2)  No_Waits,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*FAILEDWCNT)/&adj,2) Fails,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*sleeps)/&adj,2)     sleeps,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*spins)/&adj,2)      spins,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*wait_time)/&adj,2)  wait_time,
                       ROUND(SUM(DECODE(r, 1, -1, 1)*WAITCNT)/&adj,2)    Waits,
                       to_char(100*ratio_to_Report(SUM(DECODE(r, 1, -1, 1)*WAITCNT)) over(PARTITION BY grouping_id(LMDID,RHT)),'990.00')||'%' "Waits(%)"
                FROM   (SELECT /*+no_merge ordered use_nl(timer stat)*/ROWNUM r, 
                                sysdate+numtodsinterval(&secs,'second') mr FROM XMLTABLE('1 to 2')) dummy,
                        LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                        LATERAL (SELECT /*+no_merge*/ * 
                                 FROM TABLE(gv$(cursor(
                                     SELECT /*+ordered use_hash(a b)*/ 
                                            a.*,b.addr latch#,b.sleeps,b.spin_gets spins,b.wait_time
                                     FROM   sys.X$KJRTBCFP a,v$latch_children b
                                     WHERE  b.name(+) = 'ges resource hash list'
                                     AND    b.child#(+)=a.indx+1))) 
                                 WHERE timer.stime IS NOT NULL) stat
                GROUP  BY inst_id,Rollup((LMDID,GROUPID),(RHT,BUCKETIDX,LATCH#))
                ORDER  BY decode(RHT,'|',inst_id*100+nvl(regexp_substr(lmdid,'\d+'),'99'),9999),Waits desc
            ) A
            WHERE BUSYS>0 AND ROWNUM<=60]';
    ELSE
        OPEN cur FOR
            WITH stats as(
                    SELECT /*+inline*/ A.*, to_char(100*ratio_to_Report(Waits) over(partition by inst),'990.00')||'%' "Waits(%)"
                    FROM   TABLE(gv$(CURSOR(
                              SELECT inst_id inst,
                                     ''||RHT RHT,
                                     ''||b.addr LATCH#,
                                     ''||LMDID LMDID,
                                     ''||GROUPID GROUPID,
                                     BUCKETIDX  BUCKET#,
                                     CNT        Items,
                                     MAXCNT     Max_Items,
                                     NOWAITCNT  No_Waits,
                                     WAITCNT    Waits,
                                     FAILEDWCNT Fails,
                                     b.sleeps,
                                     b.spin_gets spins,
                                     b.wait_time
                              FROM   sys.X$KJRTBCFP a,v$latch_children b
                              WHERE  b.name(+) = 'ges resource hash list'
                              AND    b.child#(+)=a.indx+1
                              AND   (V1 IS NULL OR RHT like '%'||upper(V1))
                              AND   (V2 IS NULL OR BUCKETIDX=V2)
                              ORDER  BY waits DESC))) A
                    ORDER  BY waits DESC)
            SELECT lpad(rownum,2) "#", A.*,'|' "|",' oradebug lkdebug -B ' || lmdid || ' ' || groupid || ' ' || BUCKET# memo
            FROM   stats A
            WHERE  rownum <= 30
            UNION ALL
            SELECT '-',null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null from dual
            UNION ALL
            SELECT * FROM (
              SELECT decode(grouping_id(lmdid),1,'$GREPCOLOR$'),
                     inst,'ALL Buckets',null,
                     nvl(lmdid,'*'),nvl(groupid,'*'),count(1),sum(Items),sum(Max_Items),sum(No_Waits),sum(Fails),sum(Waits),
                     sum(sleeps),sum(spins),sum(wait_time),
                     to_char(100*ratio_to_Report(sum(Waits)) over(PARTITION BY grouping_id(LMDID)),'990.00')||'%' "Waits(%)",
                     '|' "|",'Avg Items|Waits ='||to_char(round(sum(Items)/count(1)),'990.9')||'|'||round(sum(Waits)/count(1),2)
              FROM   stats
              GROUP  BY inst,rollup((lmdid,groupid))
              ORDER  BY 2,4,5);
    END IF;
    :cur := cur;
END;
/
print cur