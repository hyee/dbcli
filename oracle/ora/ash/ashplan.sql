/*[[Show ash cost for a specific SQL for multiple executions. usage: @@NAME {<sql_id|plan_hash_value> [sql_exec_id] [YYMMDDHH24MI] [YYMMDDHH24MI]}  [-o] [-d|-g]
-o   : Show top object#, otherwise show top event
-d   : Only query dba_hist_active_sess_history
-g   : Only query gv$active_session_history
-all : Use hierachy clause to grab the possible missing PX slave records

--[[
    @ARGS: 1
    @adaptive : 12.1={+ADAPTIVE +REPORT} default={}
    @phf : 12.1={decode(:V1,sql_id,''||sql_full_plan_hash_value,top_level_sql_id,sql_id,''||sql_full_plan_hash_value)} default={decode(:V1,sql_id,''||sql_plan_hash_value,top_level_sql_id,sql_id,''||sql_plan_hash_value)}
    @phf2: 12.1={to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1))} default={null}
    @adp : 12.1={case when instr(other_xml, 'adaptive_plan') > 0 then 'Y' else 'N' end} default={'N'}
    @con : 12.1={AND prior nvl(con_dbid,0)=nvl(con_dbid,0)} default={}
    @mem : 12.1={DELTA_READ_MEM_BYTES} default={null}
    @did : 12.1={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
    &V9  : ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
    &top1: default={ev}, O={CURR_OBJ#}
    &top2: default={CURR_OBJ#}, O={ev}
    
    &vw  : default={A} G={G} D={D} 
    &Title: default={Objects}, O={Events}
    &titl2: default={Events}, O={Objects}
    &fmt: default={} f={} s={-rows -parallel}
    &simple: default={1} s={0}
    &V3:   default={&starttime}
    &V4:   default={&endtime}
    &q1:   default={} D={/*}
    &q2:   default={} D={*/}
    &px_count: default={} all={,(select px_count from sql_plan_px b where (b.phv=sql_plan_hash_value or b.phf=&phf) and rownum<2) px_count}
    &hierachy: {
        default={1 lv,
                decode(pred_flag,2,top_level_sql_id,sql_id) sql_id,
                sql_exec_id sql_exec_id_,
                sql_exec_start sql_exec_start_,
                nvl(sql_plan_hash_value,0) phv1,
                sql_plan_line_id,
                sql_plan_operation||' '||sql_plan_options operation,
                &phf plan_hash_full,
                pred_flag} 
           all={level lv,
                connect_by_root(decode(pred_flag,2,top_level_sql_id,sql_id)) sql_id,
                connect_by_root(sql_exec_id) sql_exec_id_,
                connect_by_root(sql_exec_start) sql_exec_start_,
                coalesce(case when pred_flag!=2 then nullif(sql_plan_hash_value,0) end,connect_by_root(sql_plan_hash_value),0) phv1,
                coalesce(case when pred_flag!=2 then nullif(case when sql_plan_line_id>65535 then 0 else sql_plan_line_id end,0) end,connect_by_root(sql_plan_line_id),0) sql_plan_line_id,
                coalesce(case when pred_flag!=2 then case when sql_plan_line_id>65535 then null else sql_plan_operation||' '||sql_plan_options end  end,connect_by_root( sql_plan_operation||' '||sql_plan_options)) operation,
                coalesce(case when pred_flag!=2 then nullif(&phf,'0')  end,connect_by_root(&phf),'0') plan_hash_full,
                connect_by_root(pred_flag) pred_flag}
    }
    &public: {default={ aas_,
                        dbid,
                        instance_number inst_id,
                        nvl(qc_instance_id,instance_number) qc_inst,
                        session_id SID,
                        nvl(qc_session_id,session_id) qc_sid,
                        qc_session_serial#,
                        current_obj#,
                        p1,
                        p2,
                        p3,
                        p1text,
                        p2text,
                        p3text,
                        event,
                        wait_class,
                        mem,
                        tm_delta_time,
                        tm_delta_db_time,
                        delta_time,
                        DELTA_READ_IO_REQUESTS,DELTA_WRITE_IO_REQUESTS,DELTA_INTERCONNECT_IO_BYTES,
                        IN_PLSQL_EXECUTION,IN_PLSQL_RPC,IN_PLSQL_COMPILATION,IN_JAVA_EXECUTION,DECODE(IS_SQLID_CURRENT,'Y','N','Y') IS_NOT_CURRENT,
                        sample_time,
                        sample_id,
                        px_flags,
                        trim(decode(bitand(time_model,power(2, 3)),0,'','connection_mgmt ') || 
                             decode(bitand(time_model,power(2, 4)),0,'','parse ') || 
                             decode(bitand(time_model,power(2, 7)),0,'','hard_parse ') || 
                             decode(bitand(time_model,power(2,15)),0,'','bind ') || 
                             decode(bitand(time_model,power(2,16)),0,'','cursor_close ') || 
                             decode(bitand(time_model,power(2,17)),0,'','sequence_load ') || 
                             decode(bitand(time_model,power(2,18)),0,'','inmemory_query ') || 
                             decode(bitand(time_model,power(2,19)),0,'','inmemory_populate ') || 
                             decode(bitand(time_model,power(2,20)),0,'','inmemory_prepopulate ') || 
                             decode(bitand(time_model,power(2,21)),0,'','inmemory_repopulate ') || 
                             decode(bitand(time_model,power(2,22)),0,'','inmemory_trepopulate ') || 
                             decode(bitand(time_model,power(2,23)),0,'','tablespace_encryption ')) time_model,
                        decode(is_sqlid_current,'Y',pga_allocated) pga_,
                        decode(is_sqlid_current,'Y',temp_space_allocated) temp_,
                        nvl(trunc(px_flags / 2097152),0) dop_}
    }

    &swcb : {
        default={
            AND     :V1 IN(sql_id,top_level_sql_id,''||sql_plan_hash_value,''||&phf)
            AND     nvl(sql_exec_id,0) = coalesce(0+:V2,sql_exec_id,0)
        }
        all={
            START  WITH :V1 IN(top_level_sql_id,sql_id,''||sql_plan_hash_value,''||&phf)
                   AND  nvl(sql_exec_id,0) = coalesce(0+:V2,sql_exec_id,0)
            CONNECT BY  PRIOR px_count>0
                   AND  NOT (session_id = qc_session_id AND instance_number = nvl(qc_instance_id, instance_number))
                   AND  PRIOR dbid = dbid
                   AND  PRIOR snap_id=snap_id
                   AND  PRIOR session_id = qc_session_id
                   AND  PRIOR instance_number = nvl(qc_instance_id, instance_number)
                   AND  PRIOR session_serial# = qc_session_serial#
                   AND  PRIOR nvl(sql_exec_id,0)=coalesce(sql_exec_id,prior sql_exec_id,0)
                   AND  PRIOR nvl(sql_id,' ') in (coalesce(sql_id,prior sql_id,' '),top_level_sql_id)
                   AND  coalesce(sql_exec_start,prior sql_exec_start,sysdate) =  nvl(prior sql_exec_start,sysdate)
                   AND  sample_time+0 between nvl(prior sql_exec_start,prior sample_time+0)-numtodsinterval(1,'minute') and (prior sample_time+0)+numtodsinterval(1,'hour')
                   &con
                   AND  LEVEL <3}
    }
    &merge: default={merge(a)} all={no_merge(a)}
--]]
]]*/
set feed off printsize 10000 pipequery off
WITH ALL_PLANS AS 
 (SELECT * FROM 
    (SELECT    id,
                parent_id,
                child_number    ha,
                1               flag,
                TIMESTAMP       tm,
                child_number,
                sql_id,
                nvl(plan_hash_value,0) phv,
                &did dbid,
                inst_id,
                object#,
                object_name,
                object_node tq,operation||' '||options operation,
                &phf2 plan_hash_full,
                instr(other_xml,'adaptive_plan') is_adaptive_
        FROM    gv$sql_plan a
        WHERE   '&vw' IN('A','G')
        AND     :V1 in(''||a.plan_hash_value,sql_id)
        UNION ALL
        SELECT  id,
                parent_id,
                plan_hash_value,
                2,
                TIMESTAMP,
                NULL child_number,
                sql_id,
                nvl(plan_hash_value,0),
                dbid,
                null,
                object#,
                object_name,
                object_node tq,operation||' '||options,
                &phf2 plan_hash_full,
                instr(other_xml,'adaptive_plan') is_adaptive_
        FROM    dba_hist_sql_plan a
        WHERE   '&vw' IN('A','D')
        AND     :V1 in(''||a.plan_hash_value,sql_id))
  WHERE dbid=nvl(0+'&dbid',&did)),
plan_objs AS
 (SELECT DISTINCT OBJECT#,OBJECT_NAME FROM ALL_PLANS),
sql_plan_data AS
 (SELECT * FROM
     (SELECT a.*,
             nvl(max(plan_hash_full) over(PARTITION by phv),phv) phf,
             nvl(max(sign(is_adaptive_)) over(partition by phv),0) is_adaptive,
             dense_rank() OVER(PARTITION BY phv ORDER BY flag, tm DESC, child_number DESC NULLS FIRST, inst_id desc,dbid,sql_id) seq
      FROM   ALL_PLANS a)
  WHERE  seq = 1),
sql_plan_px AS(
    select /*+materialize*/ phv,phf,count(case when operation like 'PX%' then 1 end) px_count
    from   sql_plan_data
    group  by phv,phf
),
sqlstats as(
    SELECT /*+materialize*/ 
            dbid,sql_id,
            nvl(plan_hash_value,-1) phv,
            SUM(executions_Delta) exec_,
            round(SUM(elapsed_time_Delta) * 1e-6, 2) ela,
            round(SUM(elapsed_time_Delta) * 1e-3 /
                    decode(SUM(executions_Delta),
                            0,
                            nullif(floor(SUM(parse_calls_delta) / greatest(1, SUM(px_servers_execs_delta))), 0),
                            SUM(executions_Delta)),
                    3) avg_
    FROM   dba_hist_sqlstat natural join dba_hist_snapshot
    WHERE  '&vw' IN('A','D')
    AND    :V1 in(''||plan_hash_value,sql_id)
    AND    elapsed_time_Delta>0
    AND    dbid=nvl(0+'&dbid',&did)
    AND    end_interval_Time+0 BETWEEN nvl(to_date(:V3,'YYMMDDHH24MISS'),SYSDATE-7)
                               AND     nvl(to_date(:V4,'YYMMDDHH24MISS'),SYSDATE)
    GROUP  BY dbid,sql_id, rollup(plan_hash_value)
),
ash_raw as (
    select h.*,
            nvl(event,'ON CPU') ev,
            nvl(trim(case 
                    when current_obj# > 0 then 
                        nvl((select max(object_name) from plan_objs where object#=current_obj#),''||current_obj#) 
                    when p3text='100*mode+namespace' and p3>power(2,32) then 
                        nvl((select max(object_name) from plan_objs where object#=trunc(p3/power(2,32))),''||trunc(p3/power(2,32))) 
                    when p3text like '%namespace' then 
                        'X$KGLST#'||trunc(mod(p3,power(2,32))/power(2,16))
                    when p1text like 'cache id' then 
                        (select parameter from v$rowcache where cache#=p1 and rownum<2)
                    when event like 'latch%' and p2text='number' then 
                        (select name from v$latchname where latch#=p2 and rownum<2)
                    when p3text='class#' then
                        (select class from (SELECT class, ROWNUM r from v$waitstat) where r=p3 and rownum<2)
                    when p1text ='file#' and p2text='block#' then 
                        'file#'||p1||' block#'||p2
                    when p3text in('block#','block') then 
                        'file#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(p3)||' block#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(p3)    
                    when px_flags > 65536 then
                        decode(trunc(mod(px_flags/65536, 32)),
                               1,'[PX]Executing-Parent-DFO',     
                               2,'[PX]Executing-Child-DFO',
                               3,'[PX]Sampling-Child-DFO',
                               4,'[PX]Joining-Group',      
                               5,'[QC]Scheduling-Child-DFO',
                               6,'[QC]Scheduling-Parent-DFO',
                               7,'[QC]Initializing-Objects', 
                               8,'[QC]Flushing-Objects',    
                               9,'[QC]Allocating-Slaves', 
                              10,'[QC]Initializing-Granules', 
                              11,'[PX]Parsing-Cursor',   
                              12,'[PX]Executing-Cursor',    
                              13,'[PX]Preparing-Transaction',    
                              14,'[PX]Joining-Transaction',  
                              15,'[PX]Load-Commit', 
                              16,'[PX]Aborting-Transaction',
                              17,'[QC]Executing-Child-DFO',
                              18,'[QC]Executing-Parent-DFO')
                    when time_model is not null then
                        '['||time_model||']'
                    when current_obj#=0 then 'Undo'
                    --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                    --when c.class is not null then c.class
                end),''||greatest(-1,current_obj#)) curr_obj#,
            nvl(wait_class,'ON CPU') wl,
            decode(sec_seq,1,aas) cost,
            nvl(nullif(plan_hash_full,'0'),''||phv1) phf,
            decode(sec_seq,1,least(coalesce(tm_delta_db_time,delta_time,AAS*1e6),coalesce(tm_delta_time,delta_time,AAS*1e6),AAS*2e6) * 1e-6) secs,
            max(case when pred_flag!=2 or is_px_slave=1 then dop_ end)  over(partition by dbid,phv1,sql_exec,pid) dop,
            sum(case when p3text='block cnt' and nvl(event,'temp') like '%temp' then temp_ end) over(partition by dbid,phv1,sql_exec,pid,sample_time+0) temp,
            sum(pga_)  over(partition by dbid,phv1,sql_exec,pid,sample_time+0) pga,
            sum(case when is_px_slave=1 and px_flags>65536 then least(tm_delta_db_time,AAS*2e6) end) over(partition by px_flags,dbid,phv1,sql_exec,pid,qc_sid,qc_inst,qc_session_serial#,sid,inst_id) dbtime
    FROM   (SELECT /*+NO_BIND_AWARE NO_PQ_CONCURRENT_UNION no_expand opt_param('optimizer_index_cost_adj' 500) opt_param('_optim_peek_user_binds' 'false') opt_param('_optimizer_connect_by_combine_sw', 'false') opt_param('_optimizer_filter_pushdown', 'false')*/ --PQ_CONCURRENT_UNION 
                   a.*, --seq: if ASH and DASH have the same record, then use ASH as the standard
                   decode(AAS_,1,1,decode((
                        select sign(max(avg_) keep(dense_rank last order by phv1)- 5e3) flag 
                        from   sqlstats b 
                        where  a.dbid=b.dbid 
                        and    a.sql_id=b.sql_id 
                        and    b.phv in(a.phv1,-1)
                    ),1,10,1)) AAS,
                   row_number() OVER(PARTITION BY dbid,sample_id,inst_id,sid ORDER BY AAS_,lv desc) seq,
                   --sec_seq: multiple PX processes at the same second wille be treated as on second 
                   row_number() OVER(PARTITION BY dbid,phv1,sql_plan_line_id,operation,sample_time+0,qc_inst,qc_sid ORDER BY AAS_,lv desc,tm_delta_db_time desc) sec_seq,
                   nvl(decode(pred_flag,2,0,case when sql_plan_line_id>65535 then 0 else sql_plan_line_id end),0) pid,
                   nvl(''||sql_exec_id_,'@'||qc_inst||','||qc_sid||','||qc_session_serial#)||','||to_char(sql_exec_start_,'yyyymmddhh24miss') sql_exec,
                   case when (qc_sid!=sid or qc_inst!=inst_id) then 1 else 0 end is_px_slave,
                   CASE WHEN 'Y' IN(decode(pred_flag,2,'Y','N'),IS_NOT_CURRENT,IN_PLSQL_EXECUTION,IN_PLSQL_RPC,IN_PLSQL_COMPILATION,IN_JAVA_EXECUTION) THEN 1 END IN_PLSQL       
            FROM   (
                &q1
                SELECT  --+ QB_NAME(ASH)  CONNECT_BY_FILTERING ORDERED
                        &public,
                        &hierachy
                FROM    (
                    select --+merge(a) cardinality(30000000) full(a.a) leading(a.a) use_hash(a.a a.s) swap_join_inputs(a.s) FULL(A.GV$ACTIVE_SESSION_HISTORY.A)  leading(A.GV$ACTIVE_SESSION_HISTORY.A) use_hash(A.GV$ACTIVE_SESSION_HISTORY.A A.GV$ACTIVE_SESSION_HISTORY.S) swap_join_inputs(A.GV$ACTIVE_SESSION_HISTORY.S)
                            a.*,&did dbid,inst_id instance_number,1 aas_,&mem mem,0 snap_id &px_count,decode(:V1,sql_id,1,top_level_sql_id,2,3) pred_flag
                    from   gv$active_session_history a
                    where  '&vw' IN('A','G')
                    and    sample_time+0 BETWEEN nvl(to_date(:V3,'YYMMDDHH24MISS'),SYSDATE-7) 
                                         AND     nvl(to_date(:V4,'YYMMDDHH24MISS'),SYSDATE)
                    and   (:V1 IN(sql_id,top_level_sql_id,''||sql_plan_hash_value,''||&phf) or 
                            qc_session_id!=session_id or qc_instance_id!=inst_id or session_serial# != qc_session_serial#                            
                           )) a
                where  dbid=nvl('&dbid',dbid)
                &swcb
                UNION ALL
                &q2
                SELECT  /*+QB_NAME(DASH) CONNECT_BY_FILTERING ORDERED PX_JOIN_FILTER(a)*/
                        &public,
                        &hierachy
                FROM    (select /*+MERGE(D)
                                   cardinality(30000000)
                                   FULL(D.ASH) FULL(D.EVT) swap_join_inputs(D.EVT) OPT_ESTIMATE(TABLE D.ASH ROWS=30000000)
                                   full(D.DBA_HIST_ACTIVE_SESS_HISTORY.ASH) OPT_ESTIMATE(TABLE D.DBA_HIST_ACTIVE_SESS_HISTORY.ASH ROWS=30000000)
                                   swap_join_inputs(D.DBA_HIST_ACTIVE_SESS_HISTORY.EVT) full(D.DBA_HIST_ACTIVE_SESS_HISTORY.EVT)
                                */ 
                                d.*, 10 aas_,null mem &px_count,decode(:V1,sql_id,1,top_level_sql_id,2,3) pred_flag
                         from   dba_hist_active_sess_history d
                         WHERE   '&vw' IN('A','D')
                         AND     dbid=nvl(0+'&dbid',&did)
                         AND     sample_time BETWEEN nvl(to_date(:V3,'YYMMDDHH24MISS'),SYSDATE-7) 
                                                   AND nvl(to_date(:V4,'YYMMDDHH24MISS'),SYSDATE)) a
                WHERE 1=1
                &swcb
                ) a ) h
    WHERE  seq = 1),
ash_phv_agg as(
    SELECT  /*+materialize*/ a.* 
    from (
        select  phv phv1,
                is_adaptive,
                nvl(b.phf,a.phf) phfv,
                100*sum(cost) over(partition by nvl(b.phf,a.phf))/sum(cost) over() phf_rate,
                100*ratio_to_report(cost) over() phv_rate,
                first_value(phv) OVER(PARTITION BY nvl(b.phf,a.phf) ORDER BY nvl2(b.phf,0,1),cost desc,aas DESC) phv,
                listagg(phv,',') WITHIN GROUP(ORDER BY cost desc,aas DESC) OVER(PARTITION BY nvl(b.phf,a.phf)) phvs,
                count(1) over(partition by  nvl(b.phf,a.phf)) phv_cnt,
                max(nvl2(b.phf,1,0)) over(partition by  nvl(b.phf,a.phf)) plan_exists
        from (SELECT phv1 phv,max(phf) phf,sum(cost) cost,sum(aas) aas from ash_raw group by phv1) a 
        left join (select distinct phv,phf,is_adaptive from sql_plan_data) b using(phv)) A
    WHERE phv_rate>=0.1),
hierarchy_data AS
 (SELECT id, parent_id, phv,operation
  FROM   (select * from sql_plan_data where phv in(select phv from ash_phv_agg where plan_exists=1))
  START  WITH id = 0
  CONNECT BY PRIOR id = parent_id AND phv=PRIOR phv 
  ORDER  SIBLINGS BY id DESC),
ordered_hierarchy_data AS
 (SELECT id,
         parent_id AS pid,
         phv AS phv,
         operation,
         row_number() over(PARTITION BY phv ORDER BY rownum DESC) AS OID,
         MAX(id) over(PARTITION BY phv) AS maxid
  FROM   hierarchy_data),
qry AS
 ( SELECT DISTINCT sql_id sq,
         flag flag,
         'ADVANCED IOSTATS METRICS -PEEKED_BINDS -cost -bytes -alias -OUTLINE -projection &adaptive &fmt' format,
         phv phv,
         coalesce(child_number, 0) child_number,
         inst_id,
         dbid
  FROM   sql_plan_data
  WHERE  phv in(select phv from ash_phv_agg where plan_exists=1)),
xplan AS
 (  SELECT phv,rownum r,a.*
    FROM   qry, TABLE(dbms_xplan.display('dba_hist_sql_plan',NULL,format,'dbid='||dbid||' and plan_hash_value=' || phv || ' and sql_id=''' || sq ||'''')) a
    WHERE  flag = 2
    UNION ALL
    SELECT phv,rownum,a.*
    FROM   qry,
            TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'inst_id='|| inst_id||' and plan_hash_value=' || phv || ' and sql_id=''' || sq ||''' and child_number='||child_number)) a
    WHERE  flag = 1),
ash_agg as(
    SELECT /*+materialize parallel(4)*/ 
           a.*, 
           nvl2(costs,trim(dbms_xplan.format_number(costs))||'('||to_char(ratio,case when ratio=10 then '990' else 'fm990.0' end)||'%)','') cost_rate,
           trim(dbms_xplan.format_number(costs)) cost_text,
           trim(dbms_xplan.format_number(aas)) aas_text,
           trim(dbms_xplan.format_number(io_reqs_/execs)) io_reqs,
           trim(dbms_xplan.format_size(io_bytes_/execs)) io_bytes,
           trim(dbms_xplan.format_size(buf_/execs)) buf,
           trim(dbms_xplan.format_size(pga_)) pga,
           trim(dbms_xplan.format_size(temp_)) temp,
           decode(nvl(secs_,0),0,' ',regexp_replace(trim(dbms_xplan.format_time_s(secs_)),'^00:')) secs
    FROM (
        SELECT A.*, first_value('['||lpad(round(100*AAS/aas1,1),4)||'%] '||grp) 
                   OVER(PARTITION BY phv,subtype,sub ORDER BY decode(grp,'-1',1,null,2,0),aas DESC,decode(grp,'ON CPU','Z',grp)) top_grp, 
               listagg(CASE WHEN seq<=5 AND sub IS NOT NULL THEN sub||'('||round(100*AAS/aas0,1)||'%)' END,' / ') 
                   WITHIN GROUP(ORDER BY seq) OVER(PARTITION BY phv,grp,subtype)  top_list,
               round(100*ratio_to_report(costs) over(partition by decode(g,8,null,phv),gid,g,subtype),1) ratio,
               decode(g,8,phv_rate,round(100*ratio_to_report(aas) over(partition by phv,gid,g,subtype),1)) aas_rate
        FROM (
            SELECT A.*,
                max(aas) over(partition by phv,grp) aas0,
                MAX(aas) OVER(PARTITION BY phv,sub,subtype) aas1,
                row_number() OVER(PARTITION BY phv,gid,grp,subtype order by aas desc,sub) seq
            FROM(
                select --+NO_EXPAND_GSET_TO_UNION NO_USE_DAGG_UNION_ALL_GSETS
                    grouping_id(phv1,id,top2) gid,
                    CASE
                        WHEN grouping_id(phv1,top1) =1 THEN 8
                        WHEN grouping_id(id,top1) =1 THEN 4
                        WHEN grouping_id(top1,id) =1 THEN 2   
                        WHEN grouping_id(top1,top2) =1 THEN 1
                    END g,
                    grouping_id(phv1,top1) g1,
                    grouping_id(id,top1) g2,
                    grouping_id(top1,top2) g3,
                    decode(grouping_id(phv1, id,top2),3,sql_id||','||phv1,5,top1,top1) grp,
                    decode(grouping_id(phv1, id,top2),3,top1,5,''||id,top2) sub,
                    DECODE(grouping_id(phv1, id,top2),3,'E',5,'P','O') subtype,
                    phv,phv1,phvs,phfv,plan_exists, top1, top2,id,sql_id,
                    max(phf_rate) phf_rate,max(phv_rate) phv_rate,max(pred_flag) pred_flag,
                    max(dop) max_dop,min(nullif(dop,0)) min_dop,decode(sign(max(dop)),1,max(skew)) skew,
                    COUNT(DISTINCT SQL_EXEC) EXECS,
                    SUM(secs) secs_,
                    SUM(AAS) AAS,
                    sum(cost) costs,
                    round(SUM(DECODE(wl, 'ON CPU', AAS, 0))*100/ SUM(AAS), 1) "CPU",
                    round(SUM(CASE WHEN wl IN ('User I/O','System I/O') THEN AAS ELSE 0 END) * 100 / SUM(AAS), 1) "IO",
                    round(SUM(DECODE(wl, 'Cluster', AAS, 0)) * 100 / SUM(AAS), 1) "CL",
                    round(SUM(DECODE(wl, 'Concurrency', AAS, 0)) * 100 / SUM(AAS), 1) "CC",
                    round(SUM(DECODE(wl, 'Appidcation', AAS, 0)) * 100 / SUM(AAS), 1) "APP",
                    round(SUM(DECODE(wl, 'Scheduler', AAS, 0)) * 100 / SUM(AAS), 1) "SCH",
                    round(SUM(DECODE(wl, 'Administrative', AAS, 0)) * 100 / SUM(AAS), 1) "ADM",
                    round(SUM(DECODE(wl, 'Configuration', AAS, 0)) * 100 / SUM(AAS), 1) "CFG",
                    round(SUM(DECODE(wl, 'Network', AAS, 0)) * 100 / SUM(AAS), 1) "NET",
                    round(SUM(CASE WHEN wl IN ('Idle','Commit','Other','Queueing') THEN AAS ELSE 0 END) * 100 / SUM(AAS), 1) oth,
                    round(SUM(IN_PLSQL*AAS)* 100 / SUM(AAS), 1) PLSQL,
                    SUM(DELTA_READ_IO_REQUESTS+DELTA_WRITE_IO_REQUESTS) io_reqs_,
                    SUM(DELTA_INTERCONNECT_IO_BYTES) io_bytes_,
                    SUM(mem) buf_,
                    max(pga) pga_,
                    max(temp) temp_,
                    min(sample_time) begin_time,
                    max(sample_time) end_time
                from (select a.*, nvl(''||&top1,' ') top1,nvl(''||&top2,' ') top2,
                            decode(is_adaptive,1,nvl((select min(id) from ordered_hierarchy_data b where a.phv=b.phv and b.id>=a.pid and a.operation=b.operation),a.pid),a.pid) id,
                            nullif(round(100*stddev(dbtime) over(partition by px_flags,dbid,phv1,sql_exec,pid,qc_sid,qc_inst,qc_session_serial#)
                                    /greatest(avg(dbtime) over(partition by px_flags,dbid,phv1,sql_exec,pid,qc_sid,qc_inst,qc_session_serial#),5e6),2),0) skew
                    FROM (select /*+ordered use_hash(b)*/ * from ash_phv_agg a natural join ash_raw b) A
                    )
                group by phv,phvs,phvs,phfv,plan_exists,grouping sets((phv1,sql_id),(phv1,sql_id,top1),id,(id,top1),top1,(top1,top2))) A) A
    ) a WHERE g IS NOT NULL
),
plan_agg as(
    SELECT decode(plan_exists,1,'*',' ')||phv1 phv2,
           row_number() over(order by phf_rate desc,costs desc,aas desc) r,
           row_number() over(partition by phv1 order by phf_rate desc,costs desc,aas desc) r1,
           trim(dbms_xplan.format_number(b.exec_)) awr_exec,
           case 
                when nvl(b.avg_,0) <= 0 then null
                when b.avg_<  1   then b.avg_*1e3||'us'
                when b.avg_<1e3   then round(b.avg_,1)||'ms'
                when b.avg_<180e3 then round(b.avg_/1e3,2)||'s'
                when b.avg_<6e6   then round(b.avg_/1e3/60,2)||'m'
                else round(b.avg_/1e3/3600,2)||'h'
           end awr_ela,
           a.* 
    FROM   ash_agg a left join sqlstats b on(a.sql_id=b.sql_id and a.phv1=b.phv) 
    WHERE  g=8
),
plan_wait_agg as(
    select rownum r,a.* 
    from (
        SELECT * FROM ash_agg NATURAL JOIN (SELECT phv,top1,replace(top_list,' / ',', ') top_lines FROM ash_agg WHERE SUBTYPE='P' AND seq=1) 
        WHERE GID=7 AND G=2 AND plan_exists=1
        ORDER BY phv,nvl(ratio,aas_rate) DESC,aas desc,top1) a
),
plan_line_agg AS(
    SELECT /*+materialize no_expand no_merge(a) no_merge(b)*/*
    FROM   ordered_hierarchy_data a
    LEFT   JOIN (select a.* from ash_agg a where g=4 and plan_exists=1) b
    USING(phv,id)),
plan_line_xplan AS
 (SELECT /*+no_merge(x) use_hash(x o)*/
       r,
       x.phv phv,
       x.plan_table_output AS plan_output,
       x.id,x.prefix,
       nvl(''||o.pid,' ') pid,nvl(''||o.oid,' ') oid,o.maxid,
       cpu,io,cc,cl,app,oth,adm,cfg,sch,net,plsql,cost_text,aas_text,execs,
       nvl(cost_rate,' ') cost_rate,
       secs,o.min_dop,o.max_dop,o.skew,o.buf,o.io_reqs,o.io_bytes,o.pga,o.temp,
       nvl(top_grp,' ') top_grp,
       '| Plan Hash Value(Full): '||max(phfv) over(partition by x.phv)
       ||decode(min(min_dop) over(partition by x.phv),
               null,'',
               max(max_dop) over(partition by x.phv),'    DoP: '||max(max_dop) over(partition by x.phv),
               '    DoP: '||min(min_dop) over(partition by x.phv)||'-'||max(max_dop) over(partition by x.phv))
       ||'    Period: ['||to_char(min(begin_time) over(partition by x.phv),'yyyy/mm/dd hh24:mi:ss') ||' -- '
            ||to_char(min(end_time) over(partition by x.phv),'yyyy/mm/dd hh24:mi:ss')||']' time_range,
       '| Plan Hash Value(s)   : '||max(phvs) over(partition by x.phv) phvs
  FROM  (SELECT x.*,
                nvl(regexp_substr(prefix,'\d+')+0,least(-1,r-MIN(nvl2(regexp_substr(prefix,'\d+'),r,NULL)) OVER(PARTITION BY phv))) ID
         FROM   (select x.*,regexp_substr(x.plan_table_output, '^\|[-\* ]*([0-9]+|Id) +\|') prefix from xplan x) x) x
  LEFT OUTER JOIN plan_line_agg o
  ON   x.phv = o.phv AND x.id = o.id),
agg_data as(
  select 'line' flag,phv,r,id,''||oid oid,'' full_hash,
         ''||secs secs,''||cost_rate cost_rate,aas_text aas,cost_text costs,''||execs execs,decode(min_dop,null,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,skew,
         ''||cpu cpu,''||io io,''||cl cl,''||cc cc,''||app app,''||adm adm,''||cfg cfg,''||sch sch,''||net net,''||oth oth,''||plsql  plsql,buf,io_reqs ioreqs,io_bytes iobytes,pga,temp,
         decode(&simple,1,top_grp) top_list,'' top_list2,null pred_flag,null awr_exec,null awr_ela
  FROM plan_line_xplan
  UNION ALL
  select 'phv' flag,-1,r,rid,''||phv2 oid,decode(pred_flag,3,sql_id,''||phfv),
         ''||secs secs,''|| cost_rate,aas_text aas,cost_text costs,''||execs execs,decode(min_dop,null,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,skew,
         ''||cpu cpu,''||io io,''||cl cl,''||cc cc,''||app app,''||adm adm,''||cfg cfg,''||sch sch,''||net net,''||oth oth,''||plsql  plsql,buf,io_reqs,io_bytes,pga,temp,
         ''||top_list,'',pred_flag,awr_exec,awr_ela
  FROM  plan_agg a,(select rownum-3 rid from dual connect by rownum<=3)
  UNION ALL
  select 'wait' flag,phv,r,rid,''||top1 oid,'' phfv,
         ''||secs secs,''|| cost_rate,aas_text aas,cost_text costs,''||execs execs,decode(min_dop,null,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,skew,
         '' cpu,'' io,'' cl,'' cc,'' app,'' adm,'' cfg,'' sch,'' net,'' oth,''  plsql,buf,io_reqs,io_bytes,pga,temp,
         ''||top_list,''||top_lines,null pred_flag,null awr_exec,null awr_ela
  FROM  plan_wait_agg a,(select rownum-3 rid from dual connect by rownum<=3)
),

plan_line_widths AS(
    SELECT a.*,swait+swait2+sdop + sskew + csize + rate_size + ssec + sexe + saas + scpu + sio + scl + scc + sapp + ssch +scfg + sadm + snet + soth + splsql + sbuf + sioreqs + siobytes +spga +stemp+sawrela+sawrela + 6 widths
    FROM( 
       SELECT  flag,phv,
               nvl(greatest(max(length(oid)) + 1, 6),0) as csize,
               nvl(greatest(max(length(trim(nullif(full_hash,oid)))), 11),0) as shash,
               nvl(greatest(max(length(trim(secs)))+1, 8),0)*&simple as ssec,
               nvl(greatest(max(length(trim(cost_rate))) + 1, 7),0) as rate_size,
               nvl(greatest(max(length(nullif(aas,costs)))+1,7),0) as saas,
               nvl(greatest(max(length(nullif(execs,'0'))) + 1, 5),0) as sexe,
               nvl(greatest(max(length(nullif(dop,'0'))) + 2, 5),0) as sdop,
               nvl(greatest(max(length(nullif(skew,0))) + 2, 6),0) as sskew,
               nvl(greatest(max(length(nullif(CPU,'0'))) + 1, 5),0) as scpu,
               nvl(greatest(max(length(nullif(io,'0'))) + 1, 5),0) as sio,
               nvl(greatest(max(length(nullif(cl,'0'))) + 1, 5),0) as scl,
               nvl(greatest(max(length(nullif(cc,'0'))) + 1, 5),0) as scc,
               nvl(greatest(max(length(nullif(app,'0'))) + 1, 5),0) as sapp,
               nvl(greatest(max(length(nullif(adm,'0'))) + 1, 5),0) as sadm,
               nvl(greatest(max(length(nullif(cfg,'0'))) + 1, 5),0) as scfg,
               nvl(greatest(max(length(nullif(sch,'0'))) + 1, 5),0) as ssch,
               nvl(greatest(max(length(nullif(net,'0'))) + 1, 5),0) as snet,
               nvl(greatest(max(length(nullif(oth,'0'))) + 1, 5),0) as soth,
               nvl(greatest(max(length(nullif(plsql,'0'))) + 2, 6),0) as splsql,
               nvl(greatest(max(length(nullif(buf,'0'))) + 1, 7),0)*&simple as sbuf,
               nvl(greatest(max(length(nullif(ioreqs,'0'))) + 1, 8),0)*&simple as sioreqs,
               nvl(greatest(max(length(nullif(iobytes,'0'))) + 1, 9),0)*&simple as siobytes,
               nvl(greatest(max(length(nullif(pga,'0'))) + 1, 5),0)*&simple as spga,
               nvl(greatest(max(length(nullif(temp,'0'))) + 2, 6),0)*&simple as stemp,
               nvl(greatest(max(length(trim(top_list))) + 2, 10),0) as swait,
               nvl(greatest(max(length(trim(top_list2))) + 2, 10),0) as swait2,
               nvl(greatest(max(length(nullif(awr_exec,'0'))) + 1, 8),0) as sawrexec,
               nvl(greatest(max(length(nullif(awr_ela,'0'))) + 1, 8),0) as sawrela
         FROM  agg_data
         GROUP BY flag,phv) a),
format_info as (
    SELECT flag,phv,r,widths,id,
       decode(id,
            -2,decode(flag,'line',lpad('Ord', csize),'phv','|'||lpad('Plan Hash ',csize),'|'||rpad('&titl2',csize)) || lpad(decode(pred_flag,3,'SQL Id     ','Full Hash'), shash) || ' |'
                ||decode(sawrexec+sawrela,0,'',lpad('AWR-Exes',sawrexec)||lpad('Avg-Ela',sawrela)||'|')
                ||lpad('DoP  ', sdop)|| lpad('Skew  ', sskew)|| lpad('Execs', sexe) || lpad('Secs', rate_size) || lpad('AAS', saas) || lpad('DB-Time', ssec) 
                ||nullif('|'||lpad('CPU%', scpu)  || lpad('IO%', sio) || lpad('CL%', scl) || lpad('CC%', scc) || lpad('APP%', sapp)
                            ||lpad('Sch%', ssch)  || lpad('Cfg%', scfg) || lpad('Adm%', sadm)|| lpad('Net%', snet)
                            ||lpad('OTH%', soth)  || lpad('PLSQL', splsql),'|')
                ||nullif('|'||lpad('Buffer',sbuf)||lpad('IO-Reqs',sioreqs)||lpad('IO-Bytes',siobytes)||lpad('PGA',spga)||lpad(' Temp',stemp),'|')
                ||nullif('|'||rpad(' Top Lines', swait2),'|') || nullif('|'||rpad(' Top '||decode(flag,'wait','&Title','&titl2'), swait),'|')||'|',
            -1, '+'||lpad('-',csize+shash+1,'-')||'+'
                ||decode(sawrexec+sawrela,0,'',lpad('-',sawrexec+sawrela,'-')||'+')
                ||lpad('-',sdop+sskew+sexe+rate_size+saas+ssec,'-')
                ||nullif('+'||lpad('-',scpu+sio+scl+scc+sapp+ssch+scfg+sadm+snet+soth+splsql,'-'),'+')
                ||nullif('+'||lpad('-',sbuf+sioreqs+siobytes+spga+stemp,'-'),'+')
                ||nullif('+'||rpad('-', swait2,'-'),'+') ||nullif('+'||lpad('-',swait,'-'),'+')||'+', 
           decode(flag,'line',lpad(oid, csize),'|'||rpad(oid,csize)) || lpad(nvl(full_hash,' '), shash) || ' |'
                ||decode(sawrexec+sawrela,0,'',lpad(nvl(awr_exec,' '),sawrexec)||lpad(nvl(awr_ela,' '),sawrela)||'|')
                ||lpad(dop||'  ', sdop)||lpad(skew||nvl2(nullif(skew,0),'%','')||' ', sskew)||lpad(nvl(execs,' '), sexe) || lpad(nvl(cost_rate,' '), rate_size) || lpad(nvl(aas,' '), saas) || lpad(nvl(secs,' '), ssec) 
                ||nullif('|'||lpad(nvl(CPU,' '), scpu) || lpad(nvl(io,' '), sio) || lpad(nvl(cl,' '), scl) || lpad(nvl(cc,' '), scc) || lpad(nvl(app,' '), sapp)
                            ||lpad(nvl(sch,' '), ssch) || lpad(nvl(cfg,' '), scfg) || lpad(nvl(adm,' '), sadm)|| lpad(nvl(net,' '), snet)
                            ||lpad(nvl(oth,' '), soth)  || lpad(nvl(plsql,' '), splsql),'|')
                ||nullif('|'||lpad(buf||' ',sbuf)||lpad(ioreqs||' ',sioreqs)||lpad(iobytes||' ',siobytes)||lpad(nvl(pga,' '),spga)||lpad(nvl(temp,' '),stemp),'|')
                ||nullif('|'||rpad(' '||top_list2, swait2),'|')||nullif('|'||rpad(' ' || top_list, swait),'|')||'|'
            ) fmt
    FROM   plan_line_widths JOIN agg_data USING (flag,phv)
),

plan_output AS (
    SELECT /*+ordered use_hash(b)*/
           phv,
           r,
           b.ID,
           prefix,
           prefix || 
           CASE
               WHEN plan_output LIKE '---------%' THEN
                   rpad('-', widths, '-')
               WHEN b.id = -2 OR b.id > -1 THEN
                   fmt
               WHEN b.id = -4 THEN
                   phvs
               WHEN b.id = -5 THEN
                   time_range
           END || CASE WHEN b.id not in(-4,-5) THEN substr(plan_output, nvl(LENGTH(prefix), 0) + 1) END plan_line
    FROM   (select * from format_info where flag='line') a
    JOIN   plan_line_xplan b USING  (phv,r)
    WHERE  b.id>=-5 and (b.id!=-1 or b.id=-1 and trim(plan_output) is not null)
    ORDER  BY phv, r),
titles as(select distinct phv,fmt,id,flag from format_info where id<0),
final_output as(
    SELECT 0 id,-1 phv,fmt,0 r,0 seq from titles where id=-1 and flag='phv'
    union all
    SELECT 1,-1,fmt,0,0 from titles where id=-2 and flag='phv'
    union all
    SELECT 2,-1,fmt,0,0 from titles where id=-1 and flag='phv'
    UNION ALL
    SELECT 3,-1,fmt,r,0 seq from format_info WHERE flag='phv' and id=0
    UNION ALL
    SELECT 4,-1,fmt,0,0 from titles where id=-1 and flag='phv'
    UNION ALL
    SELECT 5,b.phv,b.plan_output,r,seq
    FROM   (select r,phv1 phv from plan_agg where r1=1) a,
        (SELECT /*+NO_PQ_CONCURRENT_UNION*/ b.*,r_*1e8+seq_ seq 
            FROM (
                SELECT 1 r_,rownum seq_,phv,null plan_output from (select distinct phv FROM plan_output)
                UNION ALL
                SELECT 2,rownum seq,phv,plan_output from (select phv,rpad('=',max(length(rtrim(plan_line))),'=') plan_output FROM plan_output group by phv)
                UNION ALL
                SELECT 3,r seq,phv,rtrim(plan_line) FROM plan_output
                UNION ALL
                SELECT 4,rownum seq,phv,fmt from titles where id=-1 and flag='wait'
                union all
                SELECT 5,rownum seq,phv,fmt from titles where id=-2 and flag='wait'
                union all
                SELECT 6,rownum seq,phv,fmt from titles where id=-1 and flag='wait'
                UNION ALL
                SELECT 7,r,phv,fmt FROM format_info WHERE flag='wait' and id=0
                UNION ALL
                SELECT 8,rownum seq,phv,fmt from titles where id=-1 and flag='wait'
            ) b) b
    WHERE a.phv=b.phv)
select fmt ASH_PLAN_OUTPUT from final_output order by id,r,seq;