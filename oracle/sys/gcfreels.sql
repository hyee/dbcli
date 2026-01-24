/*[[Check GC freelist based on x$kclfx(Kernel Cache Lock Element Free list statistics)]]*/
PRO Kernel Cache Lock Element Free list statistics:
PRO ===============================================
SELECT * 
FROM   TABLE(GV$(CURSOR(
    SELECT  INST_ID "Inst|Id",
            Count(1) "Num|Addrs",
            SUM(len) "Current|Size",
            SUM(lwm) "Smallest|Size(LWM)",
            SUM(Adds) "Added|Count",
            SUM(Rems) "Removed|Count",
            SUM(LBUS) "Latch|Waits",
            SUM(NLAT) "Latch|Switches",
            SUM(WAIT) "Num|Waits"
    FROM  SYS.X$KCLFX
    GROUP BY INST_ID)))
ORDER BY "Inst|Id";