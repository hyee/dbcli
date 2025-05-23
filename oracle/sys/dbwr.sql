/*[[Show DBWR/LRU info]]*/
col gid noprint
set feed off
pro x$kcbwds
pro ========
SELECT grouping_id(inst_id,dbwr_num) gid,
       nvl2(inst_id,''||inst_id,'*') inst,
       nvl2(dbwr_num,'DBW' || decode(sign(dbwr_num - 10), -1, '' || dbwr_num, chr(87 + dbwr_num)),'*') dbwr_num,
       BP_NAME pool,
       count(1) "Work|Sets",
       SUM(cnum_set) "Work Set|Blocks",
       SUM(cnum_repl) "REPL Chain|Blocks",
       SUM(anum_repl) "Aux Chain|Blocks",
       SUM(DBINSP) "Dirty|Blocks",
       SUM(FBINSP) "Free|Blocks",
       SUM(fbwait) "Free Buff|Waits",
       SUM(bbwait) "Buff Busy|Waits",
       SUM(wcwait) "Write Complete|Waits"
FROM   TABLE(gv$(CURSOR(
    SELECT a.*,b.bp_name 
    FROM sys.x$kcbwds a,sys.x$kcbwbpd b
    WHERE cnum_set > 0
    AND   a.set_id between b.BP_LO_SID and b.BP_HI_SID)))
GROUP  BY ROLLUP(inst_id,BP_NAME,dbwr_num)
ORDER  BY 1,2, 3, pool;
pro x$kcbbhs
pro ========
SELECT * FROM TABLE(gv$(CURSOR(select * from sys.X$KCBBHS where ISSUED > 0))) order by 1,2,3;

PRO x$kvii
pro ========
SELECT * FROM TABLE(gv$(CURSOR(select INST_ID,INDX,KVIIVAL,KVIITAG,KVIIDSC from sys.x$kvii))) ORDER BY INDX,INST_ID;
--From Tanel Poder
pro x$kcbbes
pro ========
SELECT * FROM TABLE(gv$(CURSOR(
       SELECT inst_id,indx,
              CASE indx
                  WHEN 0 THEN
                   'Invalid Reason'
                  WHEN 1 THEN
                   'Ping Write'
                  WHEN 2 THEN
                   'High Prio Thread Ckpt'
                  WHEN 3 THEN
                   'Instance Recovery Ckpt'
                  WHEN 4 THEN
                   'Med Prio (incr) Ckpt'
                  WHEN 5 THEN
                   'Aging Writes'
                  WHEN 6 THEN
                   'Media Recovery Ckpt'
                  WHEN 7 THEN
                   'Low Prio Thread Ckpt'
                  WHEN 8 THEN
                   'Tablespace Ckpt'
                  WHEN 9 THEN
                   'Reuse Object Ckpt'
                  WHEN 10 THEN
                   'Reuse Block Range Ckpt'
                  WHEN 11 THEN
                   'Limit Dirty Buff Ckpt'
                  WHEN 12 THEN
                   'Smart Scan Ckpt'
                  WHEN 14 THEN
                   'Direct Path Read Ckpt'
              END reason_name,
              reason reason_buff,
              ROUND(NULLIF(RATIO_TO_REPORT(reason) OVER() * 100, 0), 1) "REASON%",
              CASE indx
                  WHEN 0 THEN
                   'Invalid Priority'
                  WHEN 1 THEN
                   'High Priority'
                  WHEN 2 THEN
                   'Medium Priority'
                  WHEN 3 THEN
                   'Low Priority'
              END prior_name,
              priority prior_buff,
              ROUND(NULLIF(RATIO_TO_REPORT(priority) OVER() * 100, 0), 1) "PRIO%",
              CASE indx
                  WHEN 0 THEN
                   'Queued For Writing'
                  WHEN 1 THEN
                   'Deferred (log file sync)'
                  WHEN 2 THEN
                   'Already being written'
                  WHEN 3 THEN
                   'Buffer not dirty'
                  WHEN 4 THEN
                   'Buffer is pinned'
                  WHEN 5 THEN
                   'I/O limit reached'
                  WHEN 6 THEN
                   'Buffer logically flushed'
                  WHEN 7 THEN
                   'No free IO slots'
              END io_proc_status,
              savecode io_count,
              ROUND(NULLIF(RATIO_TO_REPORT(savecode) OVER() * 100, 0), 1) "STATUS%"
       FROM   sys.x$kcbbes
       WHERE  GREATEST(reason, priority, savecode) > 0)))
ORDER BY indx,inst_id;