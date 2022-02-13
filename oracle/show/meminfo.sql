/*[[Show memory usage info
--[[
    @CON: 12.1={,con_id} default={}
--]]
]]*/
col "current,min,max,define,init,Granule,last_target,last_final" for kmg1
col last_dur for smhd1
SELECT inst_id inst &con,nvl(component,'--TOTAL--') component,
       SUM(a.current_size) "Current",
       SUM(a.min_size) "Min",
       SUM(a.max_size) "Max",
       SUM(a.user_specified_size) "Define",
       SUM(b.initial_size) "Init",
       nvl2(component,MAX(a.granule_size),null) "Granule",
       '|' "|",
       SUM(a.oper_count) opers,
       MAX(nvl(b.oper_type,a.last_oper_type)) KEEP(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time)) last_type,
       MAX(nvl(b.oper_mode,a.last_oper_mode)) KEEP(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time)) last_mode,
       MAX(coalesce(b.end_time,b.start_time,a.last_oper_time)) last_time,
       MAX((b.end_time-b.start_time)*86400+1) KEEP(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time)) last_dur,
       SUM(b.target_size) last_target,
       SUM(b.final_size)  last_final,
       MAX(b.status) KEEP(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time))      last_status
FROM  GV$MEMORY_DYNAMIC_COMPONENTS a
LEFT JOIN (select b.*, row_number() over(PARTITION BY inst_id,component &con order by end_time desc) seq_ from gv$memory_resize_ops b) b
USING (inst_id,component &con)
WHERE seq_=1
AND   inst_id=nvl(:instance,userenv('instance'))
GROUP BY inst_id &con, ROLLUP(component)
ORDER BY "Current" desc