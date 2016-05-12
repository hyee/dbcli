/*[[Call DBMS_RESOURCE_MANAGER.CALIBRATE_IO. Usage: @@NAME {[disks] [max latency]}
   --[[@limitation: 11.1={Oracle 11g+}]]--
]]*/

DECLARE
    lat  INTEGER;
    iops INTEGER;
    mbps INTEGER;
BEGIN
    -- DBMS_RESOURCE_MANAGER.CALIBRATE_IO (disk_count,max_latency , iops, mbps, lat);
    DBMS_RESOURCE_MANAGER.CALIBRATE_IO(nvl(:V1,'1'), NVL(:V2,'20'), iops, mbps, lat);

    DBMS_OUTPUT.PUT_LINE('max_iops = ' || iops);
    DBMS_OUTPUT.PUT_LINE('latency  = ' || lat);
    dbms_output.put_line('max_mbps = ' || mbps);
END;
/