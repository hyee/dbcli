/*[[Show log buffer information]]*/
SET FEED OFF
COL total_size,avg_size for kmg
PRO Preferred Log_buffer = 1.5 * (redo size / second)
sys param _log_parallelism _log_private "log buffer" "memory undo"
PRO Redo Strands
PRO ============
SELECT * FROM TABLE(GV$(CURSOR(
    SELECT Userenv('instance') inst,
           DECODE(last_buf_kcrfa,'00','Private Strands','Shared Strands') typ,
           COUNT(1) Strands,
           SUM(strand_size_kcrfa) total_size,
           AVG(strand_size_kcrfa) avg_size
    FROM   sys.x$kcrfstrand
    GROUP BY DECODE(last_buf_kcrfa,'00','Private Strands','Shared Strands')
))) LEFT JOIN  TABLE(GV$(CURSOR(
    SELECT Userenv('instance') inst,
           decode(bitand(ktcxbflg, 4096),0,'Private Strands','Shared Strands') typ,
           COUNT(1) transactions
    FROM   sys.x$ktcxb   
    WHERE  bitand(ksspaflg, 1) != 0   
      AND  bitand(ktcxbflg, 2) != 0
    GROUP BY decode(bitand(ktcxbflg, 4096),0,'Private Strands','Shared Strands')
))) USING(inst,typ)
ORDER BY 1,2;

PRO Redo Allocations 
PRO ================
SELECT * FROM gv$sysstat where name in('redo buffer allocation retries','redo entries') ORDER BY 1,name;

SELECT * FROM gv$system_event 
where event in('log buffer space','latch: redo allocation','latch: redo copy','latch: redo writing') 
ORDER BY 1,event;

WITH A AS(
    SELECT inst_id,name,
           count(1) latches
    FROM gv$latch_children 
    where name in('redo copy','redo allocation','redo writing')
    GROUP BY inst_id,name)
SELECT /*+OUTLINE_LEAF*/
       inst_id,name "Latch Name",
       NVL(A.LATCHES,1) latches,
       B.gets,
       B.MISSES, 
       B.SLEEPS, 
       B.IMMEDIATE_GETS, 
       B.IMMEDIATE_MISSES, 
       B.SPIN_GETS, 
       B.WAIT_TIME
FROM gv$latch B
LEFT JOIN A USING(INST_ID,NAME)
WHERE name in('redo copy','redo allocation','redo writing')
ORDER BY 1,2;