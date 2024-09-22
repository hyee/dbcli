/*[[
    Show network latency information. Usage: @@NAME [machine_key_word] {[YYMMDDHH24MISS] [YYMMDDHH24MISS] | -snap"<secs>"} [-dash]
    -dash: source table is Dba_Hist_Active_Sess_History instead of gv$active_session_history
    -snap: get the recent ASH info within <secs> seconds. i.e.: @@NAME -snap"3600"

    Sample Output:
    ==============
    MACHINE             EVENT              AAS LATENCY MAX_LATENCY AVG_BYTES MAX_BYTES      TOP_1_SQL          TOP_2_SQL         TOP_3_SQL
    ------- ----------------------------- ---- ------- ----------- --------- --------- ------------------- ----------------- -----------------
    Will    SQL*Net more data from client 1161       0       4.36m      3  B      3  B 2vchm7jzztzng(1161)
    Will                                   188 74.00us      25.94m   7.95 KB   7.97 KB 74kh4ag109cdv(91)   gvph4rn0sv7kg(17) ahwx914ga4qag(15)
    Will    SQL*Net more data to client     10  4.27ms    363.64ms   7.95 KB   7.96 KB 74kh4ag109cdv(10)
    
    --[[
        @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_}
        &ash: ash={gv$active_session_history}, dash={&check_access_pdb.Active_Sess_History}
        &snap: default={NVL(to_date(nvl('&V2','&STARTTIME'),'YYMMDDHH24MISS'),SYSDATE-7)} snap={sysdate-numtodsinterval(&0,'second')}
        &src: ash={0} dash={1}
        @ver:  11={} default={--}
        @ver12: 12={,a.con_id} default={}
    --]]
]]*/

col latency,max_latency for usmhd2
col avg_bytes,max_bytes for kmg
col "Total time" for pct3
set feed off

PRO ASH Network Summary(Estimated)
PRO ==============================
SELECT  machine,event,aas,latency,max_latency,avg_bytes,max_bytes &ver ,top_1_sql,top_2_sql,top_3_sql
FROM (
    select a.*,row_number() over(partition by gid order by aas desc) rnk
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),1) over(partition by machine,event order by nvl2(sql_id,1,2),aas desc) top_1_sql
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),2) over(partition by machine,event order by nvl2(sql_id,1,2),aas desc) top_2_sql
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),3) over(partition by machine,event order by nvl2(sql_id,1,2),aas desc) top_3_sql
    from (
        select machine,event,count(1) aas,
               PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY nvl2(event,time_waited,wait_time)/nvl2(event,1,2)) latency,
               PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY p2) avg_bytes,
               max(nvl2(event,time_waited,wait_time)/nvl2(event,1,2)) max_latency,max(p2) max_bytes,grouping_id(sql_id) gid, nvl(sql_id,top_level_sql_id) sql_id
        from  &ash
        where p2text='#bytes' 
        and   nvl(wait_class,'Network')='Network'
        and   IN_SQL_EXECUTION='Y'
        and   upper(machine||','||event||','||sql_id) like upper('%&V1%')
        and   nvl2(event,time_waited,wait_time) between 30 and 1e7
        --and   (current_obj#<1 or event is not null)
        and   sample_time BETWEEN &snap AND NVL(to_date(nvl(:V3,:ENDTIME),'YYMMDDHH24MISS'),SYSDATE+1)
        group by machine,event,rollup((sql_id,top_level_sql_id))) a)
WHERE gid  = 1
AND   rnk <= 50
ORDER BY aas desc;

var c1 refcursor "Global Network Wait Events"
var c2 refcursor "Client Network Wait Events"
DECLARE
   did int := :dbid;
   c   sys_refcursor;
BEGIN
    OPEN :c1 FOR
    $IF &src=0 $THEN
        SELECT EVENT,
               ROUND(SUM(TIME_WAITED_MICRO_FG)/SUM(TOTAL_WAITS_FG),2) latency, 
               ratio_to_report(SUM(TIME_WAITED_MICRO_FG)) over() "Total Time"
        FROM   gv$system_event
        WHERE (wait_class='Network' OR wait_class!='Idle' AND event like 'SQL*Net%')
        AND   TOTAL_WAITS_FG>0
        GROUP BY EVENT
        ORDER BY 1;
        OPEN c FOR
            SELECT * FROM (
                SELECT s.machine,e.EVENT,ROUND(SUM(TIME_WAITED_MICRO)/SUM(TOTAL_WAITS),2) latency, 
                       ratio_to_report(SUM(TIME_WAITED_MICRO)) over() "Total Time"
                FROM   gv$session_event e join gv$session s USING(inst_id,sid)
                WHERE (e.wait_class='Network' OR e.wait_class!='Idle' AND e.event like 'SQL*Net%')
                AND   TOTAL_WAITS>0
                and   upper(s.machine||','||e.event) like upper('%&V1%')
                GROUP BY s.machine,e.EVENT
                ORDER BY "Total Time" desc)
            WHERE ROWNUM<=30;
    $ELSE
        SELECT event,ROUND(SUM(micro)/nullif(SUM(cnt),0),2) latency,ratio_to_report(SUM(micro)) over() "Total Time"
        FROM (
            SELECT EVENT_NAME event,
                   TIME_WAITED_MICRO_FG-lag(TIME_WAITED_MICRO_FG) over(partition by instance_number,startup_time,EVENT_NAME &ver12 ORDER BY SNAP_ID) micro,
                   TOTAL_WAITS_FG-lag(TOTAL_WAITS_FG) over(partition by instance_number,startup_time,EVENT_NAME &ver12 ORDER BY SNAP_ID) cnt
            FROM   dba_hist_system_event a
            JOIN   dba_hist_snapshot b
            USING  (instance_number,snap_id,dbid )
            WHERE (wait_class='Network' OR wait_class!='Idle' AND EVENT_NAME like 'SQL*Net%')
            AND   TOTAL_WAITS_FG>0
            AND   end_interval_time+0 BETWEEN &snap AND NVL(to_date(nvl('&V3','&ENDTIME'),'YYMMDDHH24MISS'),SYSDATE+1)
            AND   dbid=did)
        GROUP by EVENT 
        ORDER BY 1;
    $END
    :c2 := c;
END;
/
