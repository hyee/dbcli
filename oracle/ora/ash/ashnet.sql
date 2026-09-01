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

col latency,max_latency,time for usmhd2
col avg_bytes,max_bytes for kmg
col waits for tmb2
col Time% for pct3
set feed off

PRO ASH Network Summary(Estimated)
PRO ==============================
SELECT  machine,event,aas,latency,max_latency,avg_bytes,max_bytes &ver ,top_1_sql,top_2_sql,top_3_sql
FROM (
    SELECT a.*,row_number() OVER(PARTITION BY gid ORDER BY aas DESC) rnk
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),1) OVER(PARTITION BY machine,event ORDER BY nvl2(sql_id,1,2),aas DESC) top_1_sql
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),2) OVER(PARTITION BY machine,event ORDER BY nvl2(sql_id,1,2),aas DESC) top_2_sql
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),3) OVER(PARTITION BY machine,event ORDER BY nvl2(sql_id,1,2),aas DESC) top_3_sql
    FROM (
        SELECT machine,event,count(1) aas,
               percentile_cont(0.5) WITHIN GROUP(ORDER BY nvl2(event,time_waited,wait_time)/nvl2(event,1,2)) latency,
               percentile_cont(0.5) WITHIN GROUP(ORDER BY p2) avg_bytes,
               max(nvl2(event,time_waited,wait_time)/nvl2(event,1,2)) max_latency,max(p2) max_bytes,grouping_id(sql_id) gid, nvl(sql_id,top_level_sql_id) sql_id
        FROM  &ash
        WHERE p2text='#bytes' 
        AND   nvl(wait_class,'Network')='Network'
        AND   in_sql_execution='Y'
        AND   upper(machine||','||event||','||sql_id) LIKE upper('%&V1%')
        AND   (event IS NOT NULL OR nvl2(event,time_waited,wait_time) BETWEEN 30 AND 1e7)
        --and   (current_obj#<1 or event is not null)
        AND   sample_time BETWEEN &snap AND nvl(to_date(nvl(:V3,:ENDTIME),'YYMMDDHH24MISS'),sysdate+1)
        GROUP BY machine,event,ROLLUP((sql_id,top_level_sql_id))) a)
WHERE gid  = 1
AND   rnk <= 50
ORDER BY aas DESC;

var c1 refcursor "Global Network Wait Events"
var c2 refcursor "Client Network Wait Events"
DECLARE
   did INT := :dbid;
   c   SYS_REFCURSOR;
BEGIN
    OPEN :c1 FOR
    $IF &src=0 $THEN
        SELECT event,
               round(sum(time_waited_micro_fg)/sum(total_waits_fg),2) latency, 
               sum(total_waits_fg) waits,
               sum(time_waited_micro_fg) "Time",
               ratio_to_report(sum(time_waited_micro_fg)) OVER() "Time%"
        FROM   gv$system_event
        WHERE (wait_class='Network' OR wait_class!='Idle' AND event LIKE 'SQL*Net%')
        AND   total_waits_fg>0
        GROUP BY event
        ORDER BY 1;
        OPEN c FOR
            SELECT * FROM (
                SELECT s.machine,e.event,round(sum(time_waited_micro)/sum(total_waits),2) latency, 
                       sum(total_waits) waits,
                       sum(time_waited_micro) "Time",
                       ratio_to_report(sum(time_waited_micro)) OVER() "Time%"
                FROM   gv$session_event e JOIN gv$session s USING(inst_id,sid)
                WHERE (e.wait_class='Network' OR e.wait_class!='Idle' AND e.event LIKE 'SQL*Net%')
                AND   total_waits>0
                AND   upper(s.machine||','||e.event) LIKE upper('%&V1%')
                GROUP BY s.machine,e.event
                ORDER BY "Time" DESC)
            WHERE ROWNUM<=30;
    $ELSE
        SELECT event,round(sum(micro)/nullif(sum(cnt),0),2) latency,sum(cnt) waits,sum(micro) "Time",ratio_to_report(sum(micro)) OVER() "Time%"
        FROM (
            SELECT event_name event,
                   time_waited_micro_fg-lag(time_waited_micro_fg) OVER(PARTITION BY instance_number,startup_time,event_name &ver12 ORDER BY snap_id) micro,
                   total_waits_fg-lag(total_waits_fg) OVER(PARTITION BY instance_number,startup_time,event_name &ver12 ORDER BY snap_id) cnt
            FROM   dba_hist_system_event a
            JOIN   dba_hist_snapshot b
            USING  (instance_number,snap_id,dbid )
            WHERE (wait_class='Network' OR wait_class!='Idle' AND event_name LIKE 'SQL*Net%')
            AND   total_waits_fg>0
            AND   end_interval_time+0 BETWEEN &snap AND nvl(to_date(nvl('&V3','&ENDTIME'),'YYMMDDHH24MISS'),sysdate+1)
            AND   dbid=did)
        GROUP BY event 
        ORDER BY 1;
    $END
    :c2 := c;
END;
/
