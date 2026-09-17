/*[[Show memory usage info
--[[
    @CON: 12.1={,con_id} default={}
--]]
]]*/
col "current,min,max,define,init,Granule,last_target,last_final" for kmg1
col last_dur for smhd1
SELECT inst_id inst &con,nvl(component,'--TOTAL--') component,
       sum(a.current_size) "Current",
       sum(a.min_size) "Min",
       sum(a.max_size) "Max",
       sum(a.user_specified_size) "Define",
       sum(b.initial_size) "Init",
       nvl2(component,max(a.granule_size),null) "Granule",
       '|' "|",
       sum(a.oper_count) opers,
       max(nvl(b.oper_type,a.last_oper_type)) keep(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time)) last_type,
       max(nvl(b.oper_mode,a.last_oper_mode)) keep(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time)) last_mode,
       max(coalesce(b.end_time,b.start_time,a.last_oper_time)) last_time,
       max((b.end_time-b.start_time)*86400) keep(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time)) last_dur,
       sum(b.target_size) last_target,
       sum(b.final_size)  last_final,
       max(b.status) keep(dense_rank last order by coalesce(b.end_time,b.start_time,a.last_oper_time))      last_status
FROM   gv$memory_dynamic_components a
LEFT   JOIN (SELECT b.*, row_number() over(PARTITION BY inst_id,component &con ORDER BY end_time DESC) seq_ FROM gv$memory_resize_ops b) b
USING  (inst_id,component &con)
WHERE  seq_=1
AND    inst_id=nvl(:instance,userenv('instance'))
GROUP  BY inst_id &con, rollup(component)
ORDER  BY "Current" DESC