/*[[Show RAC Inter-Connect stats]]*/
SET FEED OFF SEP4K ON
COL ADDR,INDX,CON_ID, NOPRINT
COL BYTES_RECEIVED,BYTES_SENT FORMAT KMG
COL PACKETS_RECEIVED,PACKETS_SENT FORMAT TMB
PRO Inter-Connect Stats:
PRO ===================
SELECT * FROM TABLE(GV$(CURSOR(
    select NVL(b.PUB_KSXPIA,'Y') "PUBLIC",a.* from sys.x$ksxpif a,sys.X$KSXPIA b
    WHERE  a.IF_NAME=b.NAME_KSXPIA(+)
    AND    a.IP_ADDR=b.IP_KSXPIA(+)
)))
ORDER BY inst_id,ip_addr;

PRO Instance Pings:
PRO ===================
SELECT * FROM GV$INSTANCE_PING ORDER BY 1,2;