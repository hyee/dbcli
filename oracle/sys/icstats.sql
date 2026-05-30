/*[[
    Show RAC Inter-Connect devices stats.

    Fields:
    =======
    * RX Errors       : Receive Errors
    * RX Align Err    : The most possible reason is Network Cable or RJ45 plug issue, then Network Switch issue
    * RX Frame Err    : Similar to RX Align Err
    * RX Len Err      : Similar to RX Align Err
    * RX CRC Err      : Ethernet Card or Network Swich mode is incompatible, all should be Full-Duplex mode and the same network speed
    *                   check speed and duplex mode: ethtool eth0
    *                   set speed and duplex mode  : ethtool -s eth0 speed 10000 duplex full autoneg off
    * RX Misses Err   : Package has not entered Ring Buffer due to the queue is full, could be lack of Right Buffer lack of CPU or the capacity of Ethernet Card
    *                   check Ring Buffer: ethtool -g eth0
    *                   set Ring Buffer: ethtool -G eth0 rx 4096 tx 4096 txqueuelen 10000 rxqueuelen 10000
    *                   change sysctl: net.core.netdev_max_backlog=30000
    *                   /etc/sysconfig/network-scripts/ifcfg-eth0: ETHTOOL_OPTS="-G eth0 rx 4096 tx 4096"
    * RX OverRun Err  : Similar to RX Misses
    * RX Fifo Err     : Similar to RX Misses, but the queue is not full
    * RX Drops        : Package has entered Ring Buffer, but was dropped due to lack of kernel resource (Memory,Socket buffer,etc)
    *                   adjust: net.ipv4.tcp_rmem , net.core.rmem_max, net.core.netdev_max_backlog, rx 4096
    *                   for TX: net.ipv4.tcp_wmem , net.core.wmem_max, net.core.netdev_max_backlog, tx 4096
    * TX Window Err   : Similar to RX Align/Frame/Len errs, possible Half-Duplex delay issue
    * TX Heartbeat Err: Cable/plug/Switch issue
    * TX Aborter   Err: Similar to TX Heartbeat issue
    * TX TCP Seg Fails: TSO/MTU/driver issue
    *                   check: ethtool -a eth0
    *                   set : ethtool -A  eth0 tx off
    * TX Carrier Err  : Similar to RX Align/Frame/Len errs           

    --[[
        @check_access_nmon: {
            SYS.X$KSNMON_IF={
                PRO NMON INFO(Similar to `ethtool -S`):
                PRO ===================================
                SELECT *
                FROM   TABLE(gv$(CURSOR((SELECT USERENV('instance') "Inst|Id",
                               i.KSNMONIF_IFNAME "IF|Name",
                               MAX(KSNMONIFSTS_TMSTMP+0) "Stats|Timestamp",
                               REGEXP_REPLACE(KSNMONIFSTS_NAME, 'queue_\d+\_', 'queue_') NAME,
                               NULLIF(SUM(KSNMONIFSTS_VALUE),0) VALUE
                        FROM   SYS.X$KSNMON_IF I, SYS.X$KSNMON_IFSTSALL S
                        WHERE  i.KSNMONIF_IFIDX = s.KSNMONIFSTS_IFIDX
                        GROUP  BY i.KSNMONIF_IFNAME, REGEXP_REPLACE(KSNMONIFSTS_NAME, 'queue_\d+\_', 'queue_')))))
                PIVOT(SUM(VALUE)
                      FOR NAME IN('rx_bytes' "RX|Bytes",
                                  'rx_packets' "RX|Packs",
                                  'rx_multicast' "RX_Packs|Multicast",
                                  'rx_multicast_drops' "RX_Drops|Multicast",
                                  'rx_errors' "RX|Errs",
                                  'rx_crc_errors' "RX_CRC|Errs",
                                  'rx_align_errors' "RX_Align|Errs",
                                  'rx_fifo_errors' "RX_FIFO|Errs",
                                  'rx_frame_errors' "RX_Frame|Errs",
                                  'rx_over_errors' "RX_Over|Errs",
                                  'rx_length_errors' "RX_Len|Errs",
                                  'rx_short_length_errors' "Rx_ShortLen|Errs",
                                  'rx_long_length_errors' "RX_LongLen|Errs",
                                  'rx_missed_errors' "RX_Misses|Errs",
                                  'rx_no_buffer_count' "RX|NoBuffs",
                                  'rx_queue_bytes' "RX_Queue|Bytes",
                                  'rx_queue_packets' "RX_Queue|Packs",
                                  'rx_queue_alloc_failed' "RX_Queue|Alloc_Fails",
                                  'rx_queue_csum_err' "RX_Queue|CSUM_Errs",
                                  'rx_queue_drops' "RX_Queue|Drops",
                                  'rx_hwtstamp_cleared' "TX_HWTStamp|Clears",
                                  'tx_bytes' "TX|Bytes",
                                  'tx_packets' "TX|Packs",
                                  'tx_multicast' "TX_Packs|Multicast",
                                  'tx_multicast_drops' "TX_Drops|Multicast",
                                  'tx_dropped' "TX|Drops",
                                  'tx_timeout_count' "TX|Timeouts",
                                  'tx_errors' "TX|Errs",
                                  'tx_aborted_errors' "TX_Abort|Errs",
                                  'tx_carrier_errors' "TX_Carrier|Errs",
                                  'tx_fifo_errors' "TX_FIFO|Errs",
                                  'tx_heartbeat_errors' "TX_HeartBeat|Errs",
                                  'tx_window_errors' "TX_Window|Errs",
                                  'tx_hwtstamp_skipped' "TX_HWTStamp|Skips",
                                  'tx_hwtstamp_timeouts' "TX_HWTStamp|Timeouts",
                                  'tx_dma_out_of_sync' "TX_DMA|OutOfSync",
                                  'tx_tcp_seg_failed' "TX_TCP|Seg_Fails",
                                  'tx_tcp_seg_good' "TX_TCP|Seg_Goods",
                                  'tx_queue_bytes' "TX_Queue|Bytes",
                                  'tx_queue_packets' "TX_Queue|Packs",
                                  'tx_queue_restart' "TX_Queue|Restarts"
                                  ))
                ORDER BY 1,2;

                PRO NMON_SYSSTS:
                PRO ============
                SELECT NAME,&insts,MAX(ts) "Timestamp",any_value(comments) comments
                FROM   TABLE(gv$(CURSOR(
                  SELECT userenv('instance') inst_id,
                         KSNMONSYSSTS_NAME NAME,
                         KSNMONSYSSTS_VALUE VALUE,
                         KSNMONSYSSTS_TMSTMP + 0 ts,
                         KSNMONSYSSTS_DESC comments
                  FROM   SYS.X$KSNMON_SYSSTS)))
                GROUP BY NAME
                ORDER BY 1;
            }

            default={}
        }
    --]]

]]*/
SET FEED OFF SEP4K ON
SET AUTOHIDE COL VERIFY OFF
COL ADDR,INDX,CON_ID, NOPRINT
COL BYTES_RECEIVED,BYTES_SENT,RX|BYTES,TX|BYTES,RX_QUEUE|BYTES,TX_QUEUE|BYTES FORMAT KMG
COL PACKETS_RECEIVED,PACKETS_SENT,RX|PACKS,TX|PACKS,RX_QUEUE|PACKS,TX_QUEUE|PACKS,RX_Packs|Multicast,TX_Packs|Multicast FORMAT TMB
COL PCT FOR PCT
COL BYTES_RECEIVED HEAD RX|BYTES
COL BYTES_SENT HEAD HEAD TX|BYTES
COL PACKETS_RECEIVED HEAD RX|PACKS
COL PACKETS_SENT HEAD TX|PACKS
COL RECEIVE_ERRORS HEAD RX|ERRS
COL SEND_ERRORS HEAD TX|ERRS
COL RECEIVE_DROPPED HEAD RX|DROP
COL SENDS_DROPPED HEAD TX|DROP
COL RECEIVE_BUF_OR HEAD RX_BUF|OVERRUN
COL SEND_BUF_OR HEAD TX_BUF|OVERRUN
COL RECEIVE_FRAME_ERR HEAD RX_FRAME|ERRS
COL SEND_FRAME_ERR HEAD TX_FRAME|ERRS
COL SEND_CARRIER_LOST HEAD TX_CARRIER|LOST
COL INST_ID HEAD INST

PRO Inter-Connect Stats:
PRO ===================
SELECT * FROM TABLE(GV$(CURSOR(
    select NVL(b.PUB_KSXPIA,'Y') "PUBLIC",a.* from sys.x$ksxpif a,sys.X$KSXPIA b
    WHERE  a.IF_NAME=b.NAME_KSXPIA(+)
    AND    a.IP_ADDR=b.IP_KSXPIA(+)
)))
ORDER BY inst_id,ip_addr;

VAR insts VARCHAR2(4000)
BEGIN
    SELECT LISTAGG('MAX(DECODE(INST_ID,'||inst_id||',VALUE)) "Inst#'||inst_id||'"',',')
           WITHIN GROUP(ORDER BY INST_ID)
    INTO   :insts
    FROM   GV$INSTANCE;
END;
/

PRO 
PRO TCP Paramters:
PRO ==============
SELECT STAT_NAME,&insts,any_value(COMMENTS) comments
FROM   GV$OSSTAT
WHERE  REGEXP_LIKE(STAT_NAME,'(SEND|RECEIVE|TCP)_')
AND    CUMULATIVE='NO'
GROUP  BY STAT_NAME
ORDER  BY 1;

&check_access_nmon

PRO Inter-Connect Data:
PRO ===================
SELECT A.*,RATIO_TO_REPORT(BYTES_SENT+BYTES_RCV) OVER(PARTITION BY INST_ID) PCT
FROM TABLE(GV$(CURSOR(SELECT * FROM sys.X$KSXPCLIENT))) A 
WHERE BYTES_SENT+BYTES_RCV>0
ORDER BY INST_ID,2;


PRO Instance Pings:
PRO ===================
SELECT * FROM GV$INSTANCE_PING ORDER BY 1,2;