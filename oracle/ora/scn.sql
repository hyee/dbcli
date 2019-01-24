/*[[Show SCN information or compute the time range for a specific SCN. Usage: @@NAME <inst_id>|0|<scn>
    --[[
        @check_access_obj: sys.smon_scn_time={&scn} default={}
        &his_log: {
            default={
                select a.*, null dbid
                from   gv$log_history a,(SELECT inst_id, NULLIF(VALUE, '0') val FROM gv$parameter WHERE NAME = 'thread') b
                where  a.thread# = nvl(b.val, a.thread#)
                and    a.inst_id = b.inst_id
            }
            d={(select a.*,INSTANCE_NUMBER inst_id from dba_hist_log a)}
        }
        &scn: default={select -1 grp,0 dbid,0 thread#,t1.scn_wrp * (POWER(2,32)-1) + t1.scn_bas first_scn,t1.time_dp first_time,'sys.smon_scn_time' src from sys.smon_scn_time t1 union all} d={}   
    --]]
]]*/

set feed off verify on
var c1 refcursor;
var c2 refcursor;
col DURATION for smhd2
col "SCN/Sec|(kcmgas),SCN/Sec|( Min ),SCN/Sec|( Max ),SCN/Sec|( Avg )" for k0
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
                        a.*, 
                        LEAD(first_change#) OVER(PARTITION BY a.dbid,a.inst_id,thread# ORDER BY first_time) last_change#,
                        LEAD(first_time) OVER(PARTITION BY a.dbid,a.inst_id,thread# ORDER BY first_time) next_time
                FROM   (&his_log) a),
            stat as(
                select /*+materialize*/ 
                      trunc((sysdate-(end_interval_time+0))*8) grp,
                      dbid,
                      case when inst='A' then 'A' else ''||instance_number end inst,
                      value-nvl(lag(value) over(partition by dbid,instance_number,startup_time order by snap_id),0) val,
                      86400*(end_interval_time+0-(nvl(lag(end_interval_time) over(partition by dbid,instance_number,startup_time order by snap_id),begin_interval_time)+0)) dur
                from  dba_hist_sysstat join dba_hist_snapshot using(snap_id,dbid,instance_number) 
                where stat_name ='calls to kcmgas'
                AND   instance_number=nvl(num,instance_number)
            )
            SELECT  dbid,inst,
                    MIN(first_time) begin_time,
                    MAX(next_time) end_time,
                    86400*(MAX(next_time)-MIN(first_time)) duration,
                    COUNT(1) logs,
                    MIN(FIRST_CHANGE#) first_scn,
                    MAX(LAST_CHANGE#) last_scn,
                    (select round(sum(val)/sum(dur)) from stat b where b.inst=a.inst and b.grp=a.grp and b.dbid=nvl(a.dbid,b.dbid)) "SCN/Sec|(kcmgas)",
                    MIN(scn_per_sec) "SCN/Sec|( Min )",
                    MAX(scn_per_sec) "SCN/Sec|( Max )",
                    ROUND((MAX(LAST_CHANGE#) - MIN(FIRST_CHANGE#)) / ((MAX(NEXT_TIME) - MIN(FIRST_TIME)) * 86400)) "SCN/Sec|( Avg )",
                    MAX(room) KEEP(dense_rank LAST ORDER BY first_time) "Head Room|Left days"
            FROM   (SELECT case when inst='A' then 'A' else ''||inst_id end inst,
                           TRUNC((SYSDATE - next_time) * 8) grp,
                           a.*,
                           ROUND((LAST_CHANGE# - FIRST_CHANGE#) / ((NEXT_TIME - FIRST_TIME) * 86400)) scn_per_sec,
                           round(months_between(next_time, DATE '1988-1-1') * 31 - LAST_CHANGE# / 86400 / 16 / 1024, 1) room
                    FROM   a
                    WHERE  next_time > first_time
                    AND    a.inst_id=nvl(num,inst_id)) a
            GROUP  BY dbid,grp, inst
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
                        lead(first_scn) over(partition by dbid,grp,thread# order by first_time) next_scn,
                        lead(first_time) over(partition by dbid,grp,thread# order by first_time) next_time
                    from (
                        &check_access_obj                
                        select 0 grp,dbid,thread#, first_change# first_scn,first_time,'log_history' src 
                        FROM   (&his_log)) a
                ),
                lg as(select /*+materialize*/ * from src where grp=0 and next_time>first_time),
                lg1 as(
                    select dbid,thread#,max(next_time)-min(first_time) dur,
                           max(next_scn)-min(first_scn) scns,
                           ceil(greatest(min(first_scn)-num,num-max(next_scn))/nullif(max(next_scn)-min(first_scn),0)) gaps,
                           sign(num-max(next_scn)) dir
                    from lg group by dbid,thread#
                )
                select dbid,first_time+((num-first_scn)*(next_time-first_time)/nullif(next_scn-first_scn,0)) est_time,
                       num input_scn,first_scn,next_scn,first_time,next_time,src  
                from (
                    select * from src
                    union all
                    select -2,
                           dbid,
                           thread#,
                           first_scn+scns*gaps*dir,
                           first_time+dur*gaps*dir,
                           '(estimate)' src,
                           next_scn+scns*gaps*dir,
                           next_time+dur*gaps*dir
                    from   lg join lg1 using(dbid,thread#)) 
                where num between first_scn and next_scn and rownum<2;
        end;
    end if;
    :c1 := c1;
    :c2 := c2;
end;
/
