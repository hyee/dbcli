/*[[
    Show the summary of cell metric based on external table EXA$METRIC. Usage: @@NAME [<cellname>]
    Refer to page https://docs.oracle.com/en/engineered-systems/exadata-database-machine/sagug/exadata-storage-server-monitoring.html#GUID-B52267F8-FAD9-4A86-9D84-81792A914C94
    This script relies on external table EXA$METRIC which is created by shell script "oracle/shell/create_exa_external_tables.sh" with the oracle user
    --[[
        @check_access_obj: EXA$METRIC={}
        @table: {
            12.2={json_table(data,'$[*]' columns CELL varchar2(30) path '$[0]',TYP varchar2(30) path '$[1]',NAME varchar2(30) path '$[2]',OBJ varchar2(300) path '$[3]' ,VALUE number path '$[4]',UNIT varchar2(30) path '$[5]',TSTAMP varchar2(30) path '$[6]')}
            default={xmltable('/ROWSET/ROW' passing data columns CELL varchar2(30) path 'CELL',TYP varchar2(30) path 'TYP',NAME varchar2(30) path 'NAME',OBJ varchar2(300) path 'OBJ' ,VALUE number path 'VALUE',UNIT varchar2(30) path 'UNIT',TSTAMP varchar2(30) path 'TSTAMP')}
        }    
        @V122_TYP: 12.2={CLOB} default={XMLTYPE}
    --]]
]]*/

set verify off feed off
var cell       refcursor
var celldisk   refcursor
var griddisk   refcursor
var flashcache refcursor
var flashlog   refcursor
var smartio    refcursor
var ibport     refcursor
var interconn  refcursor
var iorm_db    refcursor
var ccc refcursor;
COL "IB_IN/s,IB_OUT/s,ETH_IN/s,ETH_OUT/s,VMEM(CS),VMEM(MS),SWAP,SWAP_IN/s,SWAP_OUT/s,FC_DIRTY,SM_R/s,SM_W/s,LG_R/s,LG_W/s,SCRUB/s,ALLOC" FOR KMG
COL "ALLOC(OLTP),DIRTY,KEEP,USED,CC_USED,CC_ELIG/s,CC_SAVED/s,CC_POP/s,R/s,W/s,R_MISS/s,R_DW/s,R_SKIP/s,W_1st/s,W_DW/s,W_Pop/s,W_Skip/s,HD/s,FD/s,R/IO,W/IO,R,W,R_SKIP,W_SKIP,R_MISS,CC_R,CC_ELIG,CC_SAVED,CC_W" for kmg
COL "CC_REQS,LG_R_IOPS,LG_W_IOPS,SM_R_IOPS,SM_W_IOPS,SCRUB_IOPS,REQS,FL_REQS,HD_FIRST,FD_FIRST,HD_ERRS,FD_ERRS,HD_OUTLIER,FD_OUTLIER,BOTH_OUTLIER,SKIP_OUTLIER,SKIP_BUSY,SKIP_BUSY(1m),SKIP_LARGE,SKIP_DISABLED,SKIP_IORM,SKIP_PLAN,FC_IOPS,FL_IOPS" for tmb
COL "OFL_IN,OFL_OUT,SI_SAVE,PASSTHRU,FC_R,HD_R,BOTH,OFL_IN/s,OFL_OUT/s,SI_SAVE/s,PASSTHRU/s,PASSTHRU_CPU,PASSTHRU_CPU/s,FC_R/s,HD_R/s,BOTH/s,FC_WR,HD_W,FC_W/s,HD_W/s" for kmg
COL "SM_Latency,AVG_Wait,IO_Wait,FD_TM,FD_TM_LG,FD_WT_LG,FD_TM_SM,FD_WT_SM,HD_TM_LG,HD_WT_LG,HD_TM_SM,HD_WT_SM" for usmhd
COL "CELL_IN,CELL_OUT,CELL_DROP,RDMA_DROP,CELL_IN/s,CELL_OUT/s,CELL_DROP/s,RDMA_DROP/s,PMEM_ALLOC,PMEM_ALLOC_DB,PMEM_ALLOC_PDB,FC_ALLOC,PMEM,FC/s,FL/s,FD/s,HD/s" for KMG
COL "Temp,LOADS,CPU,CPU(CS),CPU(MS),Mem,Mem(CS),Mem(MS),MaxFSUsage,EFF,EFF(1h),IB_UTIL_IN,IB_UTIL_OUT" for k justify right
COL CELL BREAK

DECLARE
    data &V122_TYP;
    cur  SYS_REFCURSOR;
    hdl  BINARY_INTEGER;
    V1   VARCHAR2(128):=:V1;
BEGIN
    $IF DBMS_DB_VERSION.VERSION>11 AND DBMS_DB_VERSION.RELEASE>1 OR DBMS_DB_VERSION.VERSION>12 $THEN
        SELECT /*+opt_param('parallel_force_local' 'true')*/ json_arrayagg(json_array(
                nullif(cellnode,' '),
                nullif(objecttype,' '),
                nullif(NAME,' '),
                nullif(metricobjectname,cellnode),
                nullif(metricvalue * CASE
                    WHEN unit LIKE 'MB%' THEN
                     1024 * 1024
                    WHEN unit LIKE 'KB%' THEN
                     1024
                    WHEN unit = 'ms' THEN
                     1000
                    ELSE
                     1
                END,-1),
                nullif(CASE
                    WHEN regexp_like(unit, '(KB|bytes|MB|us|ms)') THEN
                     ''
                    ELSE
                     TRIM(unit)
                END,' '),
                NULLIF(TO_CHAR(COLLECTIONTIME,'YYYY-MM-DD HH24:MI:SS'),' ') null on null) RETURNING CLOB)
        INTO   data
        FROM   exa$metric 
        WHERE  nvl(lower(v1),' ') in(' ',lower(cellnode));
    $ELSE
        OPEN cur FOR q'[
            SELECT /*+opt_param('parallel_force_local' 'true')*/ cellnode cell,
                   objecttype typ,
                   NAME,
                   nullif(metricobjectname,cellnode) obj,
                   CASE
                       WHEN unit LIKE 'MB%' THEN
                         1024 * 1024
                       WHEN unit LIKE 'KB%' THEN
                         1024
                       WHEN unit = 'ms' THEN
                         1000
                       ELSE
                         1
                   END * metricvalue value,
                   CASE WHEN regexp_like(unit,'(KB|bytes|MB|us|ms)') THEN '' ELSE trim(unit) END unit,
                   TO_CHAR(COLLECTIONTIME,'YYYY-MM-DD HH24:MI:SS') TSTAMP
            FROM   exa$metric
            WHERE  nvl(lower(:keyword),' ') in(' ',lower(cellnode))]' USING v1;
        hdl :=dbms_xmlgen.newcontext(cur);
        data:=dbms_xmlgen.getxmltype(hdl);
        dbms_xmlgen.closecontext(hdl);
        CLOSE cur;
    $END

    OPEN :cell FOR 
        SELECT * FROM (SELECT cell,name,value||unit value,MAX(TSTAMP) OVER(PARTITION BY cell) COLLECT_TIME FROM &table WHERE typ IN('CELL','CELL_FILESYSTEM'))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('CL_TEMP' "Temp",
                       'CL_FANS' "Fans",
                       'CL_RUNQ' "LOADS",
                       'CL_CPUT' "CPU",
                       'CL_CPUT_CS' "CPU(CS)",
                       'CL_CPUT_MS' "CPU(MS)",
                       'CL_MEMUT' "Mem",
                       'CL_MEMUT_CS' "Mem(CS)",
                       'CL_MEMUT_MS' "Mem(MS)",
                       'CL_VIRTMEM_CS' "vMem(CS)",
                       'CL_VIRTMEM_MS' "vMem(MS)",
                       'CL_FSUT' "MaxFSUsage",
                       'N_HCA_MB_RCV_SEC' "IB_IN/s",
                       'N_HCA_MB_TRANS_SEC' "IB_OUT/s",
                       'N_NIC_KB_RCV_SEC' "ETH_IN/s",
                       'N_NIC_KB_TRANS_SEC' "ETH_OUT/s",
                       'CL_SWAP_USAGE' "SWAP",
                       'CL_SWAP_IN_BY_SEC' "SWAP_IN/s",
                       'CL_SWAP_OUT_BY_SEC' "SWAP_OUT/s",
                       'IORM_MODE' "IORM"))
        ORDER  BY CELL;

    OPEN :ibport FOR
        SELECT *
        FROM   (SELECT nvl(cell,'--TOTAL--') cell,
                       NAME,
                       MAX(MAX(TSTAMP)) OVER(PARTITION BY cell) COLLECT_TIME,
                       MAX(COUNT(DISTINCT CASE WHEN typ='IBPORT' THEN CELL||OBJ END)) OVER(PARTITION BY cell) IB_CNT,
                       CASE WHEN max(unit)='%' THEN ROUND(AVG(VALUE),2)||'%' ELSE SUM(VALUE)||'' END VALUE
                FROM   &TABLE
                WHERE  typ IN ('IBPORT','HOST_INTERCONNECT','PMEMCACHE')
                GROUP  BY NAME,rollup(CELL))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('N_IB_MB_RCV_SEC' "IB_IN/s",
                       'N_IB_MB_TRANS_SEC' "IB_OUT/s",
                       'N_MB_RECEIVED_SEC' "CELL_IN/s",
                       'N_MB_SENT_SEC' "CELL_OUT/s",
                       'N_MB_DROP_SEC' "CELL_DROP/s",
                       'N_MB_RDMA_DROP_SEC' "RDMA_DROP/s",
                       'N_IB_UTIL_RCV' "IB_UTIL_IN",
                       'N_IB_UTIL_TRANS' "IB_UTIL_OUT",
                       'N_MB_RECEIVED' "CELL_IN",
                       'N_MB_SENT' "CELL_OUT",
                       'N_MB_DROP' "CELL_DROP",
                       'N_MB_RDMA_DROP' "RDMA_DROP",
                       'PC_BY_ALLOCATED' "PMEM_ALLOC",
                       'DB_PC_BY_ALLOCATED' "PMEM_ALLOC_DB",
                       'PDB_PC_BY_ALLOCATED' "PMEM_ALLOC_PDB"
                       ))
        ORDER  BY CELL;
    OPEN :celldisk FOR 
        SELECT *
        FROM   (SELECT nvl(cell,'--TOTAL--') cell,
                       MAX(MAX(TSTAMP)) OVER(PARTITION BY cell) COLLECT_TIME,
                       NAME,
                       substr(obj, 1, 2) Typ,
                       MAX(COUNT(1)) over(PARTITION BY cell, substr(obj, 1, 2)) disks,
                       ROUND(CASE
                           WHEN name LIKE '%_RQ' or name like '%UTIL%' or name like '%LOAD%' THEN
                            AVG(VALUE)
                           ELSE
                            SUM(VALUE)
                       END,2) VALUE
                FROM   &TABLE
                WHERE  typ = 'CELLDISK'
                GROUP  BY NAME,rollup(substr(obj, 1, 2),CELL))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('CD_IO_UTIL' "Util",
                       'CD_IO_UTIL_LG' "Util(LG)",
                       'CD_IO_UTIL_SM' "Util(SM)",
                       'CD_IO_LOAD' "LOAD",
                       'CD_IO_ERRS' "ERRS",
                       'CD_IO_ERRS_SCRUB' "ERRS(SCRUB)",
                       'CD_BY_FC_DIRTY' "FC_DIRTY",
                       'CD_IO_ST_RQ' "SM_Latency",
                       'CD_IO_BY_R_SM_SEC' "SM_R/s",
                       'CD_IO_BY_W_SM_SEC' "SM_W/s",
                       'CD_IO_RQ_R_SM_SEC' "SM_R_IOPS",
                       'CD_IO_RQ_W_SM_SEC' "SM_W_IOPS",
                       'CD_IO_BY_R_LG_SEC' "LG_R/s",
                       'CD_IO_BY_W_LG_SEC' "LG_W/s",
                       'CD_IO_RQ_R_LG_SEC' "LG_R_IOPS",
                       'CD_IO_RQ_W_LG_SEC' "LG_W_IOPS",
                       'CD_IO_BY_R_SCRUB_SEC' "SCRUB/s",
                       'CD_IO_RQ_R_SCRUB_SEC' "SCRUB_IOPS"))
        ORDER  BY CELL, typ nulls first;

    OPEN :griddisk FOR 
        SELECT *
        FROM   (SELECT nvl(cell,'--TOTAL--') cell,
                       NAME,
                       regexp_replace(obj,'_[^_]+_\d+_[^_]+$') DISKGROUP,
                       decode(instr(obj,'_FD_'),0,'CD','FD') Typ,
                       MAX(COUNT(1)) over(PARTITION BY cell, regexp_replace(obj,'_[^_]+_\d+_[^_]+$'),decode(instr(obj,'_FD_'),0,'CD','FD')) disks,
                       ROUND(CASE
                           WHEN name LIKE '%_RQ' or name like '%UTIL%' or name like '%LOAD%' THEN
                            AVG(VALUE)
                           ELSE
                            SUM(VALUE)
                       END,2) VALUE
                FROM   &TABLE
                WHERE  typ = 'GRIDDISK'
                GROUP  BY NAME,rollup(regexp_replace(obj,'_[^_]+_\d+_[^_]+$'),(CELL,decode(instr(obj,'_FD_'),0,'CD','FD'))))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('GD_SP_BY_ALLOCATED' "ALLOC",
                       'GD_SP_PRCT_ALLOCATED' "ALLOC(%)",
                       'GD_IO_ERRS' "ERRS",
                       'GD_IO_ERRS_SCRUB' "ERRS(SCRUB)",
                       'GD_BY_FC_DIRTY' "FC_DIRTY",
                       'GD_IO_BY_R_SM_SEC' "SM_R/s",
                       'GD_IO_BY_W_SM_SEC' "SM_W/s",
                       'GD_IO_RQ_R_SM_SEC' "SM_R_IOPS",
                       'GD_IO_RQ_W_SM_SEC' "SM_W_IOPS",
                       'GD_IO_BY_R_LG_SEC' "LG_R/s",
                       'GD_IO_BY_W_LG_SEC' "LG_W/s",
                       'GD_IO_RQ_R_LG_SEC' "LG_R_IOPS",
                       'GD_IO_RQ_W_LG_SEC' "LG_W_IOPS",
                       'GD_IO_BY_R_SCRUB_SEC' "SCRUB/s",
                       'GD_IO_RQ_R_SCRUB_SEC' "SCRUB_IOPS"))
        ORDER  BY CELL, DISKGROUP nulls first,typ nulls first;

    OPEN :flashcache FOR 
        SELECT *
        FROM   (SELECT * FROM (
                    SELECT nvl(cell,'--TOTAL--') cell,
                           NAME,
                           SUM(VALUE) VALUE
                    FROM   &TABLE
                    WHERE  typ = 'FLASHCACHE'
                    GROUP  BY NAME,rollup(CELL))
                MODEL  PARTITION BY(CELL) DIMENSION BY (name) MEASURES(value)
                RULES  (
                    VALUE['FC_IO_BY_R_RQ']=round(VALUE['FC_IO_BY_R']/VALUE['FC_IO_RQ_R']),
                    VALUE['FC_IO_BY_W_RQ']=round(VALUE['FC_IO_BY_W']/VALUE['FC_IO_RQ_W'])
                ))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('FC_BY_ALLOCATED' "ALLOC",
                       'FC_BY_ALLOCATED_OLTP' "ALLOC(OLTP)",
                       'FC_BY_DIRTY' "DIRTY",
                       'FC_BYKEEP_USED' "KEEP",
                       'FC_BY_USED' "USED",
                       'FC_COL_BY_USED' "CC_USED",
                       'FC_COL_IO_BY_R_ELIGIBLE_SEC' "CC_ELIG/s",
                       'FC_COL_IO_BY_SAVED_SEC' "CC_SAVED/s",
                       'FC_COL_IO_BY_W_POPULATE_SEC' "CC_POP/s",
                       'FC_IO_BY_R_SEC' "R/s",
                       'FC_IO_BY_W_SEC' "W/s",
                       'FC_IO_BY_R_MISS_SEC' "R_MISS/s",
                       'FC_IO_BY_R_DISK_WRITER_SEC' "R_DW/s",
                       'FC_IO_BY_R_SKIP_SEC' "R_SKIP/s",
                       'FC_IO_BY_W_FIRST_SEC' "W_1st/s",
                       'FC_IO_BY_W_DISK_WRITER_SEC' "W_DW/s",
                       'FC_IO_BY_W_POPULATE_SEC' "W_Pop/s",
                       'FC_IO_BY_W_SKIP_SEC' "W_Skip/s",
                       'FC_IO_BY_R_RQ' "R/IO",
                       'FC_IO_BY_W_RQ' "W/IO",
                       'FC_IO_ERRS' "ERRS",
                       'FC_IO_RQ_R' "R",
                       'FC_IO_RQ_R_SKIP' "R_SKIP",
                       'FC_IO_RQ_R_MISS' "R_MISS",
                       'FC_COL_IO_BY_R' "CC_R",
                       'FC_COL_IO_BY_R_ELIGIBLE' "CC_ELIG",
                       'FC_COL_IO_BY_SAVED' "CC_SAVED",
                       'FC_IO_RQ_W' "W",
                       'FC_IO_RQ_W_SKIP' "W_SKIP",
                       'FC_COL_IO_BY_W_POPULATE' "CC_W"))
        ORDER  BY CELL;

    OPEN :flashlog FOR 
        SELECT *
        FROM   (SELECT nvl(cell,'--TOTAL--') cell,
                       NAME,
                       ROUND(CASE WHEN name like '%_RQ' or MAX(unit)='%' THEN AVG(VALUE) ELSE SUM(VALUE) END,2)
                       ||CASE WHEN max(unit)='%' THEN '%' END VALUE
                FROM   &TABLE
                WHERE  typ = 'FLASHLOG'
                GROUP  BY NAME,rollup(CELL))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('FL_IO_FL_BY_W_SEC' "FD/s",
                       'FL_IO_DB_BY_W_SEC' "HD/s",
                       'FL_RQ_TM_W_RQ' "AVG_Wait",
                       'FL_IO_TM_W_RQ' "IO_Wait",
                       'FL_RQ_W' "REQS",
                       'FL_IO_W' "FL_REQS",
                       'FL_FLASH_FIRST' "FD_FIRST",
                       'FL_DISK_FIRST' "HD_FIRST",
                       'FL_FLASH_IO_ERRS' "FD_ERRS",
                       'FL_BY_KEEP' "HD_ERRS",
                       'FL_FLASH_ONLY_OUTLIERS' "FD_OUTLIER",
                       'FL_PREVENTED_OUTLIERS' "HD_OUTLIER",
                       'FL_ACTUAL_OUTLIERS' "BOTH_OUTLIER",
                       'FL_SKIP_OUTLIERS' "SKIP_OUTLIER",
                       'FL_EFFICIENCY_PERCENTAGE' "EFF",
                       'FL_EFFICIENCY_PERCENTAGE_HOUR' "EFF(1h)",
                       'FL_IO_W_SKIP_BUSY' "SKIP_BUSY",
                       'FL_IO_W_SKIP_BUSY_MIN' "SKIP_BUSY(1m)",
                       'FL_IO_W_SKIP_LARGE' "SKIP_LARGE",
                       'FL_IO_W_SKIP_DISABLED_GD' "SKIP_DISABLED",
                       'FL_IO_W_SKIP_IORM_LIMIT' "SKIP_IORM",
                       'FL_IO_W_SKIP_IORM_LIMIT' "SKIP_PLAN"))
        ORDER  BY CELL;

    OPEN :smartio FOR 
        SELECT *
        FROM   (SELECT nvl(cell,'--TOTAL--') cell,
                       NAME,
                       SUM(VALUE) VALUE
                FROM   &TABLE
                WHERE  typ = 'SMARTIO'
                GROUP  BY NAME,rollup(CELL))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('SIO_IO_EL_OF_SEC' "OFL_IN/s",
                       'SIO_IO_OF_RE_SEC' "OFL_OUT/s",
                       'SIO_IO_SI_SV_SEC' "SI_SAVE/s",
                       'SIO_IO_RD_FC_SEC' "FC_R/s",
                       'SIO_IO_RD_HD_SEC' "HD_R/s",
                       'SIO_IO_RD_FC_HD_SEC' "BOTH/s",
                       'SIO_IO_WR_FC_SEC' "FC_W/s",
                       'SIO_IO_WR_HD_SEC' "HD_W/s",
                       'SIO_IO_RV_OF_SEC' "PASSTHRU_CPU/s",
                       'SIO_IO_PA_TH_SEC' "PASSTHRU/s",
                       'SIO_IO_EL_OF' "OFL_IN",
                       'SIO_IO_OF_RE' "OFL_OUT",
                       'SIO_IO_SI_SV' "SI_SAVE",
                       'SIO_IO_RD_FC' "FC_R",
                       'SIO_IO_RD_HD' "HD_R",
                       'SIO_IO_RD_FC_HD' "BOTH",
                       'SIO_IO_WR_FC' "FC_W",
                       'SIO_IO_WR_HD' "HD_W",
                       'SIO_IO_RV_OF' "PASSTHRU_CPU",
                       'SIO_IO_PA_TH' "PASSTHRU"
                       ))
        ORDER  BY CELL;

    OPEN :iorm_db FOR 
        SELECT *
        FROM   (SELECT nvl(cell,'--TOTAL--') cell,
                       NAME,
                       NVL(replace(obj,'_OTHER_DATABASE_','Others'),'--TOTAL--') DB,
                       ROUND(CASE WHEN name like '%_RQ' or name like '%UTIL%' or name like '%LOAD%' THEN AVG(VALUE) ELSE SUM(VALUE) END,2) VALUE
                FROM   &TABLE
                WHERE  typ = 'IORM_DATABASE'
                GROUP  BY NAME,CUBE(replace(obj,'_OTHER_DATABASE_','Others'),CELL))
        PIVOT(MAX(VALUE)
        FOR    NAME IN('DB_FC_BY_ALLOCATED' "FC_ALLOC",
                       'DB_PC_BY_ALLOCATED' "PMEM",
                       'DB_FC_IO_BY_SEC' "FC/s",
                       'DB_FL_IO_BY_SEC' "FL/s",
                       'DB_FD_IO_BY_SEC' "FD/s",
                       'DB_IO_BY_SEC' "HD/s",
                       'DB_FC_IO_RQ_SEC' "FC_IOPS",
                       'DB_FL_IO_RQ_SEC' "FL_IOPS",
                       'DB_FD_IO_TM_RQ' "FD_TM",
                       'DB_FD_IO_TM_LG_RQ' "FD_TM_LG",
                       'DB_FD_IO_WT_LG_RQ' "FD_WT_LG",
                       'DB_FD_IO_TM_SM_RQ' "FD_TM_SM",
                       'DB_FD_IO_WT_SM_RQ' "FD_WT_SM",
                       'DB_IO_TM_LG_RQ' "HD_TM_LG",
                       'DB_IO_WT_LG_RQ' "HD_WT_LG",
                       'DB_IO_TM_SM_RQ' "HD_TM_SM",
                       'DB_IO_WT_SM_RQ' "HD_WT_SM",
                       'DB_FD_IO_UTIL' "FD_UTIL",
                       'DB_FD_IO_UTIL_LG' "FD_UTIL_LG",
                       'DB_FD_IO_UTIL_SM' "FD_UTIL_SM",
                       'DB_IO_UTIL_LG' "HD_UTIL_LG",
                       'DB_IO_UTIL_SM' "HD_UTIL_SM",
                       'DB_FD_IO_LOAD' "FD_LOAD",
                       'DB_IO_LOAD' "HD_LOAD"))
        ORDER  BY CELL,DB nulls first;
    open :ccc for select * from v$open_cursor where sid=userenv('sid') and SQL_EXEC_ID is not null;
END;
/

PRO CELL METRIC (CS=CELLSRV   MS=ManagementServer   FS=FileSystem   IB=InfiniBand   ETH=Ethernet)
PRO =============================================================================================
print cell

PRO INFINIBAND / PMEM / HOST-INTERCONNECT METRIC (IB=InfiniBand   CELL=HostInterConnect)
PRO ====================================================================================
print ibport

PRO CELLDISK METRIC (LG=LargeIO SM=SmallIO CD=HardDisk FD=FlashDisk FC=FlashCache R=Read W=write)
PRO ===============================================================================================
print celldisk

COL CELL BREAK SKIP -
SET COLSEP |
PRO GRIDDISK METRIC (LG=LargeIO SM=SmallIO CD=HardDisk FD=FlashDisk FC=FlashCache R=Read W=write)
PRO =============================================================================================
print griddisk

COL CELL BREAK
SET COLSEP DEFAULT

PRO SMART IO METRIC (HD=HardDisk FC=FlashCache R=Read W=Write SI=StorageIndex OFL=Offload)
PRO ======================================================================================
print smartio

PRO FLASHCACHE METRIC (R=Read W=Write CC=ColumnarCache DW=DiskWriter Pop=Population)
PRO ================================================================================
print flashcache

PRO FLASHLOG METRIC (HD=HardDisk FD=FlashDisk FL=FlashLogging Outlier>0.5s)
PRO =======================================================================
print flashlog


COL CELL BREAK SKIP -
SET COLSEP |
PRO IORM DATABASE METRIC (HD=HardDisk FC=FlashCache FL=FlashLog FD=FlashDisk TM=AvgIOLatency WT=AvgIORMLatency LG=LargeIO SM=SmallIO)
PRO ================================================================================================================================
print iorm_db
