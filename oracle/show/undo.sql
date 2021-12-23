/*[[Show Undo info]]*/
col "Current|Undo Size,Exp Undo Size|For Retention" format kmg
col "Max|Undo Size" format kmg
col "Necessary|Undo Size" format kmg
col "Max|Used Size" format kmg
col "Undo Size|/ Sec,ActiveS|/ Sec,Expired|/ Sec,Unexpired|/ Sec,Steal-Tries|/ Sec,Steal-Succ|/ Sec,Reused|/Sec" format kmg
SELECT d.inst_id INST,
       d.tablespace_name undo_tbs,
       d.MAXBYTES "Max|Undo Size",
       d.undo_size "Current|Undo Size",
       g.undoblks*block_size "Max|Used Size",
       trim(e.value) "Undo|Retent",
       undo_block_per_sec*block_size*e.value*1.3 "Exp Undo Size|For Retention",
       g.MAXQUERYLEN "Max|Query",
       g.TUNED_UNDORETENTION "Tuned|Retent",
       ROUND((to_number(e.value) * to_number(f.value) * g.undo_block_per_sec)) "Necessary|Undo Size",
       g.MAXTXNCOUNT "Max|TXNs",
       g.MAXCONCURRENCY "Max|CONCURR",
       g.SSOLDERRCNT "ORA1555|Errors",
       g.NOSPACEERRCNT "NoSpace|Errors",
       round(undo_block_per_sec*block_size, 2) "Undo Size|/ Sec",
       round(active_block_per_sec*block_size, 2) "Actives|/ Sec",
       round(expired_block_per_sec*block_size, 2) "Expired|/ Sec",
       round(unexpired_block_per_sec*block_size, 2) "Unexpired|/ Sec",
       round(STEALATTEMPS*block_size, 2) "Steal|Tries/Sec",
       round(STEALSUCC*block_size, 2) "Steal|Succ/Sec",
       round(REUSED*block_size, 2) "Reused|/Sec"
FROM   (SELECT a.inst_id, c.tablespace_name,SUM(a.bytes) undo_size, SUM(d.MAXBYTES) MAXBYTES, MAX(C.BLOCK_SIZE) BLOCK_SIZE
        FROM   gv$datafile a, gv$tablespace b, dba_tablespaces c, dba_data_files d
        WHERE  c.contents = 'UNDO'
        AND    c.status = 'ONLINE'
        AND    b.name = c.tablespace_name
        AND    b.name = d.tablespace_name
        AND    a.file# = d.FILE_ID
        AND    a.inst_id = b.inst_id
        AND    a.ts# = b.ts#
        GROUP  BY a.inst_id,c.tablespace_name) d,
       gv$parameter e,
       gv$parameter f,
       gv$parameter h,
       (SELECT a.inst_id,
               SUM(undoblks / ((end_time - begin_time) * 3600 * 24)) undo_block_per_sec,
               SUM(ACTIVEBLKS / ((end_time - begin_time) * 3600 * 24)) active_block_per_sec,
               SUM(EXPIREDBLKS / ((end_time - begin_time) * 3600 * 24)) expired_block_per_sec,
               SUM(UNEXPIREDBLKS / ((end_time - begin_time) * 3600 * 24)) unexpired_block_per_sec,
               SUM(SSOLDERRCNT) SSOLDERRCNT,
               SUM(NOSPACEERRCNT) NOSPACEERRCNT,
               SUM((UNXPSTEALCNT+EXPSTEALCNT)/ ((end_time - begin_time) * 3600 * 24)) STEALATTEMPS,
               SUM((UNXPBLKRELCNT+EXPBLKRELCNT)/ ((end_time - begin_time) * 3600 * 24)) STEALSUCC,
               SUM((UNXPBLKREUCNT+EXPBLKREUCNT)/ ((end_time - begin_time) * 3600 * 24)) REUSED,
               MAX(UNDOBLKS) UNDOBLKS,
               MAX(TXNCOUNT) MAXTXNCOUNT,
               MAX(MAXQUERYLEN) MAXQUERYLEN,
               MAX(MAXCONCURRENCY) MAXCONCURRENCY,
               MAX(TUNED_UNDORETENTION) TUNED_UNDORETENTION
        FROM   gv$undostat a
        GROUP  BY a.inst_id) g
WHERE  e.name = 'undo_retention'
AND    f.name = 'db_block_size'
AND    h.name = 'undo_tablespace'
AND    h.value = d.tablespace_name
AND    e.inst_id = f.inst_id
AND    e.inst_id = d.inst_id
AND    e.inst_id = h.inst_id
AND    e.inst_id = g.inst_id
order by 1;
