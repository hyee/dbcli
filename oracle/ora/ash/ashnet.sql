/*[[
    Show network latency information. Usage: @@NAME [machine_key_word] [YYMMDDHH24MISS] [YYMMDDHH24MISS] [-dash]
    -dash: source table is Dba_Hist_Active_Sess_History instead of gv$active_session_history
    --[[
        &ash: ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
        &snap: default={NVL(to_date(nvl(:V2,:STARTTIME),'YYMMDDHH24MISS'),SYSDATE-7)} snap={sysdate-numtodsinterval(&0,'second')}
        @ver:  11={} default={--}
    --]]
]]*/

col latency,max_latency for usmhd2
col avg_bytes,max_bytes for kmg
SELECT  machine,event,aas,latency,max_latency,avg_bytes,max_bytes &ver ,top_1_sql,top_2_sql,top_3_sql
FROM (
    select a.*,row_number() over(partition by gid order by aas desc) rnk
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),1) over(partition by machine,event order by nvl2(sql_id,1,2),aas desc) top_1_sql
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),2) over(partition by machine,event order by nvl2(sql_id,1,2),aas desc) top_2_sql
        &ver ,nth_value(nvl2(sql_id,sql_id||'('||aas||')',''),3) over(partition by machine,event order by nvl2(sql_id,1,2),aas desc) top_3_sql
    from (
        select machine,event,count(1) aas,median(nvl2(event,time_waited,wait_time)) latency,median(p2) avg_bytes,
               max(nvl2(event,time_waited,wait_time)) max_latency,max(p2) max_bytes,grouping_id(sql_id) gid, nvl(sql_id,top_level_sql_id) sql_id
        from  &ash
        where p2text='#bytes' 
        and   nvl(wait_class,'Network')='Network'
        and   upper(machine) like upper('%&V1%')
        and   sample_time BETWEEN &snap AND NVL(to_date(nvl(:V3,:ENDTIME),'YYMMDDHH24MISS'),SYSDATE)
        group by machine,event,rollup((sql_id,top_level_sql_id))) a)
WHERE gid  = 1
AND   rnk <= 100
ORDER BY aas desc;
