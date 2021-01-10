/*[[Show LMS info]]*/
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
SELECT  INST_ID,INDX,WAIT_TICKET,
        ACTUAL_RCV,
		ROUND(RCVMSG_TIME*1000/ACTUAL_RCV,2) RCV_AVG,
		ROUND(RCVQ_TIME*1000/ACTUAL_RCV,2) RCVQ_AVG,
        LOGICAL_RCV,
        ROUND(LOGICAL_PTIME*1000/LOGICAL_RCV,2) LOG_AVGTIME,
        FC_SENT,NULL_REQ,
        CRB_SENT,
        ROUND(CRB_STIME*1000/CRB_SENT,2) CRB_AVGTIME,
		ERRCHK_TIME,
		SBUF_TIME,
		FMSGBUFS_TIME,
		PBATFLUSH_TIME,
		RCFGFRZ_TIME,
		RCFGSYNC_TIME
		SQFLUSH_TIME,
		DRMSYNC_TIME,
		BPMSG_TIME,
		PMSG_TIME,
		SCANQ_TIME,
		PDCQ_TIME,
		PTOQ_TIME,
		FSCH_TIME,
		IPBAT_TIME,
		RETRYQ_TIME,
		SCANDEFERQ_TIME,
		PRIORITY,
		PRIORITY_CHANGES,
		MAX_RCVQ_LEN,
		CURRENT_RCVQ_LEN,
		CURRENT_LOGICAL_QLEN,
		HWM_RCVQ_TIME
FROM TABLE(GV$(CURSOR(SELECT * FROM X$KJMSDP)))
ORDER BY INST_ID,INDX;