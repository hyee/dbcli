/*[[Show Undo info
    --[[--
        @insts: 11.2={listagg(b.inst_id) within group(order by b.inst_id)} {default=to_char(wmsys.wm_concat(b.inst_id))}
        @CHECK_ACCESS_PARAMETERS: {
            sys.x$ksppi={
               (SELECT ksppinm NAME,ksppity TYPE, ksppstdvl VALUE,ksppstdf isdefault,ksppdesc DESCRIPTION
                FROM   sys.x$ksppcv y
                JOIN   sys.x$ksppi x
                USING(indx))}
            default={(select '' name,0 type,'' value,'Y' isdefault,'' description from dual)}
        }
    --]]--
]]*/
col "Current|Undo Size,Exp Undo Size|For Retention,HWM|Roll Size" format kmg
col "Max|Undo Size,Current|Roll Size,Avg Active|Roll Size,Avg|Extent Size" format kmg
col "Necessary|Undo Size" format kmg
col "Max|Used Size,BYTES,BLOCK_SIZE" format kmg
col "Undo Size|/ Sec,ActiveS|/ Sec,Expired|/ Sec,Unexpired|/ Sec,Steal-Tries|/ Sec,Steal-Succ|/ Sec,Reused|/Sec" format kmg
col "Total|Header Gets,Total|Header Waits,Total|Shrinks,Total|Extends" FOR TMB
SET FEED OFF

PRO Undo Parameters in Current Instance:
PRO ====================================
SELECT name,type,value,isdefault,description
FROM   v$parameter
WHERE  upper(name||'.'||description) LIKE '%UNDO%'
OR     (name IN('_ktb_debug_flags','_lm_drm_disable') AND bitand(0+value,2)=2 OR
     name='_smu_debug_mode' AND value='33554432')
UNION
SELECT *
FROM   &CHECK_ACCESS_PARAMETERS
WHERE  name IN('_enable_default_temp_threshold',
              '_enable_default_undo_threshold',
              '_gc_undo_affinity',
              '_gc_undo_rdma_read',
              '_offline_rollback_segments',
              '_highthreshold_undoretention',
              '_in_memory_undo',
              '_rollback_segment_count',
              '_temp_undo_disable_adg',
              '_undo_autotune',
              '_undo_block_compression'
              )
ORDER  BY 1;


PRO DBA_UNDO_EXTENTS:
PRO =================
SELECT &insts inst,
       decode(seq, 1, owner) owner,
       decode(seq, 1, undo_tbs) undo_tbs,
       status,
       max(segments) segments,
       max(extents) extents,
       max(blocks) blocks,
       max(bytes) bytes,
       max(block_size) block_size
FROM   (SELECT owner,
               tablespace_name undo_tbs,
               status,
               count(DISTINCT segment_name) segments,
               count(1) extents,
               sum(blocks) blocks,
               sum(bytes) bytes,
               sum(bytes) / sum(blocks) block_size,
               row_number() OVER(PARTITION BY owner, tablespace_name ORDER BY status) seq
        FROM   dba_undo_extents a
        GROUP  BY owner, tablespace_name, status) a
LEFT   JOIN (SELECT inst_id, value FROM gv$parameter WHERE name = 'undo_tablespace') b
ON     a.undo_tbs = b.value
AND    a.seq = 1
GROUP  BY a.owner, a.undo_tbs, a.status, seq
ORDER  BY a.owner, a.undo_tbs, a.status;

PRO GV$ROLLSTAT:
PRO ============

SELECT decode(row_number() OVER(PARTITION BY inst_id ORDER BY 1),1,inst_id) inst,
       decode(xacts,0,status,'ACTIVE') status,
       count(1) segs,
       sum(xacts) "Current|Transactions",
       sum(extents) "Current|Extents",
       sum(rssize) "Current|Roll Size",
       round(sum(rssize)/nullif(sum(extents),0))  "Avg|Extent Size",
       '|' "|",
       sum(aveactive) "Avg Active|Roll Size",
       sum(hwmsize) "HWM|Roll Size",
       sum(gets) "Total|Header Gets",
       sum(waits) "Total|Header Waits",
       sum(shrinks) "Total|Shrinks",
       sum(extends) "Total|Extends"
FROM   gv$rollstat
GROUP  BY inst_id,decode(xacts,0,status,'ACTIVE')
ORDER  BY inst_id,2;

PRO GV$UNDOSTAT:
PRO ============
SELECT /*+opt_param('optimizer_dynamic_sampling' 5) no_merge(g) no_merge(d)*/
       d.inst_id inst,
       d.tablespace_name undo_tbs,
       d.maxbytes "Max|Undo Size",
       d.undo_size "Current|Undo Size",
       g.undoblks*block_size "Max|Used Size",
       trim(e.value) "Undo|Retent",
       undo_block_per_sec*block_size*e.value*1.3 "Exp Undo Size|For Retention",
       g.maxquerylen "Max|Query",
       g.maxqueryid  "Max|SQLId",
       g.tuned_undoretention "Tuned|Retent",
       round((to_number(e.value) * to_number(f.value) * g.undo_block_per_sec)) "Necessary|Undo Size",
       g.maxtxncount "Max|TXNs",
       g.maxconcurrency "Max|CONCURR",
       g.ssolderrcnt "ORA1555|Errors",
       g.nospaceerrcnt "NoSpace|Errors",
       round(undo_block_per_sec*block_size, 2) "Undo Size|/ Sec",
       round(active_block_per_sec*block_size, 2) "Actives|/ Sec",
       round(expired_block_per_sec*block_size, 2) "Expired|/ Sec",
       round(unexpired_block_per_sec*block_size, 2) "Unexpired|/ Sec",
       round(stealattemps*block_size, 2) "Steal|Tries/Sec",
       round(stealsucc*block_size, 2) "Steal|Succ/Sec",
       round(reused*block_size, 2) "Reused|/Sec"
FROM   (SELECT a.inst_id, c.tablespace_name,sum(a.bytes) undo_size, sum(d.maxbytes) maxbytes, max(c.block_size) block_size
        FROM   gv$datafile a, gv$tablespace b, dba_tablespaces c, dba_data_files d
        WHERE  c.contents = 'UNDO'
        AND    c.status = 'ONLINE'
        AND    b.name = c.tablespace_name
        AND    b.name = d.tablespace_name
        AND    a.file# = d.file_id
        AND    a.inst_id = b.inst_id
        AND    a.ts# = b.ts#
        GROUP  BY a.inst_id,c.tablespace_name) d,
       gv$parameter e,
       gv$parameter f,
       gv$parameter h,
       (SELECT a.inst_id,
               sum(undoblks / ((end_time - begin_time) * 3600 * 24)) undo_block_per_sec,
               sum(activeblks / ((end_time - begin_time) * 3600 * 24)) active_block_per_sec,
               sum(expiredblks / ((end_time - begin_time) * 3600 * 24)) expired_block_per_sec,
               sum(unexpiredblks / ((end_time - begin_time) * 3600 * 24)) unexpired_block_per_sec,
               sum(ssolderrcnt) ssolderrcnt,
               sum(nospaceerrcnt) nospaceerrcnt,
               sum((unxpstealcnt+expstealcnt)/ ((end_time - begin_time) * 3600 * 24)) stealattemps,
               sum((unxpblkrelcnt+expblkrelcnt)/ ((end_time - begin_time) * 3600 * 24)) stealsucc,
               sum((unxpblkreucnt+expblkreucnt)/ ((end_time - begin_time) * 3600 * 24)) reused,
               max(undoblks) undoblks,
               max(txncount) maxtxncount,
               max(maxquerylen) maxquerylen,
               max(maxqueryid) KEEP(dense_rank LAST ORDER BY maxquerylen) maxqueryid,
               max(maxconcurrency) maxconcurrency,
               max(tuned_undoretention) tuned_undoretention
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
ORDER  BY 1;
