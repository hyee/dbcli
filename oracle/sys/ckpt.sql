/*[[Show CKPT info]]*/
SET FEED OFF
pro x$activeckpt
pro ============
SELECT inst_id,
       decode(ckpt_type,
              0,'PQ induced',
              1,'Instance recovery',
              2,'Media recovery',
              3,'Thread',
              4,'Interval',
              5,'Tablespace',
              6,'Close db',
              7,'Incremental',
              8,'Local db',
              9,'Global db',
              10,'Obj reuse/trunc',
              11,'Object',
              12,'Reuse Blk Range') ckpt_type,
       ckpt_priority  pri,
       ckpt_flags     flags,
       NXT_ACT_ENT,
       PRV_ACT_ENT,
       NXT_CHLD_ENT,
       PRV_CHLD_ENT,
       CKPT_SCN_BAS,
       CKPT_SCN_WRP,
       CKPT_TIM,
       CKPT_ALLOC_THR ALLOC_THR,
       CKPT_RBA_SEQ   RBA_SEQ,
       CKPT_RBA_BNO   RBA_BNO,
       CKPT_RBA_BOF   RBA_BOF
FROM   TABLE(gv$(CURSOR (SELECT * FROM sys.x$activeckpt WHERE ckpt_type > 0)))
order  by 1,2;

pro x$ckptbuf
pro ============
SELECT inst_id,
       QUEUE_NUM,
       BUF_RBA_SEQ logfile#,
       BUF_STATE,
       count(distinct SET_NUM) sets,
       COUNT(DISTINCT BUF_DBABLK) BLOCKS,
       SUM(BUF_COUNT) BUFFS,
       COUNT(distinct nullif(BUF_RBA_BNO,0)) NUM_RBA_BNO,
       COUNT(distinct nullif(BUF_RBA_BOF,0)) NUM_RBA_BOF
FROM   TABLE(gv$(CURSOR(SELECT * FROM sys.x$ckptbuf WHERE BUF_RBA_SEQ > 0 AND rawtohex(buf_ptr) != '00')))
GROUP BY inst_id,QUEUE_NUM,BUF_STATE,BUF_RBA_SEQ
ORDER BY 1,2,3;

pro gv$instance_recovery
pro ==============================
SELECT * FROM gv$instance_recovery
ORDER BY 1,2,3