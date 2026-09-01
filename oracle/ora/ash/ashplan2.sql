/*[[
       Show ash cost for a specific SQL for multiple executions. usage: @@NAME {<sql_id> [plan_hash_value|sid|a] [YYMMDDHH24MI] [YYMMDDHH24MI]} [-dash|-t"<ash_dump_table>"] [-o] -f"<format>"
       -o      : Show top object#, otherwise show top event
       -dash   : Based on dba_hist_active_sess_history, otherwise based on gv$active_session_history
       -sqlset : Use dba_hist_active_sess_history + dba_sqlset_plans as the data source
       -t      : Based on the table that stores the ASH data, instead of using gv$active_session_history. i.e.: -t"ash_dump"

       The output is similar to 'ora ashplan', but less accurate and faster
       --[[
       @ARGS: 1
       @adaptive : 12.1={adaptive} 11.1={}
       @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_}
       &ash : {
          ash={(select * from table(gv$(cursor(select userenv('instance') inst_id,a.* from v$active_session_history a where userenv('instance')=nvl(:instance,userenv('instance')) and '&V1' in(sql_id,top_level_sql_id)))))}, 
          dash={&check_access_pdb.Active_Sess_History},
          sqlset={&check_access_pdb.Active_Sess_History} ,
          t={&0}
       }
       &dplan: default={&check_access_pdb.sql_plan} sqlset={(select a.*,0+null object# from dba_sqlset_plans a)}
       &src1 : default={&check_access_pdb.sql_plan} sqlset={dba_sqlset_plans}
       &cid  : default={dbid} sqlset={con_dbid}
       &unit: default={1} ash={1}, dash={10}
       &OBJ : default={ev}, O={CURR_OBJ#}
       &OBJ1: default={CURR_OBJ#}, O={ev}
       &Title: default={Event}, O={Obj#}
       &fmt: default={} f={} s={-rows -parallel}
       &simple: default={1} s={0}
       &V3: default={&starttime}
       &V4: default={&endtime}
       --]]
]]*/
set feed off printsize 3000 pipequery off

WITH sql_plan_data AS
 (SELECT /*+materialize opt_param('optimizer_dynamic_sampling' 11)*/ *
  FROM   (SELECT a.*,
                 dense_rank() OVER(ORDER BY flag, tm DESC, child_number DESC, plan_hash_value DESC,inst_id DESC) seq
          FROM   (SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/ *
                  FROM TABLE(gv$(CURSOR(
                      SELECT id,position pos,
                             decode(parent_id,-1,id-1,parent_id) parent_id,
                             child_number    ha,
                             1               flag,
                             TIMESTAMP       tm,
                             child_number,
                             sql_id,
                             nvl(plan_hash_value,0) plan_hash_value,
                             userenv('instance') inst_id,
                             object#,object_name
                      FROM   v$sql_plan_statistics_all a
                      WHERE  userenv('instance')=nvl(:instance,userenv('instance'))
                      AND    a.sql_id = '&V1'
                      AND    a.plan_hash_value = CASE WHEN nvl(lengthb('&V2'),0) >6 THEN '&V2'+0 ELSE plan_hash_value END)))
                  UNION ALL
                  SELECT id,position pos,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         plan_hash_value,
                         2,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         nvl(plan_hash_value,0) plan_hash_value,
                         &cid dbid,
                         object#,object_name
                  FROM   &dplan a
                  WHERE  a.sql_id = '&V1'
                  AND    a.plan_hash_value = CASE WHEN nvl(lengthb('&V2'),0) >6 THEN '&V2'+0 ELSE plan_hash_value END
                  ) a)
  WHERE  seq = 1),
hierarchy_data AS
 (SELECT /*+opt_param('_connect_by_use_union_all','old_plan_mode')*/ id, parent_id, plan_hash_value
  FROM   sql_plan_data
  START  WITH id = 0
  CONNECT BY PRIOR id = parent_id
  ORDER  siblings BY pos DESC,id DESC),
ordered_hierarchy_data AS
 (SELECT id,
         parent_id AS pid,
         nvl(plan_hash_value,0) AS phv,
         row_number() OVER(PARTITION BY plan_hash_value ORDER BY ROWNUM DESC) AS oid,
         max(id) OVER(PARTITION BY plan_hash_value) AS maxid
  FROM   hierarchy_data),
qry AS
 (SELECT DISTINCT sql_id sq,
         flag flag,
         'BASIC ROWS PARTITION PARALLEL PREDICATE NOTE REMOTE &adaptive &fmt' format,
         plan_hash_value phv,
         coalesce(child_number, plan_hash_value,0) plan_hash,
         inst_id
  FROM   sql_plan_data),
ash_detail AS (
    SELECT h.*,costs secs
    FROM (
        SELECT h.*,decode(row_number() OVER(PARTITION BY sql_plan_line_id,sql_exec,sample_time+0 ORDER BY costs DESC),1,&unit,0) aas
        FROM (
            SELECT h.*,
                   nvl(sql_id,'<Parsing>') sql_id_,
                   nvl(event,'ON CPU')||decode(in_parse,'Y',' [PARSE]') ev,
                   nvl(trim(CASE 
                        WHEN current_obj# < -1 THEN
                            'Temp I/O'
                        WHEN current_obj# > 0 THEN 
                             ''||current_obj#
                        WHEN p2text='id1' THEN
                             ''||p2
                        WHEN p3text IN('(identifier<<32)+(namespace<<16)+mode','100*mode+namespace') THEN 
                             ''||trunc(p3/power(16,8))
                        WHEN p3text LIKE '%namespace' AND p3>power(16,8)*4294950912 THEN
                            'Undo'
                        WHEN p3text LIKE '%namespace' AND p3>power(16,8) THEN 
                             ''||trunc(p3/power(16,8))
                        WHEN p3text LIKE '%namespace' THEN 
                            'X$KGLST#'||trunc(mod(p3,power(16,8))/power(16,4))
                        WHEN p1text LIKE 'cache id' THEN 
                            (SELECT parameter FROM v$rowcache WHERE cache#=p1 AND ROWNUM<2)
                        WHEN event LIKE 'latch%' AND p2text='number' THEN 
                            (SELECT name FROM v$latchname WHERE latch#=p2 AND ROWNUM<2)
                        WHEN p3text='class#' THEN
                            (SELECT class FROM (SELECT class, ROWNUM r FROM v$waitstat) WHERE r=p3 AND ROWNUM<2)
                        WHEN p1text ='file#' AND p2text='block#' THEN 
                            'file#'||p1||' block#'||p2
                        WHEN p3text IN('block#','block') THEN 
                            'file#'||dbms_utility.data_block_address_file(p3)||' block#'||dbms_utility.data_block_address_block(p3)    
                        WHEN px_flags > 65536 THEN
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
                        WHEN current_obj# = 0 THEN 'Undo'
                        --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                        --when c.class is not null then c.class
                    END),''||current_obj#) curr_obj#,
                   nvl(wait_class,'ON CPU') wl,
                   least(coalesce(tm_delta_db_time,delta_time,&unit*1e6),coalesce(tm_delta_time,delta_time,&unit*1e6),&unit*2e6) * 1e-6 costs,
                   sql_plan_hash_value||','||nvl(qc_session_id,session_id)||','||sql_exec_id||to_char(nvl(sql_exec_start,sample_time+0),'yyyymmddhh24miss') sql_exec
            FROM   &ASH h
            WHERE  '&V1' IN(sql_id,top_level_sql_id)
            AND    sample_time BETWEEN nvl(to_date(nvl('&V3',:STARTTIME),'YYMMDDHH24MISS'),sysdate-7) 
                                   AND nvl(to_date(nvl('&V4',:ENDTIME),'YYMMDDHH24MISS'),sysdate+1)) h) h) ,
ash AS(SELECT b.*,
              round(sum(aas) OVER(PARTITION BY sql_id,sql_plan_line_id,&OBJ)*100/sum(aas) OVER(PARTITION BY sql_plan_line_id),1) tenv
       FROM (SELECT /*+no_expand no_merge(b) ordered use_hash(b)*/ b.*
             FROM   qry a,ash_detail b 
             WHERE  a.phv = nvl(nullif(b.sql_plan_hash_value,0),a.phv)
             AND    a.sq=b.sql_id_
             AND    ('&V2' IS NULL OR nvl(lengthb('&V2'),0) >6 OR NOT regexp_like('&V2','^\d+$') OR '&V2'+0 IN(qc_session_id,session_id))
       ) b),
ash_base AS(
   SELECT /*+materialize no_expand*/ 
           nvl(sql_plan_line_id,0) id,
           sum(aas)||'('||round(100*ratio_to_report(sum(aas)) OVER())||'%)' px_hits,
           ceil(sum(secs)) secs,
           count(DISTINCT sql_exec) exes,
           round(count(decode(wl, 'ON CPU', aas))*100/ sum(aas), 1) "CPU",
           round(count(CASE WHEN wl IN ('User I/O','System I/O') THEN aas END) * 100 / sum(aas), 1) "IO",
           round(count(decode(wl, 'Cluster', aas)) * 100 / sum(aas), 1) "CL",
           round(count(decode(wl, 'Concurrency', aas)) * 100 / sum(aas), 1) "CC",
           round(count(decode(wl, 'Application', aas)) * 100 / sum(aas), 1) "APP",
           round(count(CASE WHEN wl NOT IN ('ON CPU','User I/O','System I/O','Cluster','Concurrency','Application') THEN aas END) * 100 / sum(aas), 1) oth,
           max(&OBJ||'('||tenv||'%)') KEEP(dense_rank LAST ORDER BY tenv) top_event
    FROM   ash
    GROUP  BY nvl(sql_plan_line_id,0)),
ash_agg AS
 (SELECT /*+materialize*/ 
         top_item,
         to_char(max(execs)) execs,
         nvl(trim(dbms_xplan.format_time_s(ceil(sum(secs)))),' ') secs,
         nvl(trim(dbms_xplan.format_number(sum(io_reqs))),' ') io_reqs,
         nvl(trim(dbms_xplan.format_size(sum(io_bytes))),' ') io_bytes,
         to_char(sum(aas0)) aas,
         listagg(CASE WHEN r <= 7 AND c0 = 1 THEN id || '(' || aas || '%)' END, ',') WITHIN GROUP(ORDER BY aas DESC) plan_lines,
         listagg(CASE WHEN r1 <= 5 AND c1 = 1 THEN substr(obj1, 1, 32) || '(' || aas1 || '%)' END, ',') WITHIN GROUP(ORDER BY aas1 DESC,obj1 DESC) wait_objects
  FROM   (SELECT obj top_item,
                 obj1,
                 nvl(id, 0) id,
                 max(execs) execs,
                 aas,
                 aas1,
                 sum(aas0)  aas0,
                 sum(secs) secs,
                 sum(io_reqs) io_reqs,
                 sum(io_bytes) io_bytes,
                 row_number() OVER(PARTITION BY obj, id ORDER BY 1) c0,
                 row_number() OVER(PARTITION BY obj, obj1 ORDER BY 1) c1,
                 dense_rank() OVER(PARTITION BY obj ORDER BY aas DESC,id) r,
                 dense_rank() OVER(PARTITION BY obj ORDER BY aas1 DESC,obj1 DESC) r1
          FROM   (SELECT secs,
                         nvl(sql_plan_line_id,0) id,
                         &OBJ obj,
                         &OBJ1 obj1,
                         delta_read_io_requests+delta_write_io_requests io_reqs,
                         delta_interconnect_io_bytes io_bytes,
                         aas aas0,
                         count(DISTINCT sql_exec) OVER(PARTITION BY &OBJ) execs,
                         round(sum(aas) OVER(PARTITION BY &OBJ, sql_plan_line_id)*100/nullif(sum(aas) OVER(PARTITION BY &OBJ),0),1) aas,
                         round(sum(aas) OVER(PARTITION BY &OBJ, &OBJ1)*100/nullif(sum(aas) OVER(PARTITION BY &OBJ),0),1) aas1
                  FROM   ash a)
          GROUP  BY obj, id, aas, obj1, aas1)
  GROUP  BY top_item
  ORDER  BY aas+0 DESC),
ash_width AS
 (SELECT greatest(max(length(top_item)),9) c1, 
         greatest(max(length(execs)),5) c2, 
         greatest(nvl(max(length(secs)),0),4) c3, 
         greatest(max(length(aas)),4) c4, 
         greatest(max(length(plan_lines)),18) c5, 
         greatest(max(length(wait_objects)),18) c6,
         greatest(max(length(io_reqs)),7) c7,
         greatest(max(length(io_bytes)),8) c8,
         count(1) cnt
  FROM ash_agg),
plan_agg AS(
  SELECT /*+materialize*/ 
         sql_id_,decode(sql_id_,'&V1',''||sql_plan_hash_value,'=> '||sql_id_) plan_hash,
         count(DISTINCT sql_exec) execs,
         nvl(trim(dbms_xplan.format_time_s(sum(secs))),' ') secs,
         sum(aas) aas,
         round(count(decode(wl, 'ON CPU', aas))*100/ sum(aas), 1) "CPU",
         round(count(CASE WHEN wl IN ('User I/O','System I/O') THEN aas END) * 100 / sum(aas), 1) "IO",
         round(count(decode(wl, 'Cluster', aas)) * 100 / sum(aas), 1) "CL",
         round(count(decode(wl, 'Concurrency', aas)) * 100 / sum(aas), 1) "CC",
         round(count(decode(wl, 'Application', aas)) * 100 / sum(aas), 1) "APP",
         round(count(CASE WHEN wl NOT IN ('ON CPU','User I/O','System I/O','Cluster','Concurrency','Application') THEN aas END) * 100 / sum(aas), 1) oth,
         nvl(trim(dbms_xplan.format_number(sum(delta_read_io_requests+delta_write_io_requests))),' ') io_reqs,
         nvl(trim(dbms_xplan.format_size(sum(delta_interconnect_io_bytes))),' ') io_bytes,
         listagg(CASE WHEN r <= 4 AND c0 = 1 THEN item END, ' / ') WITHIN GROUP(ORDER BY tenv DESC) top_event
  FROM  ( SELECT  s.*,
                  obj||'('||tenv||'%)' item,
                  row_number() OVER(PARTITION BY sql_plan_hash_value,obj,tenv ORDER BY 1) c0,
                  dense_rank() OVER(PARTITION BY sql_plan_hash_value ORDER BY tenv DESC) r
          FROM  (
             SELECT s.*,&OBJ obj,
                    round(100*sum(aas) OVER(PARTITION BY sql_id_,sql_plan_hash_value,&OBJ)/sum(aas) OVER(PARTITION BY sql_plan_hash_value),1) tenv
             FROM   ash_detail s) s
        ) 
  GROUP  BY sql_id_,decode(sql_id_,'&V1',''||sql_plan_hash_value,'=> '||sql_id_)
),

plan_width AS (
  SELECT greatest(max(length(plan_hash)+1),9) c1, 
         greatest(max(length(execs)),5) c2, 
         greatest(nvl(max(length(secs)),0),4) c3, 
         greatest(max(length(aas)),4) c4, 
         greatest(max(length(io_reqs)),7) c7,
         greatest(max(length(io_bytes)),8) c8,
         greatest(max(length(top_event)),10) c9, 
         count(1) cnt
  FROM plan_agg
),

ash_data AS(
    SELECT /*+materialize no_expand no_merge(a) no_merge(b)*/*
    FROM   ordered_hierarchy_data a
    LEFT   JOIN ash_base b
    USING  (id)
) ,
xplan AS
 (SELECT ROWNUM r,plan_table_output output
  FROM   qry, TABLE(dbms_xplan.display('&src1',NULL,format,'&cid='||inst_id||' and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 2
  UNION ALL
  SELECT ROWNUM r,a.*
  FROM   qry,
         TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'child_number=' || plan_hash || ' and sql_id=''' || sq ||''' and inst_id=' || inst_id)) a
  WHERE  flag = 1),
xplan_data AS
 (SELECT CASE
            WHEN output LIKE 'Plan hash value%' THEN
                 output ||'   from '||coalesce('&V3',:STARTTIME,to_char(sysdate-90,'YYMMDDHH24MI'))||' to '||coalesce('&V4',:ENDTIME,to_char(sysdate,'YYMMDDHH24MI'))
            WHEN output LIKE '---%' THEN
                 output || rpad('-', decode(:simple,0,0,sevent)+csize+spx_hit+ssec+sexe+31, '-')
            WHEN id1=-2 THEN
                 regexp_replace(output, '\|','|'  || lpad('Ord |', csize)--
                 ||lpad('Execs',sexe)
                 ||lpad('AAS',spx_hit)
                 ||lpad('Time|',ssec)
                 ||' CPU%  IO%  CL%  CC% APP% OTH%|'
                 ||decode(:simple,0,'',rpad(' Top &title',sevent-1)||'|'),1,2)
            WHEN id IS NOT NULL THEN
                 regexp_replace(output, '\|','|' || lpad(oid || ' |', csize)
                 ||lpad(exes, sexe)
                 ||lpad(px_hits,spx_hit)
                 ||lpad(secs||'|', ssec)
                 ||lpad(cpu,5)||lpad(io,5)||lpad(cl,5)||lpad(cc,5)||lpad(app,5)||lpad(oth,5)||'|'
                 ||decode(:simple,0,'',rpad(' '||top_event,sevent-1)||'|'),1,2)
            ELSE
                 output
         END output,
         id1,id
  FROM (SELECT /*+ ordered use_nl(o) */
               x.r,
               o.id,
               nvl2(o.id,o.id,r-min(nvl2(o.id,r,NULL)) OVER()) id1,
               greatest(max(lengthb(nvl(''||maxid,' '))) OVER () + 3, 6) AS csize,
               greatest(max(lengthb(nvl(''||secs,' '))) OVER () + 1, 5)+1 AS ssec,
               greatest(max(lengthb(nvl(''||px_hits,' '))) OVER () + 1, 7) AS spx_hit,
               greatest(max(lengthb(nvl(''||exes,' '))) OVER () + 1, 5) AS sexe,
               greatest(max(lengthb(nvl(top_event,' '))) OVER () + 2, 11) AS sevent,
               x.output AS output,
               o.pid,
               o.oid,
               o.maxid,
               regexp_replace(nvl(cpu,0),'^0$',' ') cpu,
               regexp_replace(nvl(io,0),'^0$',' ') io,
               regexp_replace(nvl(cc,0),'^0$',' ') cc,
               regexp_replace(nvl(cl,0),'^0$',' ') cl,
               regexp_replace(nvl(app,0),'^0$',' ') app,
               regexp_replace(nvl(oth,0),'^0$',' ') oth,
               regexp_replace(nvl(px_hits,0),'^0$',' ') px_hits,
               decode(nvl(secs,0),0,' ',regexp_replace(trim(dbms_xplan.format_time_s(secs)),'^00:')) secs,
               regexp_replace(nvl(exes,0),'^0$',' ') exes,
               nvl(top_event,' ') top_event,
               p.phv,
              count(*) OVER() AS rc
      FROM   (SELECT DISTINCT phv FROM ordered_hierarchy_data) p
      CROSS  JOIN xplan x
      LEFT JOIN ash_data o
      ON     (nvl(nullif(o.phv,0),p.phv) = p.phv AND o.id = to_number(regexp_substr(x.output, '^\|[-\* ]*([0-9]+) \|',1,1,'i',1)))) a
 ORDER BY r)
SELECT output FROM xplan_data

UNION ALL
SELECT NULL FROM ash_width WHERE cnt>0
UNION ALL

SELECT  '+'||rpad('-',c1,'-')||'+'||rpad('-',c2,'-')||'+'||rpad('-',c3,'-')||'+'||rpad('-',c4,'-')||'+'||rpad('-',c7,'-')||'+'||rpad('-',c8,'-')||'+'||rpad('-',c5,'-')||'+'||rpad('-',c6,'-')||'+'
FROM    ash_width WHERE cnt>0
UNION  ALL
SELECT  '|'||rpad('TOP_ITEM',c1,' ')||'|'||lpad('EXECS',c2,' ')||'|'||rpad('TIME',c3,' ')||'|'||lpad('AAS',c4,' ')||'|'||lpad('IO Reqs',c7,' ')||'|'||lpad('IO Bytes',c8,' ')||'|'||rpad('TOP_SQL_PLAN_LINES',c5,' ')||'|'||rpad('TOP_WAIT_OBJECTS',c6,' ')||'|'
FROM    ash_width WHERE cnt>0
UNION ALL 
SELECT  '|'||rpad('-',c1,'-')||'+'||rpad('-',c2,'-')||'+'||rpad('-',c3,'-')||'+'||rpad('-',c4,'-')||'+'||rpad('-',c7,'-')||'+'||rpad('-',c8,'-')||'+'||rpad('-',c5,'-')||'+'||rpad('-',c6,'-')||'|'
FROM    ash_width WHERE cnt>0
UNION ALL
SELECT * FROM (
SELECT  '|'||rpad(top_item,c1,' ')||'|'||lpad(execs,c2,' ')||'|'||rpad(secs,c3,' ')||'|'||lpad(aas,c4,' ')||'|'||lpad(io_reqs,c7,' ')||'|'||lpad(io_bytes,c8,' ')||'|'||rpad(plan_lines,c5,' ')||'|'||rpad(wait_objects,c6,' ')||'|'
FROM    ash_width,ash_agg WHERE cnt>0
ORDER BY 0+aas DESC
)
UNION ALL
SELECT  '+'||rpad('-',c1,'-')||'+'||rpad('-',c2,'-')||'+'||rpad('-',c3,'-')||'+'||rpad('-',c4,'-')||'+'||rpad('-',c7,'-')||'+'||rpad('-',c8,'-')||'+'||rpad('-',c5,'-')||'+'||rpad('-',c6,'-')||'+'
FROM    ash_width WHERE cnt>0

UNION ALL
SELECT NULL FROM plan_width WHERE cnt>0
UNION ALL

SELECT  '+'||rpad('-',c1,'-')||'+'||rpad('-',c2,'-')||'+'||rpad('-',c3,'-')||'+'||rpad('-',c4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',c7,'-')||'+'||rpad('-',c8,'-')||'+'||rpad('-',c9,'-')||'+'
FROM    plan_width  WHERE cnt>0
UNION  ALL
SELECT  '|'||lpad('PLAN_HASH',c1,' ')||'|'||lpad('EXECS',c2,' ')||'|'||rpad('TIME',c3,' ')||'|'||lpad('AAS',c4,' ')||'|'||lpad('CPU%',4,' ')||'|'||lpad('IO %',4,' ')||'|'||lpad('CC %',4,' ')||'|'||lpad('CL %',4,' ')||'|'||lpad('APP%',4,' ')||'|'||lpad('OTH%',4,' ')||'|'||lpad('IO Reqs',c7,' ')||'|'||lpad('IO Bytes',c8,' ')||'|'||rpad('Top &Title',c9,' ')||'|'
FROM    plan_width WHERE cnt>0
UNION ALL
SELECT  '+'||rpad('-',c1,'-')||'+'||rpad('-',c2,'-')||'+'||rpad('-',c3,'-')||'+'||rpad('-',c4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',c7,'-')||'+'||rpad('-',c8,'-')||'+'||rpad('-',c9,'-')||'+'
FROM    plan_width WHERE cnt>0
UNION  ALL
SELECT * FROM (
SELECT  '|'||rpad(decode(''||plan_hash,(SELECT ''||phv FROM qry),'*',' ')||plan_hash,c1,' ')||'|'||lpad(execs,c2,' ')||'|'||rpad(secs,c3,' ')||'|'||lpad(aas,c4,' ')||'|'||lpad(cpu,4,' ')||'|'||lpad(io,4,' ')||'|'||lpad(cc,4,' ')||'|'||lpad(cl,4,' ')||'|'||lpad(app,4,' ')||'|'||lpad(oth,4,' ')||'|'||lpad(io_reqs,c7,' ')||'|'||lpad(io_bytes,c8,' ')||'|'||rpad(nvl(top_event,' '),c9,' ')||'|'
FROM    plan_agg,plan_width WHERE cnt>0 ORDER BY 0+aas DESC)
UNION ALL
SELECT  '+'||rpad('-',c1,'-')||'+'||rpad('-',c2,'-')||'+'||rpad('-',c3,'-')||'+'||rpad('-',c4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',c7,'-')||'+'||rpad('-',c8,'-')||'+'||rpad('-',c9,'-')||'+'
FROM    plan_width WHERE cnt>0;
