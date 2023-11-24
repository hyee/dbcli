/*[[Show log buffer information]]*/

COL total_size,avg_size for kmg
sys param _log_parallelism _log_private log_buffer
PRO Redo Strands
PRO ============
SELECT * FROM TABLE(GV$(CURSOR(
    SELECT Userenv('instance') inst,
           DECODE(last_buf_kcrfa,'00','Private Strands','Shared Strands') typ,
           COUNT(1) Strands,
           SUM(strand_size_kcrfa) total_size,
           AVG(strand_size_kcrfa) avg_size
    FROM   x$kcrfstrand
    GROUP BY DECODE(last_buf_kcrfa,'00','Private Strands','Shared Strands')
))) LEFT JOIN  TABLE(GV$(CURSOR(
    SELECT Userenv('instance') inst,
           decode(bitand(ktcxbflg, 4096),0,'Private Strands','Shared Strands') typ,
           COUNT(1) transactions
    FROM   x$ktcxb   
    WHERE  bitand(ksspaflg, 1) != 0   
      AND  bitand(ktcxbflg, 2) != 0
    GROUP BY decode(bitand(ktcxbflg, 4096),0,'Private Strands','Shared Strands')
))) USING(inst,typ)
ORDER BY 1,2;