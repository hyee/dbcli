/*[[
    Show network latency information. Usage: @@NAME [machine_key_word] [YYMMDDHH24MISS] [YYMMDDHH24MISS] [-dash]
    --[[
        &ash: ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
        &snap: default={NVL(to_date(nvl(:V2,:STARTTIME),'YYMMDDHH24MISS'),SYSDATE-7)} snap={sysdate-numtodsinterval(&0,'second')}
    --]]
]]*/

col latency for usmhd2
col bytes for kmg
select machine,event,count(1) aas,median(time_waited) latency,median(p2) bytes
from  &ash
where p2text='#bytes' and wait_class='Network'
and   upper(machine) like upper('%&V1%')
and   time_waited>0
and   sample_time BETWEEN &snap
                      AND NVL(to_date(nvl(:V3,:ENDTIME),'YYMMDDHH24MISS'),SYSDATE)
group by machine,event
order by sum(time_waited) desc;
