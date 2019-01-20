/*[[Show SCN information or compute the time range for a specific SCN. Usage: @@NAME <inst_id>|0|<scn>
    --[[
        @check_access_obj: sys.smon_scn_time={select -1 grp,0 thread#,t1.scn_wrp * (POWER(2,32)-1) + t1.scn_bas first_scn,t1.time_dp first_time,'sys.smon_scn_time' src from smon_scn_time t1 union all} default={}
    --]]
]]*/

set feed off verify on
var c1 refcursor;
var c2 refcursor;
col DURATION for smhd2

declare
    inst varchar2(30):=upper(coalesce(:V1,:instance,'A'));
    num  int         :=nullif(regexp_substr(inst,'\d+'),'0');
    c1   sys_refcursor;
    c2   sys_refcursor;
    tim  date;
begin
    if nvl(num,0)<=128 then
        open c1 for
            with a as(
                SELECT /*+materialize*/ 
                        a.*, LEAD(first_time) OVER(PARTITION BY a.inst_id,thread# ORDER BY sequence#) next_time
                FROM   gv$log_history a,
                        (SELECT inst_id, NULLIF(VALUE, '0') val FROM gv$parameter WHERE NAME = 'thread') b
                WHERE  a.thread# = nvl(b.val, a.thread#)
                AND    a.inst_id = b.inst_id)
            SELECT inst,
                MIN(first_time) begin_time,
                MAX(next_time) end_time,
                86400*(MAX(next_time)-MIN(first_time)) duration,
                COUNT(1) logs,
                MIN(FIRST_CHANGE#) first_scn,
                MAX(NEXT_CHANGE#) last_scn,
                MIN(scn_per_sec) "SCN/Sec|( Min )",
                MAX(scn_per_sec) "SCN/Sec|( Max )",
                ROUND((MAX(NEXT_CHANGE#) - MIN(FIRST_CHANGE#)) / ((MAX(NEXT_TIME) - MIN(FIRST_TIME)) * 86400)) "SCN/Sec|( Avg )",
                MAX(room) KEEP(dense_rank LAST ORDER BY first_time) "Head Room|Left days"
            FROM   (SELECT case when inst='A' then 'A' else ''||inst_id end inst,
                           TRUNC((SYSDATE - next_time) * 8) grp,
                           a.*,
                           ROUND((NEXT_CHANGE# - FIRST_CHANGE#) / ((NEXT_TIME - FIRST_TIME) * 86400)) scn_per_sec,
                           round(months_between(next_time, DATE '1988-1-1') * 31 - next_change# / 86400 / 16 / 1024, 1) room
                    FROM   a
                    WHERE  next_time > first_time
                    AND    a.inst_id=nvl(num,inst_id))
            GROUP  BY grp, inst
            ORDER  BY begin_time DESC, inst, end_time;

        open c2 for
            select inst_id, current_scn,CHECKPOINT_CHANGE#,CONTROLFILE_CHANGE#,ARCHIVE_CHANGE#,RESETLOGS_CHANGE# 
            from gv$database a
            where a.inst_id=nvl(num,inst_id)
            order by 1;
    else
        begin
            tim :=scn_to_timestamp(num);
            open c1 for select tim "SCN_TO_TIMSTAMP" from dual;
        exception when others then
            open c1 for
                with src as(
                    select a.*,
                        lead(first_scn) over(partition by grp,thread# order by first_scn) next_scn,
                        lead(first_time) over(partition by grp,thread# order by first_scn) next_time
                    from (
                        &check_access_obj                        
                        select 0 grp,thread#, first_change# first_scn,first_time,'v$log_history' src 
                        FROM   v$log_history
                        union  all
                        select instance_number grp,thread#, first_change# first_scn,first_time,'dba_hist_log' src  
                        FROM   dba_hist_log) a
                    union all
                    select 99 grp,thread#,first_change#,first_time,'v$archived_log',next_change#,next_time
                    from v$archived_log
                ),
                lg as(select /*+materialize*/ * from src where grp=0 and thread#=1 and next_time>first_time),
                lg1 as(
                    select max(next_time)-min(first_time) dur,
                           max(next_scn)-min(first_scn) scns,
                           ceil(greatest(min(first_scn)-num,num-max(next_scn))/nullif(max(next_scn)-min(first_scn),0)) gaps,
                           sign(num-max(next_scn)) dir
                    from lg
                )
               
                select first_time+((num-first_scn)*(next_time-first_time)/nullif(next_scn-first_scn,0)) possible_time,
                       num input_scn,first_scn,next_scn,first_time,next_time,src  
                from (
                    select * from src
                    union all
                    select -2,
                           thread#,
                           first_scn+scns*gaps*dir,
                           first_time+dur*gaps*dir,
                           '(estimate)' src,
                           next_scn+scns*gaps*dir,
                           next_time+dur*gaps*dir
                    from   lg,lg1) 
                where num between first_scn and next_scn and rownum<2;
        end;
    end if;
    :c1 := c1;
    :c2 := c2;
end;
/
