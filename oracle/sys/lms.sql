/*[[Show LMS info]]*/
SET FEED OFF
COL ADDR,FLAG NOPRINT
COL ACTUAL_RCV for tmb Head  "Actual|Msg Rcv"
COL RCV_AVG for usmhd2 Head  "Rcv Msg|Avg Tim"
COL RCVQ_AVG for usmhd2 Head  "Rcv Msg|Avg Que"
COL LOGICAL_RCV for tmb Head  "Logical|Msg Rcv"
COL LOG_AVGTIME for usmhd2 Head  "Logi-Msg|Proc Avg"
COL FC_SENT for tmb HEAD "Flow Ctrl|Msg Sent"
COL NULL_REQ for TMB HEAD "Null Req|Sent"
COL WAIT_TICKET for TMB HEAD "LMS TCK|Waits"
COL CRB_SENT for TMB HEAD "GC CR|Sent"
COL CRB_AVGTIME for usmhd2 HEAD "GC CR|Avg Time"
COL RCVQ_TIME for msmhd2 Head  "Rcv-Msg|Queue"
COL SQFLUSH_TIME for msmhd2 Head  "Sent-Que|Flush"
COL ERRCHK_TIME for msmhd2 Head  "Error|Check"
COL SBUF_TIME for msmhd2 Head  "Flush-Sent|Buff Time"
COL FMSGBUFS_TIME for msmhd2 Head  "Flush-Msg|Buff Time"
COL PBATFLUSH_TIME for msmhd2 Head  "Flush-Msg|Batch Proc"
COL RCFGFRZ_TIME for msmhd2 Head  "Reconfig|Freezed"
COL RCFGSYNC_TIME for msmhd2 Head  "Reconfig|Synched"
COL DRMSYNC_TIME for msmhd2 Head  "DRM|Sync"
COL BPMSG_TIME for msmhd2 Head  "Batch-Msg|Processed"
COL PMSG_TIME for msmhd2 Head  "Proce-Msg|from Rcver"
COL SCANQ_TIME for msmhd2 Head  "Scan|Queue"
COL PDCQ_TIME for msmhd2 Head  "Down-Conv|Queue"
COL PTOQ_TIME for msmhd2 Head  "Defer-Ping|Queue"
COL FSCH_TIME for msmhd2 Head  "Flush Side|Channel"
COL IPBAT_TIME for msmhd2 Head  "Embed Batch|Msg"
COL RETRYQ_TIME for msmhd2 Head  "Retry|Queue"
pro X$KJMSDP:
pro =========
SELECT  INST_ID INST,spid,
        PRIORITY "PRIOR",
        SUM(PRIORITY_CHANGES) PRIOR_CHGS,
        count(1) threads,
        SUM(WAIT_TICKET) WAIT_TICKET,
        AVG(ACTUAL_RCV) ACTUAL_RCV,
        ROUND(SUM(RCVMSG_TIME)*1000/SUM(ACTUAL_RCV),2) RCV_AVG,
        ROUND(SUM(RCVQ_TIME)*1000/SUM(ACTUAL_RCV),2) RCVQ_AVG,
        SUM(LOGICAL_RCV) LOGICAL_RCV,
        ROUND(SUM(LOGICAL_PTIME)*1000/SUM(LOGICAL_RCV),2) LOG_AVGTIME,
        SUM(FC_SENT) FC_SENT,
        SUM(NULL_REQ) NULL_REQ,
        SUM(CRB_SENT) CRB_SENT,
        ROUND(SUM(CRB_STIME)*1000/SUM(CRB_SENT),2) CRB_AVGTIME,
        SUM(ERRCHK_TIME) ERRCHK_TIME,
        SUM(SBUF_TIME) SBUF_TIME,
        SUM(FMSGBUFS_TIME) FMSGBUFS_TIME,
        SUM(PBATFLUSH_TIME) PBATFLUSH_TIME,
        SUM(RCFGFRZ_TIME) RCFGFRZ_TIME,
        SUM(RCFGSYNC_TIME) RCFGSYNC_TIME,
        SUM(SQFLUSH_TIME) SQFLUSH_TIME,
        SUM(DRMSYNC_TIME) DRMSYNC_TIME,
        SUM(BPMSG_TIME) BPMSG_TIME,
        SUM(PMSG_TIME) PMSG_TIME,
        SUM(SCANQ_TIME) SCANQ_TIME,
        SUM(PDCQ_TIME) PDCQ_TIME,
        SUM(PTOQ_TIME) PTOQ_TIME,
        SUM(FSCH_TIME) FSCH_TIME,
        SUM(IPBAT_TIME) IPBAT_TIME,
        SUM(RETRYQ_TIME) RETRYQ_TIME,
        SUM(SCANDEFERQ_TIME) SCANDEFERQ_TIME
             /*,
        PRIORITY_CHANGES,
        MAX_RCVQ_LEN,
        CURRENT_RCVQ_LEN,
        CURRENT_LOGICAL_QLEN,
        HWM_RCVQ_TIME*/
FROM TABLE(GV$(CURSOR(SELECT a.*,b.spid FROM sys.X$KJMSDP a,v$process b where a.pid=b.pid)))
GROUP BY INST_ID,SPID,PRIORITY
ORDER BY INST_ID,SPID;

RAC LMS