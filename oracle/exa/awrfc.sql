/*[[
    Show Cell AWR Flash Cache Info. Usage: @@NAME [YYMMDDHH24MI] [YYMMDDHH24MI] [-sum]
    -sum: Use total number of IO costs instead of MBPS and IOPS
    --[[
        &dur: default={dur} sum={1}
        &unit: default={K}  sum={TMB}
        &io  : default={RQPS} sum={Reqs}
        &mb  : default={MBPS} sum={MBs}
    ]]--
]]*/

set feed off verify off
VAR c_space  refcursor;
VAR c_reads  refcursor;
VAR c_writes refcursor;
VAR c_ram    refcursor;
VAR v_start  VARCHAR2(30);
VAR v_end    VARCHAR2(30);
col HD|SIZE,FD|Size,total|size,un-|alloc,flashcache,flashlog,Alloc|RAM,RAM|OLTP,Alloc|FCache,Alloc|OLTP,ALLOC|SCAN,Large|Writes,OLTP|Dirty,FCache|Used,Used|OLTP,Used|Columnar,FCache|Keep,Keep|OLTP,Keep|Columnar format kmg
col "Hit|&io,Hit|Miss,OLTP|&io,SCAN|&io,COLUMNAR|&io,KEEP|&io,Keep|Miss" FOR &unit
col "Hit|&mb,2nd|Hits,2nd|Miss,OLTP|&mb,SCAN|&mb,SCAN|Reqs,COLUMNAR|&mb,COLUMNAR|ELIG,COLUMNAR|SAVED,KEEP|&mb" FOR kmg;
col "Total|&io,FirstWrite|&io,OverWrite|&io,Populate|Miss-&io,LargeWrite|&io,TempSpill|&io,DataTemp|&io,WriteOnly|&io" FOR &unit
col "Total|&mb,FirstWrite|&mb,OverWrite|&mb,Populate|Miss-&mb,LargeWrite|&mb,Temp|Spill,Data/|Temp,Write|Only" FOR kmg;
col "Populate|&io,Pop-Keep|&io,Pop-CC|&io,Scan Used|Free Header,Scan|OLTP,Scan|DW,Scan|Self,Scan|Zero Hit,RAM|&io,MISS|&io,Write|&io" for &unit
col "Populate|&mb,Pop-Keep|&mb,Pop-CC|&mb,RAM|&mb,RAM|Miss,RAM|Write" FOR kmg;

DECLARE
    duration NUMBER;
    did      NUMBER;
    bid      NUMBER;
    eid      NUMBER;
    c_meta clob:=q'[
      <stats>
        <!-- user reads -->
        <stat id="180" name="fcoior" type="bytes" cat="01-fc_ureads" sub="fco" in_cat_sum="Y"/>
        <stat id="200" name="fcoior" type="reqs"  cat="01-fc_ureads" sub="fco" in_cat_sum="Y"/>
        <stat id="206" name="fcsior" type="bytes"  cat="01-fc_ureads" sub="fcs" in_cat_sum="Y"/>
        <stat id="204" name="fcsior" type="reqs" cat="01-fc_ureads" sub="fcs" in_cat_sum="Y"/>
        <stat id="305" name="fccior" type="bytes"  cat="01-fc_ureads" sub="fcc" in_cat_sum="Y"/>
        <stat id="304" name="fccior" type="reqs"  cat="01-fc_ureads" sub="fcc" in_cat_sum="Y"/>
        <stat id="214" name="fckpior" type="bytes"  cat="01-fc_ureads" sub="fckp" in_cat_sum="Y"/>
        <stat id="212" name="fckpior" type="reqs"  cat="01-fc_ureads" sub="fckp" in_cat_sum="Y"/>
        <stat id="201" name="fcoiorqrm" type="reqs" cat="01-fc_ureads" sub="fco"/>
        <stat id="205" name="fcsiobyra" type="bytes" cat="01-fc_ureads" sub="fcs"/>
        <stat id="302" name="fcciobyelig" type="bytes"  cat="01-fc_ureads" sub="fcc"/>
        <stat id="303" name="fcciobysave" type="bytes"  cat="01-fc_ureads" sub="fcc"/>
        <stat id="213" name="fckpiorqrm" type="reqs" cat="01-fc_ureads" sub="fckp"/>
        <stat id="196" name="fciorash" type="bytes" cat="01-fc_ureads"/>
        <stat id="194" name="fciorash" type="reqs" cat="01-fc_ureads"/>
        <stat id="197" name="fciorasm" type="bytes" cat="01-fc_ureads"/>
        <stat id="195" name="fciorasm" type="reqs" cat="01-fc_ureads"/>
        <!-- user writes -->
        <stat id="181" name="fciow" type="bytes"  cat="02-fc_uwrites" in_cat_sum="Y"/>
        <stat id="188" name="fciow" type="reqs"  cat="02-fc_uwrites" in_cat_sum="Y"/>
        <stat id="185" name="fciowf" type="bytes" cat="02-fc_uwrites"/>
        <stat id="189" name="fciowf" type="reqs" cat="02-fc_uwrites"/>
        <stat id="186" name="fciowow" type="bytes" cat="02-fc_uwrites"/>
        <stat id="190" name="fciowow" type="reqs" cat="02-fc_uwrites"/>
        <stat id="216" name="fckpiow" type="bytes" cat="02-fc_uwrites"/>
        <stat id="215" name="fckpiow" type="reqs" cat="02-fc_uwrites"/>
        <stat id="373" name="fclwmrw" type="reqs" cat="02-fc_uwrites"/>
        <stat id="374" name="fclwnrw" type="reqs" cat="02-fc_uwrites"/>
        <stat id="375" name="fclwrow" type="reqs" cat="02-fc_uwrites"/>
        <stat id="376" name="fclwmrw" type="bytes" cat="02-fc_uwrites"/>
        <stat id="377" name="fclwnrw" type="bytes" cat="02-fc_uwrites"/>
        <stat id="378" name="fclwrow" type="bytes" cat="02-fc_uwrites"/>
        <!-- internal reads -->
        <stat id="192" name="fciordw" type="bytes"  cat="03-fc_ireads" in_cat_sum="Y"/>
        <stat id="193" name="fciordw" type="reqs"  cat="03-fc_ireads" in_cat_sum="Y"/>
        <stat id="314" name="fciordkwr" type="reqs" cat="03-fc_ireads"/>
        <stat id="315" name="fciordkwr" type="bytes" cat="03-fc_ireads"/>
        <stat id="316" name="fciowdkwr" type="reqs" cat="03-fc_ireads"/>
        <stat id="317" name="fciowdkwr" type="bytes" cat="03-fc_ireads"/>
        <!-- internal writes -->
        <stat id="187" name="fciowpop" type="bytes"  cat="04-fc_iwrites" in_cat_sum="Y"/>
        <stat id="191" name="fciowpop" type="reqs" cat="04-fc_iwrites" in_cat_sum="Y"/>
        <stat id="218" name="fckpiowpop" type="bytes" cat="04-fc_iwrites"/>
        <stat id="217" name="fckpiowpop" type="reqs" cat="04-fc_iwrites"/>
        <stat id="307" name="fcciowpop" type="bytes" cat="04-fc_iwrites"/>
        <stat id="306" name="fcciowpop" type="reqs" cat="04-fc_iwrites"/>
        <stat id="379" name="fciowtrim" type="reqs"  cat="04-fc_iwrites" in_cat_sum="Y"/>
        <stat id="380" name="fciowtrim" type="bytes" cat="04-fc_iwrites" in_cat_sum="Y"/>
        <stat id="318" name="fciowmd"   type="reqs" cat="04-fc_iwrites" in_cat_sum="Y"/>
        <stat id="319" name="fciowmd"   type="bytes" cat="04-fc_iwrites" in_cat_sum="Y"/>
        <!-- fc scan -->
        <stat id="211" name="fcsfrhdr" type="reqs"  cat="05-fcs_pop" in_cat_sum="Y"/>
        <stat id="207" name="fcsrepdw" type="reqs"  cat="05-fcs_pop" in_cat_sum="Y"/>
        <stat id="208" name="fcsrepoltp" type="reqs"  cat="05-fcs_pop" in_cat_sum="Y"/>
        <stat id="209" name="fcsrepself" type="reqs"  cat="05-fcs_pop" in_cat_sum="Y"/>
        <stat id="210" name="fcsrepzhit" type="reqs"  cat="05-fcs_pop" in_cat_sum="Y"/>
        <!-- others -->
        <stat id="184" name="fciobykpow" type="bytes" cat="06-others"/>
        <stat id="198" name="fciorqspc" type="reqs" cat="06-others"/>
        <stat id="199" name="fciorqspcf" type="reqs" cat="06-others"/>
         <!-- ram cache -->
        <stat id="390" name="rcior" type="reqs"  cat="07-rc_ureads" sub="rco" in_cat_sum="Y"/>
        <stat id="391" name="rcior" type="bytes"  cat="07-rc_ureads" sub="rco" in_cat_sum="Y"/>
        <stat id="392" name="rciorm" type="reqs"  cat="07-rc_ureads" sub="rco" in_cat_sum="Y"/>
        <stat id="393" name="rciorm" type="bytes"  cat="07-rc_ureads" sub="rco" in_cat_sum="Y"/>
        <stat id="394" name="rciowpop"  type="reqs"  cat="08-rc_iwrites" in_cat_sum="Y"/>
        <stat id="395" name="rciowpop" type="bytes"  cat="08-rc_iwrites" in_cat_sum="Y"/>
        <stat id="396" name="rcby" type="space"  cat="09-rc_spc" in_cat_sum="Y"/>
        <stat id="397" name="rcbyo" type="space" cat="09-rc_spc"/>
        <!-- FC skips -->
        <stat id="441" name="fcrsk" type="reqs"  cat="10-fc_rskips" in_cat_sum="Y"/>
        <stat id="442" name="fcrsk" type="bytes" cat="10-fc_rskips" in_cat_sum="Y"/>
        <stat id="443" name="fcwsk" type="reqs" cat="11-fc_wskips" in_cat_sum="Y"/>
        <stat id="444" name="fcwsk" type="bytes" cat="11-fc_wskips" in_cat_sum="Y"/>
        <stat id="445" name="fcrskstnc" type="reqs" cat="10-fc_rskips"/>
        <stat id="446" name="fcrskstnc" type="bytes" cat="10-fc_rskips"/>
        <stat id="447" name="fcwskstnc" type="reqs" cat="11-fc_wskips"/>
        <stat id="448" name="fcwskstnc" type="bytes" cat="11-fc_wskips"/>
        <stat id="449" name="fcrskiorsn" type="reqs" cat ="10-fc_rskips"/>
        <stat id="450" name="fcrskiorsn" type="bytes" cat ="10-fc_rskips"/>
        <stat id="451" name="fcrskgdnc" type="reqs" cat ="10-fc_rskips"/>
        <stat id="452" name="fcrskgdnc" type="bytes" cat ="10-fc_rskips"/>
        <stat id="453" name="fcwskgdnc" type="reqs" cat ="11-fc_wskips"/>
        <stat id="454" name="fcwskgdnc" type="bytes" cat ="11-fc_wskips"/>
        <stat id="455" name="fcrsklio" type="reqs" cat ="10-fc_rskips"/>
        <stat id="456" name="fcrsklio" type="bytes" cat ="10-fc_rskips"/>
        <stat id="457" name="fcwsklio" type="reqs" cat ="11-fc_wskips"/>
        <stat id="458" name="fcwsklio" type="bytes" cat ="11-fc_wskips"/>
        <stat id="459" name="fcrskthio" type="reqs" cat ="10-fc_rskips"/>
        <stat id="460" name="fcrskthio" type="bytes" cat ="10-fc_rskips"/>
        <stat id="461" name="fcwskthio" type="reqs" cat ="11-fc_wskips"/>
        <stat id="462" name="fcwskthio" type="bytes" cat ="11-fc_wskips"/>
        <stat id="463" name="fcrskliorej" type="reqs" cat ="10-fc_rskips"/>
        <stat id="464" name="fcrskliorej" type="bytes" cat ="10-fc_rskips"/>
        <!-- LW rejects -->
        <!-- bug30441717: use all reasons to get the category sum -->
        <stat id="470" name="fclwelig" type="reqs" cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="471" name="fclwrej" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="472" name="fclwrejcglwth" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="473" name="fclwrejflwr" type="reqs" cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="474" name="fclwrejlwth" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="475" name="fclwrejmxlm" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="476" name="fclwrejgllm" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="477" name="fclwrejflbs" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/>
        <stat id="478" name="fclwrejkpcl" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/>
        <!-- stat 479 has been deleted; remove from output -->
        <stat id="480" name="fclwrejiormhd" type="reqs"  cat="12-fc_lwrej" in_cat_sum="Y"/> 
        <!-- pmem cache -->
        <stat id="543" name="pcior" type="reqs"  cat="13-pc_ureads" sub="pco" in_cat_sum="Y"/>
        <stat id="544" name="pciorm" type="reqs" cat="13-pc_ureads" sub="pco" in_cat_sum="Y"/>
        <stat id="545" name="pcior" type="bytes" cat="13-pc_ureads" sub="pco" in_cat_sum="Y"/>
        <stat id="546" name="pciow" type="reqs" cat="14-pc_uwrites" in_cat_sum="Y"/>
        <stat id="547" name="pciowf" type="reqs" cat="14-pc_uwrites"/>
        <stat id="548" name="pciowow" type="reqs" cat="14-pc_uwrites"/>
        <stat id="549" name="pciow" type="bytes" cat="14-pc_uwrites" in_cat_sum="Y"/>
        <stat id="550" name="pciowf" type="bytes" cat="14-pc_uwrites"/>
        <stat id="551" name="pciowow" type="bytes" cat="14-pc_uwrites"/>
        <stat id="552" name="pciordw" type="reqs"  cat="15-pc_ireads" in_cat_sum="Y"/>
        <stat id="553" name="pciordw" type="bytes"  cat="15-pc_ireads" in_cat_sum="Y"/>
        <stat id="554" name="pciordkwr" type="reqs" cat="15-pc_ireads"/>
        <stat id="555" name="pciordkwr" type="bytes" cat="15-pc_ireads"/>
        <stat id="556" name="pciowdkwr" type="reqs" cat="15-pc_ireads"/>
        <stat id="557" name="pciowdkwr" type="bytes" cat="15-pc_ireads"/>
        <stat id="558" name="pciowpop" type="reqs" cat="16-pc_iwrites" in_cat_sum="Y"/>
        <stat id="559" name="pciowpop" type="bytes" cat="16-pc_iwrites" in_cat_sum="Y"/>
        <stat id="540" name="pcby" type="space"  cat="17-pc_spc" in_cat_sum="Y"/>
        <stat id="541" name="pcbyo" type="space" cat="17-pc_spc"/>
        <stat id="542" name="pcbyod" type="space" cat="17-pc_spc"/>
      </stats>]';
    v_xml xmltype;
BEGIN
    SELECT max(dbid),max(bid),max(eid),max(&dur),max(stime),max(etime)
    INTO   did,bid,eid,duration,:v_start,:v_end
    FROM   (
        SELECT /*+ordered use_hash(b)*/ 
               (MAX(end_interval_time+0)-MIN(end_interval_time+0))*86400 dur,
                dbid,
                MAX(snap_id) eid,
                MIN(snap_id) bid,
                max(end_interval_time)+0 etime,
                min(end_interval_time)+0 stime,
                incarnation_num
        FROM   dba_hist_snapshot a JOIN dba_hist_cell_global b USING(snap_id,dbid)
        WHERE  dbid=:dbid
        AND    end_interval_time+0 between nvl(to_date(nvl(:V1,:starttime),'YYMMDDHH24MI'),SYSDATE - 7) AND nvl(to_date(nvl(:V2,:endtime),'YYMMDDHH24MI'),SYSDATE)
        GROUP  BY dbid,incarnation_num
        ORDER  BY incarnation_num DESC)
    WHERE  ROWNUM<2;

    OPEN :c_space FOR 
        WITH gstats0 AS
        (SELECT nvl(cell_hash, 0) cellhash,
                CASE WHEN metric_name LIKE '%allocated - large writes%' THEN 'Large Writes' ELSE metric_name END n,
                SUM(metric_value) v
        FROM   dba_hist_cell_global
        WHERE  dbid=did and snap_id=eid
        GROUP  BY CASE WHEN metric_name LIKE '%allocated - large writes%' THEN 'Large Writes' ELSE metric_name END,
                    ROLLUP(cell_hash)),
        gstats AS
        (SELECT *
        FROM   gstats0
        UNION ALL
        SELECT cellhash,'SCAN',
                SUM(decode(n,'Flash cache bytes allocated',v,'Flash cache bytes allocated for OLTP data',-v,'Large Writes',-v,'Flash cache bytes used - columnar',-v,'Flash cache bytes used - columnar keep',v,0))
        FROM   gstats0
        GROUP  BY cellhash)
        SELECT *
        FROM   (SELECT nvl(cell, '--TOTAL--') cell,
                    nvl(cellhash, 0) cellhash,
                    SUM(DECODE(disktype, 'HardDisk', 1, 0)) "Hard|Disks",
                    SUM(DECODE(disktype, 'HardDisk', 0, 1)) "Flash|Disks",
                    SUM(DECODE(disktype, 'HardDisk', siz)) "HD|Size",
                    SUM(DECODE(disktype, 'FlashDisk', siz)) "FD|Size",
                    SUM(siz) "Total|Size",
                    SUM(freeSpace) "Un-|Alloc",
                    '|' "|"
                FROM   (SELECT cellname, cell, CELLHASH, b.*
                        FROM   dba_hist_cell_config a,
                            XMLTABLE('/' PASSING xmltype(a.confval) COLUMNS cell path 'context/@cell') c,
                            XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                                        NAME VARCHAR2(300) path 'name',
                                        diskType VARCHAR2(300) path 'diskType',
                                        siz INT path 'size',
                                        freeSpace INT path 'freeSpace') b
                        WHERE  conftype = 'CELLDISK'
                        AND    (dbid, cellhash, CURRENT_SNAP_ID) IN
                            (SELECT dbid, cellhash, MAX(CURRENT_SNAP_ID)
                                FROM   dba_hist_cell_config
                                WHERE  conftype = 'CELLDISK'
                                AND    dbid = :dbid
                                GROUP  BY dbid, cellhash)) a
                GROUP  BY ROLLUP((cell, cellname, CELLHASH)))
        RIGHT  JOIN (SELECT *
                    FROM   gstats
                    PIVOT(MAX(v)
                    FOR    n IN('Flash cache bytes allocated' AS "Alloc|FCache",
                                'Flash cache bytes allocated for OLTP data' AS "Alloc|OLTP",
                                'SCAN' AS "Alloc|Scan",
                                'Flash cache bytes used - columnar' AS "Used|Columnar",
                                'Flash cache bytes allocated for unflushed data' AS "OLTP|Dirty",
                                'Large Writes' AS "Large|Writes",
                                'Flash cache bytes used' AS "FCache|Used",
                                'Flash cache bytes used for OLTP data' AS "Used|OLTP",
                                'Flash cache bytes used - keep objects' AS "FCache|Keep",
                                'Flash cache bytes allocated for OLTP keep objects' AS "Keep|OLTP",
                                'Flash cache bytes used - columnar keep' AS "Keep|Columnar",
                                '|' AS "|",
                                'RAM cache bytes allocated' AS "Alloc|RAM",
                                'RAM cache bytes allocated for OLTP data' AS "RAM|OLTP"))) b
        USING  (cellhash);

   
    
    WITH meta AS
     (SELECT *
      FROM   xmltable('/stats/stat' --
                      passing xmltype(c_meta) columns --
                      id NUMBER path '@id',
                      stat_name VARCHAR2(32) path '@name',
                      stat_type VARCHAR2(10) path '@type',
                      stat_category VARCHAR2(32) path '@cat',
                      stat_subcategory VARCHAR2(32) path '@sub',
                      in_cat_sum VARCHAR2(1) path '@in_cat_sum')),
    cell_stats AS
     (SELECT 1 id,
             s.dbid,
             s.cell_hash,
             cn.cell_name,
             num_cells,
             stat_name,
             stat_category,
             stat_subcategory,
             nullif(cat_rq, 0) cat_rq,
             nullif(cat_by, 0)  cat_mb,
             nullif(cat_rqps, 0) cat_rqps,
             nullif(cat_byps, 0)  cat_mbps,
             nullif(cat_spc, 0)  cat_spcmb,
             -- value for stat
             nullif(rq, 0) rq,
             nullif(rqps, 0) rqps,
             nullif(bytes, 0)  mb,
             nullif(byps, 0)  mbps,
             nullif(spc, 0)  spcmb,
             -- calculate as % of total for category
             100 * rq / decode(cat_rq, 0, NULL, cat_rq) rq_pct,
             100 * rqps / decode(cat_rqps, 0, NULL, cat_rqps) rqps_pct,
             100 * bytes / decode(cat_by, 0, NULL, cat_by) by_pct,
             100 * byps / decode(cat_byps, 0, NULL, cat_byps) byps_pct,
             100 * spc / decode(cat_spc, 0, NULL, cat_spc) spc_pct,
             -- calculate partial writes
             -- make sure we do not get negative numbers
             CASE
                 WHEN stat_name = 'fciow' AND rq > tmp_rq THEN
                  rq - tmp_rq
                 ELSE
                  NULL
             END fciorqwp,
             (CASE
                 WHEN stat_name = 'fciow' AND bytes > tmp_by THEN
                  bytes - tmp_by
                 ELSE
                  NULL
             END)  fciombwp,
             CASE
                 WHEN stat_name = 'fciow' AND rqps > tmp_rqps THEN
                  rqps - tmp_rqps
                 ELSE
                  NULL
             END fciorqwp_ps,
             (CASE
                 WHEN stat_name = 'fciow' AND byps > tmp_byps THEN
                  byps - tmp_byps
                 ELSE
                  NULL
             END)  fciombwp_ps,
             -- calculate efficiency
             eff_denom,
             fcciobysave,
             CASE
                 WHEN stat_name IN ('fcoior', 'rcior') THEN
                  100 * (rq / decode(eff_denom, 0, NULL, eff_denom))
                 WHEN stat_name = 'fckpior' THEN
                  100 * (rq / decode(eff_denom, 0, NULL, eff_denom))
                 WHEN stat_name = 'fcsior' THEN
                  100 * (bytes / decode(eff_denom, 0, NULL, eff_denom))
             -- note we use save/elig for fcc
                 WHEN stat_name = 'fccior' THEN
                  100 * (fcciobysave / decode(eff_denom, 0, NULL, eff_denom))
                 WHEN stat_name = 'rcbyo' THEN
                  100 * (spc / decode(eff_denom, 0, NULL, eff_denom))
             END eff,
             -- now do the same thing for the 'All' node
             nullif(cat_rq_s, 0) cat_rq_s,
             nullif(cat_by_s, 0)  cat_mb_s,
             nullif(cat_rqps_s, 0) cat_rqps_s,
             nullif(cat_byps_s, 0)  cat_mbps_s,
             nullif(cat_spc_s, 0)  cat_spcmb_s,
             nullif(rq_s, 0) rq_s,
             nullif(rqps_s, 0) rqps_s,
             nullif(bytes_s, 0)  mb_s,
             nullif(byps_s, 0)  mbps_s,
             nullif(spc_s, 0)  spcmb_s,
             -- calculate as % of total for category
             100 * rq_s / decode(cat_rq_s, 0, NULL, cat_rq_s) rq_pct_s,
             100 * rqps_s / decode(cat_rqps_s, 0, NULL, cat_rqps_s) rqps_pct_s,
             100 * bytes_s / decode(cat_by_s, 0, NULL, cat_by_s) by_pct_s,
             100 * byps_s / decode(cat_byps_s, 0, NULL, cat_byps_s) byps_pct_s,
             100 * spc_s / decode(cat_spc_s, 0, NULL, cat_spc_s) spc_pct_s,
             -- calculate partial writes
             -- make sure we do not get negative numbers
             CASE
                 WHEN stat_name = 'fciow' AND rq_s > tmp_rq_s THEN
                  rq_s - tmp_rq_s
                 ELSE
                  NULL
             END fciorqwp_s,
             (CASE
                 WHEN stat_name = 'fciow' AND bytes_s > tmp_by_s THEN
                  bytes_s - tmp_by_s
                 ELSE
                  NULL
             END)  fciombwp_s,
             CASE
                 WHEN stat_name = 'fciow' AND rqps_s > tmp_rqps_s THEN
                  rqps_s - tmp_rqps_s
                 ELSE
                  NULL
             END fciorqwp_ps_s,
             (CASE
                 WHEN stat_name = 'fciow' AND byps_s > tmp_byps_s THEN
                  byps_s - tmp_byps_s
                 ELSE
                  NULL
             END)  fciombwp_ps_s,
             -- calculate efficiency
             eff_denom_s,
             fcciobysave_s,
             CASE
                 WHEN stat_name IN ('fcoior', 'rcior') THEN
                  100 * (rq_s / decode(eff_denom_s, 0, NULL, eff_denom_s))
                 WHEN stat_name = 'fckpior' THEN
                  100 * (rq_s / decode(eff_denom_s, 0, NULL, eff_denom_s))
                 WHEN stat_name = 'fcsior' THEN
                  100 * (bytes_s / decode(eff_denom_s, 0, NULL, eff_denom_s))
             -- note we use save/elig for fcc
                 WHEN stat_name = 'fccior' THEN
                  100 * (fcciobysave_s / decode(eff_denom_s, 0, NULL, eff_denom_s))
                 WHEN stat_name = 'rcbyo' THEN
                  100 * (spc_s / decode(eff_denom_s, 0, NULL, eff_denom_s))
             END eff_s,
             -- rank cells
             CASE
                 WHEN stat_category != '09-rc_spc' THEN
                  dense_rank() over(PARTITION BY stat_category ORDER BY cat_rqps DESC, cat_byps DESC, cn.cell_name)
                 ELSE
                  dense_rank() over(PARTITION BY stat_category ORDER BY cat_spc DESC, cat_rqps DESC, cat_byps DESC, cn.cell_name)
             END rn,
             -- get first occurrence of stat
             row_number() over(PARTITION BY stat_category, stat_name ORDER BY cat_rqps DESC, cat_byps DESC, cat_spc DESC, cn.cell_name) rn_stat
      FROM   dba_hist_cell_name cn,
             (SELECT dbid,
                     cell_hash,
                     stat_name,
                     rq,
                     rqps,
                     bytes,
                     byps,
                     spc,
                     stat_category,
                     stat_subcategory,
                     -- now populate the derived columns for all rows 
                     -- in the category so we can derive the values
                     SUM(tmp_rq) over(PARTITION BY cell_hash, stat_category) tmp_rq,
                     SUM(tmp_by) over(PARTITION BY cell_hash, stat_category) tmp_by,
                     SUM(tmp_rqps) over(PARTITION BY cell_hash, stat_category) tmp_rqps,
                     SUM(tmp_byps) over(PARTITION BY cell_hash, stat_category) tmp_byps,
                     -- also populate columns for denominator for efficiency
                     SUM(eff_denom) over(PARTITION BY cell_hash, stat_subcategory) eff_denom,
                     SUM(fcciobysave) over(PARTITION BY cell_hash, stat_subcategory) fcciobysave,
                     -- get total for category for each cell
                     SUM(cat_rq) over(PARTITION BY cell_hash, stat_category) cat_rq,
                     SUM(cat_by) over(PARTITION BY cell_hash, stat_category) cat_by,
                     SUM(cat_rqps) over(PARTITION BY cell_hash, stat_category) cat_rqps,
                     SUM(cat_byps) over(PARTITION BY cell_hash, stat_category) cat_byps,
                     SUM(cat_spc) over(PARTITION BY cell_hash, stat_category) cat_spc,
                     -- get totals for 'All' node
                     SUM(rq) over(PARTITION BY stat_name) rq_s,
                     SUM(bytes) over(PARTITION BY stat_name) bytes_s,
                     SUM(rqps) over(PARTITION BY stat_name) rqps_s,
                     SUM(byps) over(PARTITION BY stat_name) byps_s,
                     SUM(spc) over(PARTITION BY stat_name) spc_s,
                     -- get total for derived columns for 'All' node
                     SUM(tmp_rq) over(PARTITION BY stat_category) tmp_rq_s,
                     SUM(tmp_by) over(PARTITION BY stat_category) tmp_by_s,
                     SUM(tmp_rqps) over(PARTITION BY stat_category) tmp_rqps_s,
                     SUM(tmp_byps) over(PARTITION BY stat_category) tmp_byps_s,
                     -- and totals to denominator for 'All' node
                     SUM(eff_denom) over(PARTITION BY stat_subcategory) eff_denom_s,
                     SUM(fcciobysave) over(PARTITION BY stat_subcategory) fcciobysave_s,
                     -- and get total for the category over all cells
                     SUM(cat_rq) over(PARTITION BY stat_category) cat_rq_s,
                     SUM(cat_by) over(PARTITION BY stat_category) cat_by_s,
                     SUM(cat_rqps) over(PARTITION BY stat_category) cat_rqps_s,
                     SUM(cat_byps) over(PARTITION BY stat_category) cat_byps_s,
                     SUM(cat_spc) over(PARTITION BY stat_category) cat_spc_s,
                     -- number of cells
                     COUNT(DISTINCT cell_hash) over() num_cells
              FROM   ( -- partial pivot and create category/subcategories
                      SELECT dbid,
                              cell_hash,
                              stat_name,
                              MAX(stat_category) stat_category,
                              MAX(stat_subcategory) stat_subcategory,
                              -- create columns for reqs, bytes, rqps, bps
                              SUM(decode(stat_type, 'reqs', total_value, 0)) rq,
                              SUM(decode(stat_type, 'reqs', persec_value, 0)) rqps,
                              SUM(decode(stat_type, 'bytes', total_value, 0)) bytes,
                              SUM(decode(stat_type, 'bytes', persec_value, 0)) byps,
                              SUM(decode(stat_type, 'space', current_value, 0)) spc,
                              -- start columns for deriving partial writes
                              SUM(CASE
                                      WHEN stat_type = 'reqs' AND stat_name IN ('fciowf','fciowow',
                                 'fclwrej','fclwrejcglwth','fclwrejflwr',
                                 'fclwrejlwth','fclwrejmxlm','fclwrejgllm',
                                 'fclwrejflbs','fclwrejkpcl','fclwrejiormhd') THEN
                                       total_value
                                  END) tmp_rq,
                              SUM(CASE
                                      WHEN stat_type = 'bytes' AND stat_name IN ('fciowf','fciowow') THEN
                                       total_value
                                  END) tmp_by,
                              SUM(CASE
                                      WHEN stat_type = 'reqs' AND stat_name IN ('fciowf','fciowow',
                                 'fclwrej','fclwrejcglwth','fclwrejflwr',
                                 'fclwrejlwth','fclwrejmxlm','fclwrejgllm',
                                 'fclwrejflbs','fclwrejkpcl','fclwrejiormhd') THEN
                                       persec_value
                                  END) tmp_rqps,
                              SUM(CASE
                                      WHEN stat_type = 'bytes' AND stat_name IN ('fciowf','fciowow')THEN
                                       persec_value
                                  END) tmp_byps,
                              -- start columns for denominator for efficiency
                              -- also denominator for space usage to calculate %
                              SUM(CASE
                                      WHEN stat_type = 'reqs' AND stat_name IN ('fcoior', 'fckpior', 'fcoiorqrm', 'fckpiorqrm', 'rcior', 'rciorm','pcior','pciorm') THEN
                                       total_value
                                      WHEN stat_type = 'bytes' AND stat_name IN ('fcsiobyra', 'fcciobyelig') THEN
                                       total_value
                                      WHEN stat_type = 'space' AND stat_name IN ('rcby','pcby') THEN
                                       current_value
                                  END) eff_denom,
                              -- start column for additional information for fcc
                              SUM(CASE
                                      WHEN stat_type = 'bytes' AND stat_name = 'fcciobysave' THEN
                                       total_value
                                  END) fcciobysave,
                              -- start columns for category reqs/bytes
                              SUM(CASE
                                      WHEN stat_type = 'reqs' AND in_cat_sum = 'Y' THEN
                                       total_value
                                  END) cat_rq,
                              SUM(CASE
                                      WHEN stat_type = 'bytes' AND in_cat_sum = 'Y' THEN
                                       total_value
                                  END) cat_by,
                              SUM(CASE
                                      WHEN stat_type = 'reqs' AND in_cat_sum = 'Y' THEN
                                       persec_value
                                  END) cat_rqps,
                              SUM(CASE
                                      WHEN stat_type = 'bytes' AND in_cat_sum = 'Y' THEN
                                       persec_value
                                  END) cat_byps,
                              SUM(CASE
                                      WHEN stat_type = 'space' AND in_cat_sum = 'Y' THEN
                                       current_value
                                  END) cat_spc
                      FROM   (SELECT e.dbid,
                                      e.cell_hash,
                                      e.metric_id,
                                      e.metric_value - nvl(b.metric_value, 0) total_value,
                                      -- per second value
                                      (e.metric_value - nvl(b.metric_value, 0)) / duration persec_value,
                                      -- current value
                                      e.metric_value current_value,
                                      -- get stat_name
                                      st.stat_name,
                                      st.stat_type,
                                      st.stat_category,
                                      st.stat_subcategory,
                                      st.in_cat_sum
                               FROM   dba_hist_cell_global b, dba_hist_cell_global e, meta st
                               WHERE  e.dbid = did
                               AND    b.snap_id(+) = bid
                               AND    e.snap_id = eid
                               AND    b.dbid(+) = e.dbid
                               AND    b.cell_hash(+) = e.cell_hash
                               AND    b.incarnation_num(+) = e.incarnation_num
                               AND    b.metric_id(+) = e.metric_id
                               AND    (e.metric_id BETWEEN 180 AND 218 OR e.metric_id BETWEEN 300 AND 307 OR e.metric_id BETWEEN 314 AND 317 OR
                                     e.metric_id BETWEEN 370 AND 380 OR e.metric_id BETWEEN 390 AND 397)
                               AND    e.metric_id = st.id)
                      GROUP  BY dbid, cell_hash, stat_name)) s
      WHERE  cn.dbid = s.dbid
      AND    cn.cell_hash = s.cell_hash
      AND    cn.snap_id = eid)
    SELECT xmlelement("statsgroup", xmlagg(cells_xml ORDER BY category))
    INTO   v_xml
    FROM   (SELECT category, xmlelement("cellstats", xmlattributes(disp_category AS "type"), all_xml, cell_xml) cells_xml
            FROM   (SELECT category,
                           MAX(disp_category) disp_category,
                           CASE
                               WHEN MAX(cat_rq_s) IS NOT NULL OR MAX(cat_mb_s) IS NOT NULL OR MAX(cat_spcmb_s) IS NOT NULL THEN
                                xmlelement("cell",
                                           xmlattributes('All' AS "name", MAX(num_cells) AS "num_cells"),
                                           -- build XML for user reads total
                                           CASE
                                               WHEN category = '01-fc_ureads' AND (MAX(cat_rq_s) IS NOT NULL OR MAX(cat_mb_s) IS NOT NULL) THEN
                                                xmlelement("stat",
                                                           xmlattributes('fcior' AS "name",
                                                                         round(MAX(cat_rq_s), 2) AS "rq",
                                                                         round(MAX(cat_rqps_s), 2) AS "rqps",
                                                                         round(MAX(cat_mb_s), 2) AS "mb",
                                                                         round(MAX(cat_mbps_s), 2) AS "mbps"))
                                           END,
                                           xmlagg(all_xml ORDER BY rn),
                                           -- add XML for partial writes
                                           CASE
                                               WHEN category = '02-fc_uwrites' AND (MAX(fciorqwp_s) IS NOT NULL OR MAX(fciombwp_s) IS NOT NULL) THEN
                                                xmlelement("stat",
                                                           xmlattributes('fciowp' AS "name",
                                                                         round(MAX(fciorqwp_s), 2) AS "rq",
                                                                         round(MAX(fciorqwp_ps_s), 2) AS "rqps",
                                                                         round(MAX(fciombwp_s), 2) AS "mb",
                                                                         round(MAX(fciombwp_ps_s), 2) AS "mbps",
                                                                         -- calculate % of total
                                                                         round(100 * MAX(fciorqwp_s) / decode(MAX(cat_rq_s), 0, NULL, MAX(cat_rq_s)), 2) AS "rqpct",
                                                                         -- calculate % of total
                                                                         round(100 * MAX(fciombwp_s) / decode(MAX(cat_mb_s), 0, NULL, MAX(cat_mb_s)), 2) AS "mbpct"))
                                           END)
                           END all_xml,
                           xmlagg(cell_xml ORDER BY rn) cell_xml
                    FROM   (SELECT cat.category,
                                   rn,
                                   MAX(cat.cat_disp) disp_category,
                                   MAX(num_cells) num_cells,
                                   MAX(cat_rq_s) cat_rq_s,
                                   MAX(cat_mb_s) cat_mb_s,
                                   MAX(cat_rqps_s) cat_rqps_s,
                                   MAX(cat_mbps_s) cat_mbps_s,
                                   MAX(cat_spcmb_s) cat_spcmb_s,
                                   MAX(fciorqwp_s) fciorqwp_s,
                                   MAX(fciorqwp_ps_s) fciorqwp_ps_s,
                                   MAX(fciombwp_s) fciombwp_s,
                                   MAX(fciombwp_ps_s) fciombwp_ps_s,
                                   -- build XML for 'All' node
                                   xmlagg(CASE
                                              WHEN rn_stat = 1 AND (rq_s IS NOT NULL OR mb_s IS NOT NULL OR spcmb_s IS NOT NULL) THEN
                                               xmlelement("stat",
                                                          xmlattributes(decode(stat_name,
                                                                               'fcoior',
                                                                               'fcioroltp',
                                                                               'fcsior',
                                                                               'fciordw',
                                                                               'fcoiorqrm',
                                                                               'fciorm',
                                                                               stat_name) AS "name",
                                                                        round(rq_s, 2) AS "rq",
                                                                        round(rqps_s, 2) AS "rqps",
                                                                        round(mb_s, 2) AS "mb",
                                                                        round(mbps_s, 2) AS "mbps",
                                                                        round(spcmb_s, 2) AS "spcmb",
                                                                        -- additional efficiency stats
                                                                        decode(stat_name, 'fcoior', round(eff_denom_s - rq_s, 2)) AS "misses",
                                                                        decode(stat_name, 'fcsior', round(eff_denom_s , 2)) AS "att",
                                                                        decode(stat_name, 'fcsior', round(eff_denom_s  / duration, 2)) AS "attps",
                                                                        decode(stat_name, 'fccior', round(eff_denom_s , 2)) AS "elig",
                                                                        decode(stat_name, 'fccior', round(fcciobysave_s , 2)) AS "save",
                                                                        CASE
                                                                            WHEN stat_name IN ('fcoior', 'fckpior', 'fcsior', 'fccior', 'rcior', 'rcbyo') THEN
                                                                             round(eff_s, 2)
                                                                        END AS "ratio",
                                                                        decode(stat_category, '02-fc_uwrites', round(rq_pct_s, 2)) AS "rqpct",
                                                                        decode(stat_category, '02-fc_uwrites', round(by_pct_s, 2)) AS "mbpct"))
                                          END ORDER BY stat_name) all_xml,
                                   CASE
                                       WHEN cell_name IS NOT NULL AND (MAX(cat_rq) IS NOT NULL OR MAX(cat_mb) IS NOT NULL OR MAX(cat_spcmb) IS NOT NULL) THEN
                                        xmlelement("cell",
                                                   xmlattributes(cell_name AS "name", rn AS "rn"),
                                                   -- add XML for user reads total
                                                   CASE
                                                       WHEN category = '01-fc_ureads' AND (MAX(cat_rq) IS NOT NULL OR MAX(cat_mb) IS NOT NULL) THEN
                                                        xmlelement("stat",
                                                                   xmlattributes('fcior' AS "name",
                                                                                 round(MAX(cat_rq), 2) AS "rq",
                                                                                 round(MAX(cat_rqps), 2) AS "rqps",
                                                                                 round(MAX(cat_mb), 2) AS "mb",
                                                                                 round(MAX(cat_mbps), 2) AS "mbps"))
                                                   END,
                                                   xmlagg(CASE
                                                              WHEN rq IS NOT NULL OR mb IS NOT NULL OR spcmb IS NOT NULL THEN
                                                               xmlelement("stat",
                                                                          xmlattributes(decode(stat_name,
                                                                                               'fcoior',
                                                                                               'fcioroltp',
                                                                                               'fcsior',
                                                                                               'fciordw',
                                                                                               'fcoiorqrm',
                                                                                               'fciorm',
                                                                                               stat_name) AS "name",
                                                                                        round(rq, 2) AS "rq",
                                                                                        round(rqps, 2) AS "rqps",
                                                                                        round(mb, 2) AS "mb",
                                                                                        round(mbps, 2) AS "mbps",
                                                                                        round(spcmb, 2) AS "spcmb",
                                                                                        -- additional efficiency stats
                                                                                        decode(stat_name, 'fcoior', round(eff_denom - rq, 2)) AS "misses",
                                                                                        decode(stat_name, 'fcsior', round(eff_denom , 2)) AS "att",
                                                                                        decode(stat_name, 'fcsior', round(eff_denom  / duration, 2)) AS "attps",
                                                                                        decode(stat_name, 'fccior', round(eff_denom , 2)) AS "elig",
                                                                                        decode(stat_name, 'fccior', round(fcciobysave , 2)) AS "save",
                                                                                        CASE
                                                                                            WHEN stat_name IN ('fcoior', 'fckpior', 'fcsior', 'fccior', 'rcior', 'rcbyo') THEN
                                                                                             round(eff, 2)
                                                                                        END AS "ratio",
                                                                                        decode(stat_category, '02-fc_uwrites', round(rq_pct, 2)) AS "rqpct",
                                                                                        decode(stat_category, '02-fc_uwrites', round(by_pct, 2)) AS "mbpct"))
                                                          END ORDER BY stat_name),
                                                   -- add XML for partial writes
                                                   CASE
                                                       WHEN category = '02-fc_uwrites' AND (MAX(fciorqwp) IS NOT NULL OR MAX(fciombwp) IS NOT NULL) THEN
                                                        xmlelement("stat",
                                                                   xmlattributes('fciowp' AS "name",
                                                                                 round(MAX(fciorqwp), 2) AS "rq",
                                                                                 round(MAX(fciorqwp_ps), 2) AS "rqps",
                                                                                 round(MAX(fciombwp), 2) AS "mb",
                                                                                 round(MAX(fciombwp_ps), 2) AS "mbps",
                                                                                 -- calculate % of total
                                                                                 round(100 * MAX(fciorqwp) / decode(MAX(cat_rq), 0, NULL, MAX(cat_rq)), 2) AS "rqpct",
                                                                                 -- calculate % of total
                                                                                 round(100 * MAX(fciombwp) / decode(MAX(cat_mb), 0, NULL, MAX(cat_mb)), 2) AS "mbpct"))
                                                   END)
                                   END cell_xml
                            FROM   cell_stats s,
                                   (SELECT DISTINCT stat_category category, substr(stat_category, 4) cat_disp
                                    FROM   meta) cat
                            WHERE  s.stat_category(+) = cat.category
                            GROUP  BY cat.category, rn, cell_name)
                    GROUP  BY category));
   OPEN :c_reads FOR
        SELECT cell,
               hits "Hit|&mb",
               active_2nd_hits "2nd|Hits",
               active_2nd_misses "2nd|Miss",
               hits_r "Hit|&io",
               misses "Hit|Miss",
               round(100*hits_r/nullif(hits_r+misses,0),2) "Hit|Rate",
               '|' "|",
               oltp "OLTP|&mb",
               oltp_r "OLTP|&io", 
               oltp_p "OLTP|Hit%",
               '|' "|",
               SCAN_d "Scan|Reqs",
               SCAN "Scan|&mb",
               SCAN_r "Scan|&io", 
               SCAN_p "Scan|Hit%",
               '|' "|",
               cc "Columnar|&mb",
               cc_elig "Columnar|Elig",
               cc_save "Columnar|Saved",
               cc_r "Columnar|&io", 
               cc_p "Columnar|Eff %",
               '|' "|",
               keeps "Keep|&mb",
               keeps_r "Keep|&io", 
               miss_keeps "Keep|Miss",
               keeps_p "Keep|Hit%"
        FROM XMLTABLE('/statsgroup/cellstats[@type="fc_ureads"]/cell' 
             PASSING v_xml COLUMNS --
                cell varchar2(128) PATH '@name',
                hits NUMBER PATH 'stat[@name="fcior"]/@mbps',
                hits_r NUMBER PATH 'stat[@name="fcior"]/@rqps',
                misses NUMBER PATH 'stat[@name="fciorm"]/@rqps',
                oltp NUMBER PATH 'stat[@name="fcioroltp"]/@mbps',
                oltp_r NUMBER PATH 'stat[@name="fcioroltp"]/@rqps',
                oltp_p NUMBER PATH 'stat[@name="fcioroltp"]/@ratio',
                SCAN NUMBER PATH 'stat[@name="fciordw"]/@mbps',
                scan_d NUMBER PATH 'stat[@name="fciordw"]/@attps',
                scan_r NUMBER PATH 'stat[@name="fciordw"]/@rqps',
                scan_p NUMBER PATH 'stat[@name="fciordw"]/@ratio',
                scan_attr NUMBER PATH 'stat[@name="fciordw"]/@attps',
                cc NUMBER PATH 'stat[@name="fccior"]/@mbps',
                cc_r NUMBER PATH 'stat[@name="fccior"]/@rqps',
                cc_p NUMBER PATH 'stat[@name="fccior"]/@ratio',
                cc_elig NUMBER PATH 'stat[@name="fcciobyelig"]/@mbps',
                cc_save NUMBER PATH 'stat[@name="fcciobysave"]/@mbps',
                keeps NUMBER PATH 'stat[@name="fckpior"]/@mbps',
                keeps_r NUMBER PATH 'stat[@name="fckpior"]/@rqps',
                keeps_p NUMBER PATH 'stat[@name="fckpior"]/@ratio',
                miss_keeps NUMBER PATH 'stat[@name="fckpiorqrm"]/@rqps',
                active_2nd_hits NUMBER PATH 'stat[@name="fciorash"]/@mbps',
                active_2nd_hits_r NUMBER PATH 'stat[@name="fciorash"]/@rqps',
                active_2nd_misses NUMBER PATH 'stat[@name="fciorasm"]/@mbps',
                active_2nd_misses_r NUMBER PATH 'stat[@name="fciorasm"]/@rqps'
       )
    ORDER BY DECODE(cell,'All',' ',LOWER(cell));
    
    
    OPEN :c_writes FOR
        SELECT cell,total "Total|&mb",fst "FirstWrite|&mb", onw "OverWrite|&mb",pop "Populate|Miss-&mb",'|' "|",
               total_r "Total|&io",fst_r "FirstWrite|&io", onw_r "OverWrite|&io",pop_r "Populate|Miss-&io",'|' "|",
               lgw "LargeWrite|&mb",lgw_spill "Temp|Spill",lgw_data "Data/|Temp",lgw_only "Write|Only",'|' "|",
               lgw_r "LargeWrite|&io",lgw_spill_r "TempSpill|&io",lgw_data_r "DataTemp|&io",lgw_only_r "WriteOnly|&io"
        FROM XMLTABLE('/statsgroup/cellstats[@type="fc_uwrites"]/cell' 
             PASSING v_xml COLUMNS --
                cell varchar2(128) PATH '@name',
                total       NUMBER PATH 'stat[@name="fciow"]/@mbps',
                fst         NUMBER PATH 'stat[@name="fciowf"]/@mbps',
                onw         NUMBER PATH 'stat[@name="fciowow"]/@mbps',
                POP         NUMBER PATH 'stat[@name="fciowp"]/@mbps',
                total_r     NUMBER PATH 'stat[@name="fciow"]/@rqps',
                fst_r       NUMBER PATH 'stat[@name="fciowf"]/@rqps',
                onw_r       NUMBER PATH 'stat[@name="fciowow"]/@rqps',
                POP_r       NUMBER PATH 'stat[@name="fciowp"]/@rqps',
                lgw         NUMBER PATH 'sum(stat[contains("fclwmrw fclwnrw fclwrow",@name)]/@mbps)',
                lgw_spill   NUMBER PATH 'stat[@name="fclwrow"]/@mbps',
                lgw_data    NUMBER PATH 'stat[@name="fclwmrw"]/@mbps',
                lgw_only    NUMBER PATH 'stat[@name="fclwnrw"]/@mbps',
                lgw_r       NUMBER PATH 'sum(stat[contains("fclwmrw fclwnrw fclwrow",@name)]/@rqps)',
                lgw_spill_r NUMBER PATH 'stat[@name="fclwrow"]/@rqps',
                lgw_data_r  NUMBER PATH 'stat[@name="fclwmrw"]/@rqps',
                lgw_only_r  NUMBER PATH 'stat[@name="fclwnrw"]/@rqps'
       )
    ORDER BY DECODE(cell,'All',' ',LOWER(cell));

    OPEN :c_ram FOR
        SELECT cell,
               SUM(fciowpop) "Populate|&mb",
               SUM(fciowpop_r) "Populate|&io",
               SUM(fckpiowpop) "Pop-Keep|&mb",
               SUM(fckpiowpop_r) "Pop-Keep|&io",
               SUM(fcciowpop) "Pop-CC|&mb",
               SUM(fcciowpop_r) "Pop-CC|&io",
               '|-|' "|-|",
               SUM(fcsfrhdr) "Scan Used|Free Header",
               SUM(fcsrepoltp) "Scan|OLTP",
               SUM(fcsrepdw) "Scan|DW",
               SUM(fcsrepself) "Scan|Self",
               SUM(fcsrepzhit) "Scan|Zero Hit",
               '|-|' "|-|",
               SUM(hits) "RAM|&mb",
               SUM(hits_r) "RAM|&io",
               SUM(hits_p) "RAM|Hit%",
               '|' "|",
               SUM(miss) "RAM|Miss",
               SUM(miss_r) "MISS|&io",
               '|' "|",
               SUM(wr) "RAM|Write",
               SUM(wr_r) "Write|&io"
        FROM XMLTABLE('/statsgroup/cellstats[contains("fc_iwrites rc_ureads rc_iwrites fcs_pop",@type)]/cell' 
             PASSING v_xml COLUMNS --
                cell varchar2(128) PATH '@name',
                fciowpop NUMBER PATH 'stat[@name="fciowpop"]/@mbps',
                fciowpop_r NUMBER PATH 'stat[@name="fciowpop"]/@rqps',
                fckpiowpop NUMBER PATH 'stat[@name="fckpiowpop"]/@mbps',
                fckpiowpop_r NUMBER PATH 'stat[@name="fckpiowpop"]/@rqps',
                fcciowpop NUMBER PATH 'stat[@name="fcciowpop"]/@mbps',
                fcciowpop_r NUMBER PATH 'stat[@name="fcciowpop"]/@rqps',
                fcsfrhdr NUMBER PATH 'stat[@name="fcsfrhdr"]/@rqps',
                fcsrepoltp NUMBER PATH 'stat[@name="fcsrepoltp"]/@rqps',
                fcsrepdw NUMBER PATH 'stat[@name="fcsrepdw"]/@rqps',
                fcsrepself NUMBER PATH 'stat[@name="fcsrepself"]/@rqps',
                fcsrepzhit NUMBER PATH 'stat[@name="fcsrepzhit"]/@rqps',
                hits NUMBER PATH 'stat[@name="rcior"]/@mbps',
                hits_r NUMBER PATH 'stat[@name="rcior"]/@rqps',
                hits_p NUMBER PATH 'stat[@name="rcior"]/@ratio',
                miss NUMBER PATH 'stat[@name="rciorm"]/@mbps',
                miss_r NUMBER PATH 'stat[@name="rciorm"]/@rqps',
                wr NUMBER PATH 'stat[@name="rciowpop"]/@mbps',
                wr_r NUMBER PATH 'stat[@name="rciowpop"]/@rqps'
       )
       GROUP BY cell
    ORDER BY DECODE(cell,'All',' ',LOWER(cell));    
END;
/

grid {
    [[c_space grid={topic='Flash Cache Space (at &v_end)',autosize='trim'}]],
    '-',
    [[c_reads grid={topic='Flash Cache User Reads (&v_start -- &v_end)'}]],
    '-',
    [[c_writes grid={topic='Flash Cache User Writes (&v_start -- &v_end)',autohide='on'}]],
    '-',
    [[c_ram grid={topic='Population || Flash Cache Scan Writes || Memory Cache Reads & Writes',autohide='on'}]]
}