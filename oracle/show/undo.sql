/*[[Show Undo info]]*/
col "Current Undo Size" format kmg
col "Max Undo Size" format kmg
col "Necessary Undo Size" format kmg
col "Max Used Size" format kmg
col "Undo Size / Sec" format kmg
col MAXQUERYLEN format smhd2
SELECT d.inst_id,
       d.tablespace_name default_undo_tbs,
       d.undo_size "Current Undo Size",
       d.MAXBYTES "Max Undo Size",
       g.undoblks*block_size "Max Used Size",
       SUBSTR(e.value, 1, 25) "UNDO RETENTION",
       round(undo_block_per_sec*block_size, 2) "Undo Size / Sec",
       ROUND((to_number(e.value) * to_number(f.value) * g.undo_block_per_sec)) "Necessary Undo Size"，
       g.MAXTXNCOUNT,
       g.MAXQUERYLEN,
       g.MAXCONCURRENCY
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
               MAX(undoblks / ((end_time - begin_time) * 3600 * 24)) undo_block_per_sec,
               MAX(UNDOBLKS) UNDOBLKS,
               MAX(TXNCOUNT) MAXTXNCOUNT,
               MAX(MAXQUERYLEN) MAXQUERYLEN,
               MAX(MAXCONCURRENCY) MAXCONCURRENCY
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
