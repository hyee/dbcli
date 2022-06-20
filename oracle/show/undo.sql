/*[[Show Undo info
    --[[--
        @insts: 11.2={listagg(b.inst_id) within group(order by b.inst_id)} {default=to_char(wmsys.wm_concat(b.inst_id))}
    --]]--
]]*/
col "Current|Undo Size,Exp Undo Size|For Retention" format kmg
col "Max|Undo Size,Current|Undo Size,Avg Active|Undo Size" format kmg
col "Necessary|Undo Size" format kmg
col "Max|Used Size,BYTES,BLOCK_SIZE" format kmg
col "Undo Size|/ Sec,ActiveS|/ Sec,Expired|/ Sec,Unexpired|/ Sec,Steal-Tries|/ Sec,Steal-Succ|/ Sec,Reused|/Sec" format kmg
SET FEED OFF

PRO DBA_UNDO_EXTENTS:
PRO =================
SELECT &insts inst,
       decode(seq, 1, owner) owner,
       decode(seq, 1, undo_tbs) undo_tbs,
       status,
       MAX(segments) segments,
       MAX(extents) extents,
       MAX(BLOCKS) BLOCKS,
       MAX(BYTES) BYTES,
       MAX(BLOCK_SIZE) BLOCK_SIZE
FROM   (SELECT OWNER,
               TABLESPACE_NAME undo_tbs,
               STATUS,
               COUNT(DISTINCT SEGMENT_NAME) SEGMENTS,
               COUNT(1) EXTENTS,
               SUM(BLOCKS) BLOCKS,
               SUM(BYTES) BYTES,
               SUM(BYTES) / SUM(BLOCKS) BLOCK_SIZE,
               row_number() over(PARTITION BY owner, tablespace_name ORDER BY status) seq
        FROM   DBA_UNDO_EXTENTS A
        GROUP  BY OWNER, TABLESPACE_NAME, STATUS) a
LEFT   JOIN (SELECT INST_ID, VALUE FROM GV$PARAMETER WHERE NAME = 'undo_tablespace') B
ON     A.undo_tbs = B.VALUE
AND    A.SEQ = 1
GROUP  BY a.owner, a.undo_tbs, a.status, seq
ORDER  BY a.owner, a.undo_tbs, a.status;

PRO GV$ROLLSTAT:
PRO ============

SELECT decode(row_number() over(partition by INST_ID order by 1),1,INST_ID) inst,
       DECODE(XACTS,0,STATUS,'ACTIVE') STATUS,
       COUNT(1) SEGS,
       SUM(XACTS) "Current|Transactions",
       SUM(RSSIZE) "Current|Undo Size",
       SUM(RSSIZE) "Avg Active|Undo Size"
FROM   GV$ROLLSTAT
GROUP  BY INST_ID,DECODE(XACTS,0,STATUS,'ACTIVE')
ORDER BY 1,2;

PRO GV$UNDOSTAT:
PRO ============
SELECT /*+opt_param('optimizer_dynamic_sampling' 5) no_merge(g) no_merge(d)*/
       d.inst_id INST,
       d.tablespace_name undo_tbs,
       d.MAXBYTES "Max|Undo Size",
       d.undo_size "Current|Undo Size",
       g.undoblks*block_size "Max|Used Size",
       trim(e.value) "Undo|Retent",
       undo_block_per_sec*block_size*e.value*1.3 "Exp Undo Size|For Retention",
       g.MAXQUERYLEN "Max|Query",
       g.MAXQUERYID  "Max|SQLId",
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
               MAX(MAXQUERYID) KEEP(DENSE_RANK LAST ORDER BY MAXQUERYLEN) MAXQUERYID,
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
