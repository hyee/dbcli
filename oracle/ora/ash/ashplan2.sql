/*[[
       Show ash cost for a specific SQL for multiple executions. usage: @@NAME {<sql_id> [plan_hash_value|sid|a] [YYMMDDHH24MI] [YYMMDDHH24MI]} [-dash] [-o] -f"<format>"
       -o    : Show top object#, otherwise show top event
       -dash : Based on dba_hist_active_sess_history, otherwise based on gv$active_session_history

       The output is similar to 'ora ashplan', but less accurate and faster
       --[[
       @ARGS: 1
       @adaptive : 12.1={adaptive} 11.1={}
       &V9  : ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
       &ash : ash={(select * from table(gv$(cursor(select userenv('instance') inst_id,a.* from v$active_session_history a where userenv('instance')=nvl(:instance,userenv('instance')) and :V1 in(sql_id,top_level_sql_id)))))}, dash={Dba_Hist_Active_Sess_History}
       &unit: ash={1}, dash={10}
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
 (SELECT /*+materialize*/ *
  FROM   (SELECT a.*,
                 dense_rank() OVER(ORDER BY flag, tm DESC, child_number DESC, plan_hash_value DESC,inst_id desc) seq
          FROM   (SELECT *
                  FROM TABLE(GV$(CURSOR(
                      SELECT id,
                             decode(parent_id,-1,id-1,parent_id) parent_id,
                             child_number    ha,
                             1               flag,
                             TIMESTAMP       tm,
                             child_number,
                             sql_id,
                             nvl(plan_hash_value,0) plan_hash_value,
                             userenv('instance') inst_id,
                             object#,OBJECT_NAME
                      FROM   v$sql_plan_statistics_all a
                      WHERE  userenv('instance')=nvl(:instance,userenv('instance'))
                      AND    a.sql_id = :V1
                      AND    a.plan_hash_value = case when nvl(lengthb(:V2),0) >6 then :V2+0 else plan_hash_value end)))
                  UNION ALL
                  SELECT id,
                         decode(parent_id,-1,id-1,parent_id) parent_id,
                         plan_hash_value,
                         2,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         nvl(plan_hash_value,0) plan_hash_value,
                         dbid,
                         object#,OBJECT_NAME
                  FROM   dba_hist_sql_plan a
                  WHERE  a.sql_id = :V1
                  AND    a.plan_hash_value = case when nvl(lengthb(:V2),0) >6 then :V2+0 else plan_hash_value end
                  ) a)
  WHERE  seq = 1),
hierarchy_data AS
 (SELECT id, parent_id, plan_hash_value
  FROM   sql_plan_data
  START  WITH id = 0
  CONNECT BY PRIOR id = parent_id
  ORDER  SIBLINGS BY id DESC),
ordered_hierarchy_data AS
 (SELECT id,
         parent_id AS pid,
         nvl(plan_hash_value,0) AS phv,
         row_number() over(PARTITION BY plan_hash_value ORDER BY rownum DESC) AS OID,
         MAX(id) over(PARTITION BY plan_hash_value) AS maxid
  FROM   hierarchy_data),
qry AS
 (SELECT DISTINCT sql_id sq,
         flag flag,
         'BASIC ROWS PARTITION PARALLEL PREDICATE NOTE REMOTE &adaptive &fmt' format,
         plan_hash_value phv,
         coalesce(child_number, plan_hash_value,0) plan_hash,
         inst_id
  FROM   sql_plan_data),

ash_detail as (
    SELECT H.*,costs SECS
    FROM (
        SELECT h.*,decode(row_number() over(partition by SQL_PLAN_LINE_ID,sql_exec,sample_time+0 order by costs desc),1,&unit,0) AAS
        FROM (
            select h.*,
                   nvl(sql_id,'<Parsing>') sql_id_,
                   nvl(event,'ON CPU') ev,
                   case 
                        when current_obj# > 0 then 
                             nvl((select max(object_name) from sql_plan_data where object#=current_obj#),''||current_obj#) 
                        when p3text='100*mode+namespace' and p3>power(2,32) then 
                             nvl((select max(object_name) from sql_plan_data where object#=trunc(p3/power(2,32))),''||trunc(p3/power(2,32))) 
                        when p3text like '%namespace' then 
                             'x$kglst#'||trunc(mod(p3,power(2,32))/power(2,16))
                        when p1text like 'cache id' then 
                             (select parameter from v$rowcache where cache#=p1 and rownum<2)
                        when event like 'latch%' and p2text='number' then 
                             (select name from v$latchname where latch#=p2 and rownum<2)
                        when p3text='class#' then
                             (select class from (SELECT class, ROWNUM r from v$waitstat) where r=p3)
                        when current_obj#=0 then 'Undo'
                        --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                        --when c.class is not null then c.class
                        else ''||greatest(current_obj#,-2)
                    end curr_obj#,
                   nvl(wait_class,'ON CPU') wl,
                   least(coalesce(tm_delta_db_time,DELTA_TIME,&unit*1e6),coalesce(tm_delta_time,DELTA_TIME,&unit*1e6),&unit*2e6) * 1e-6 costs,
                   sql_plan_hash_value||','||nvl(qc_session_id,session_id)||','||sql_exec_id||to_char(nvl(sql_exec_start,sample_time+0),'yyyymmddhh24miss') sql_exec
            from   &ASH h
            WHERE  :V1 in(sql_id,top_level_sql_id)
            AND    sample_time BETWEEN NVL(to_date(nvl(:V3,:STARTTIME),'YYMMDDHH24MISS'),SYSDATE-7) 
                                   AND NVL(to_date(nvl(:V4,:ENDTIME),'YYMMDDHH24MISS'),SYSDATE)) H) H) ,

ash as(SELECT b.*,
              ROUND(SUM(AAS) OVER(PARTITION BY SQL_ID,SQL_PLAN_LINE_ID,&OBJ)*100/SUM(AAS) OVER(PARTITION BY SQL_PLAN_LINE_ID),1) tenv
       FROM (select /*+no_expand no_merge(b) ordered use_hash(b)*/ b.*
             FROM   qry a,ash_detail b 
             WHERE  a.phv = nvl(nullif(b.sql_plan_hash_value,0),a.phv)
             AND    a.sq=b.sql_id_
             AND    (:V2 is null or nvl(lengthb(:V2),0) >6 or not regexp_like(:V2,'^\d+$') or :V2+0 in(QC_SESSION_ID,SESSION_ID))
       ) b),
ash_base AS(
   SELECT /*+materialize no_expand*/ 
           nvl(SQL_PLAN_LINE_ID,0) ID,
           sum(AAS)||'('||round(100*ratio_to_report(sum(AAS)) over())||'%)' px_hits,
           CEIL(SUM(secs)) secs,
           COUNT(DISTINCT sql_exec) exes,
           ROUND(COUNT(DECODE(wl, 'ON CPU', AAS))*100/ SUM(AAS), 1) "CPU",
           ROUND(COUNT(CASE WHEN wl IN ('User I/O','System I/O') THEN AAS END) * 100 / SUM(AAS), 1) "IO",
           ROUND(COUNT(DECODE(wl, 'Cluster', AAS)) * 100 / SUM(AAS), 1) "CL",
           ROUND(COUNT(DECODE(wl, 'Concurrency', AAS)) * 100 / SUM(AAS), 1) "CC",
           ROUND(COUNT(DECODE(wl, 'Application', AAS)) * 100 / SUM(AAS), 1) "APP",
           ROUND(COUNT(CASE WHEN wl NOT IN ('ON CPU','User I/O','System I/O','Cluster','Concurrency','Application') THEN AAS END) * 100 / SUM(AAS), 1) oth,
           MAX(&OBJ||'('||tenv||'%)') KEEP(dense_rank LAST ORDER BY tenv) top_event
    FROM   ash
    GROUP  BY nvl(SQL_PLAN_LINE_ID,0)),
ash_agg AS
 (SELECT /*+materialize*/ 
         top_item,
         to_char(MAX(execs)) execs,
         nvl(trim(dbms_xplan.FORMAT_TIME_S(ceil(SUM(secs)))),' ') secs,
         nvl(trim(dbms_xplan.format_number(sum(io_reqs))),' ') io_reqs,
         nvl(trim(dbms_xplan.format_size(sum(io_bytes))),' ') io_bytes,
         to_char(SUM(aas0)) aas,
         listagg(CASE WHEN r <= 7 AND c0 = 1 THEN id || '(' || aas || '%)' END, ',') within GROUP(ORDER BY aas DESC) Plan_lines,
         listagg(CASE WHEN r1 <= 5 AND c1 = 1 THEN SUBSTR(OBJ1, 1, 32) || '(' || aas1 || '%)' END, ',') within GROUP(ORDER BY aas1 DESC,OBJ1 DESC) wait_objects
  FROM   (SELECT OBJ top_item,
                 OBJ1,
                 nvl(ID, 0) ID,
                 MAX(execs) execs,
                 AAS,
                 aas1,
                 SUM(aas0)  aas0,
                 SUM(secs) secs,
                 sum(io_reqs) io_reqs,
                 sum(io_bytes) io_bytes,
                 row_number() OVER(PARTITION BY OBJ, ID ORDER BY 1) c0,
                 row_number() OVER(PARTITION BY OBJ, OBJ1 ORDER BY 1) c1,
                 dense_Rank() OVER(PARTITION BY OBJ ORDER BY aas DESC,ID) r,
                 dense_Rank() OVER(PARTITION BY OBJ ORDER BY aas1 DESC,OBJ1 DESC) r1
          FROM   (SELECT secs,
                         nvl(SQL_PLAN_LINE_ID,0) ID,
                         &OBJ obj,
                         &OBJ1 obj1,
                         DELTA_READ_IO_REQUESTS+DELTA_WRITE_IO_REQUESTS io_reqs,
                         DELTA_INTERCONNECT_IO_BYTES io_bytes,
                         aas aas0,
                         COUNT(DISTINCT sql_exec) over(PARTITION BY &OBJ) execs,
                         ROUND(SUM(AAS) OVER(PARTITION BY &OBJ, SQL_PLAN_LINE_ID)*100/nullif(SUM(AAS) OVER(PARTITION BY &OBJ),0),1) aas,
                         ROUND(SUM(AAS) OVER(PARTITION BY &OBJ, &OBJ1)*100/nullif(SUM(AAS) OVER(PARTITION BY &OBJ),0),1) aas1
                  FROM   ash a)
          GROUP  BY OBJ, ID, aas, OBJ1, aas1)
  GROUP  BY top_item
  ORDER  BY AAS+0 DESC),
ash_width AS
 (SELECT greatest(MAX(LENGTH(top_item)),9) c1, 
         greatest(MAX(LENGTH(execs)),5) c2, 
         greatest(nvl(MAX(LENGTH(secs)),0),4) c3, 
         greatest(MAX(LENGTH(aas)),4) c4, 
         greatest(MAX(LENGTH(Plan_lines)),18) c5, 
         greatest(MAX(LENGTH(wait_objects)),18) c6,
         greatest(MAX(LENGTH(io_reqs)),7) c7,
         greatest(MAX(LENGTH(io_bytes)),8) c8,
         count(1) cnt
  FROM ash_agg),
plan_agg as(
  SELECT /*+materialize*/ 
         sql_id_,decode(sql_id_,:V1,''||SQL_PLAN_HASH_VALUE,'=> '||sql_id_) PLAN_HASH,
         COUNT(DISTINCT SQL_EXEC) EXECS,
         nvl(trim(dbms_xplan.format_time_s(SUM(SECS))),' ') secs,
         SUM(AAS) AAS,
         ROUND(COUNT(DECODE(wl, 'ON CPU', AAS))*100/ SUM(AAS), 1) "CPU",
         ROUND(COUNT(CASE WHEN wl IN ('User I/O','System I/O') THEN AAS END) * 100 / SUM(AAS), 1) "IO",
         ROUND(COUNT(DECODE(wl, 'Cluster', AAS)) * 100 / SUM(AAS), 1) "CL",
         ROUND(COUNT(DECODE(wl, 'Concurrency', AAS)) * 100 / SUM(AAS), 1) "CC",
         ROUND(COUNT(DECODE(wl, 'Application', AAS)) * 100 / SUM(AAS), 1) "APP",
         ROUND(COUNT(CASE WHEN wl NOT IN ('ON CPU','User I/O','System I/O','Cluster','Concurrency','Application') THEN AAS END) * 100 / SUM(AAS), 1) oth,
         nvl(trim(dbms_xplan.format_number(SUM(DELTA_READ_IO_REQUESTS+DELTA_WRITE_IO_REQUESTS))),' ') io_reqs,
         nvl(trim(dbms_xplan.format_size(SUM(DELTA_INTERCONNECT_IO_BYTES))),' ') io_bytes,
         listagg(CASE WHEN r <= 4 AND c0 = 1 THEN item END, ' / ') within GROUP(ORDER BY tenv DESC) top_event
  FROM  ( SELECT  s.*,
                  obj||'('||tenv||'%)' item,
                  row_number() OVER(PARTITION BY SQL_PLAN_HASH_VALUE,OBJ,tenv ORDER BY 1) c0,
                  dense_Rank() OVER(PARTITION BY SQL_PLAN_HASH_VALUE ORDER BY tenv DESC) r
          FROM  (
             SELECT s.*,&OBJ obj,
                    ROUND(100*SUM(AAS) OVER(PARTITION BY sql_id_,SQL_PLAN_HASH_VALUE,&OBJ)/SUM(AAS) OVER(PARTITION BY SQL_PLAN_HASH_VALUE),1) tenv
             FROM   ash_detail s) s
        ) 
  GROUP  BY sql_id_,decode(sql_id_,:V1,''||SQL_PLAN_HASH_VALUE,'=> '||sql_id_)
),

plan_width as (
  SELECT greatest(MAX(LENGTH(PLAN_HASH)+1),9) c1, 
         greatest(MAX(LENGTH(execs)),5) c2, 
         greatest(nvl(MAX(LENGTH(secs)),0),4) c3, 
         greatest(MAX(LENGTH(aas)),4) c4, 
         greatest(MAX(LENGTH(io_reqs)),7) c7,
         greatest(MAX(LENGTH(io_bytes)),8) c8,
         greatest(MAX(LENGTH(top_event)),10) c9, 
         count(1) cnt
  FROM plan_agg
),

ash_data AS(
    SELECT /*+materialize no_expand no_merge(a) no_merge(b)*/*
    FROM   ordered_hierarchy_data a
    LEFT   JOIN ash_base b
    USING     (ID)
) ,
xplan AS
 (SELECT rownum r,plan_table_output output
  FROM   qry, TABLE(dbms_xplan.display('dba_hist_sql_plan',NULL,format,'dbid='||inst_id||' and plan_hash_value=' || plan_hash || ' and sql_id=''' || sq ||'''')) a
  WHERE  flag = 2
  UNION ALL
  SELECT rownum r,a.*
  FROM   qry,
         TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'child_number=' || plan_hash || ' and sql_id=''' || sq ||''' and inst_id=' || inst_id)) a
  WHERE  flag = 1),
xplan_data AS
 (SELECT CASE
            WHEN output like 'Plan hash value%' THEN
                 output ||'   from '||COALESCE(:V3,:STARTTIME,to_char(sysdate-90,'YYMMDDHH24MI'))||' to '||COALESCE(:V4,:ENDTIME,to_char(sysdate,'YYMMDDHH24MI'))
            WHEN output like '---%' THEN
                 output || rpad('-', decode(:simple,0,0,sevent)+csize+spx_hit+ssec+sexe+31, '-')
            WHEN id1=-2 THEN
                 regexp_replace(output, '\|','|'  || lpad('Ord |', csize)--
                 ||LPAD('Execs',sexe)
                 ||LPAD('AAS',spx_hit)
                 ||LPAD('Time|',ssec)
                 ||' CPU%  IO%  CL%  CC% APP% OTH%|'
                 ||decode(:simple,0,'',RPAD(' Top &title',sevent-1)||'|'),1,2)
            WHEN id is not null THEN
                 regexp_replace(output, '\|','|' || lpad(oid || ' |', csize)
                 ||LPAD(exes, sexe)
                 ||LPAD(px_hits,spx_hit)
                 ||LPAD(secs||'|', ssec)
                 ||LPAD(CPU,5)||LPAD(IO,5)||LPAD(CL,5)||LPAD(cc,5)||LPAD(app,5)||LPAD(oth,5)||'|'
                 ||decode(:simple,0,'',RPAD(' '||top_event,sevent-1)||'|'),1,2)
            ELSE
                 output
         END output,
         id1,id
  FROM (SELECT /*+ ordered use_nl(o) */
               x.r,
               o.id,
               nvl2(o.id,o.id,r-min(nvl2(o.id,r,null)) over()) id1,
               greatest(max(LENGTHB(nvl(''||maxid,' '))) over () + 3, 6) as csize,
               greatest(max(LENGTHB(nvl(''||secs,' '))) over () + 1, 5)+1 as ssec,
               greatest(max(LENGTHB(nvl(''||px_hits,' '))) over () + 1, 7) as spx_hit,
               greatest(max(LENGTHB(nvl(''||exes,' '))) over () + 1, 5) as sexe,
               greatest(max(LENGTHB(nvl(top_event,' '))) over () + 2, 11) as sevent,
               x.output AS output,
               o.pid,
               o.oid,
               o.maxid,
               regexp_replace(nvl(cpu,0),'^0$',' ') CPU,
               regexp_replace(nvl(io,0),'^0$',' ') io,
               regexp_replace(nvl(cc,0),'^0$',' ') cc,
               regexp_replace(nvl(cl,0),'^0$',' ') cl,
               regexp_replace(nvl(app,0),'^0$',' ') app,
               regexp_replace(nvl(oth,0),'^0$',' ') oth,
               regexp_replace(nvl(px_hits,0),'^0$',' ') px_hits,
               decode(nvl(secs,0),0,' ',regexp_replace(trim(dbms_xplan.FORMAT_TIME_S(secs)),'^00:')) secs,
               regexp_replace(nvl(exes,0),'^0$',' ') exes,
               nvl(top_event,' ') top_event,
               p.phv,
              COUNT(*) over() AS rc
      FROM   (SELECT DISTINCT phv FROM ordered_hierarchy_data) p
      CROSS  JOIN xplan x
      LEFT JOIN ash_data o
      ON     (nvl(nullif(o.phv,0),p.phv) = p.phv AND o.id = to_number(regexp_substr(x.output, '^\|[-\* ]*([0-9]+) \|',1,1,'i',1)))) a
 order by r)
SELECT output from xplan_data

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
select * from (
SELECT  '|'||rpad(top_item,c1,' ')||'|'||lpad(execs,c2,' ')||'|'||rpad(secs,c3,' ')||'|'||lpad(aas,c4,' ')||'|'||lpad(io_reqs,c7,' ')||'|'||lpad(io_bytes,c8,' ')||'|'||rpad(Plan_lines,c5,' ')||'|'||rpad(wait_objects,c6,' ')||'|'
FROM    ash_width,ash_agg WHERE cnt>0
ORDER BY 0+AAS DESC
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
SELECT  '|'||rpad(decode(''||plan_hash,(select ''||phv from qry),'*',' ')||plan_hash,c1,' ')||'|'||lpad(execs,c2,' ')||'|'||rpad(secs,c3,' ')||'|'||lpad(aas,c4,' ')||'|'||lpad(cpu,4,' ')||'|'||lpad(io,4,' ')||'|'||lpad(cc,4,' ')||'|'||lpad(cl,4,' ')||'|'||lpad(app,4,' ')||'|'||lpad(oth,4,' ')||'|'||lpad(io_reqs,c7,' ')||'|'||lpad(io_bytes,c8,' ')||'|'||rpad(nvl(top_event,' '),c9,' ')||'|'
FROM    plan_agg,plan_width WHERE cnt>0 order by 0+aas desc)
UNION ALL
SELECT  '+'||rpad('-',c1,'-')||'+'||rpad('-',c2,'-')||'+'||rpad('-',c3,'-')||'+'||rpad('-',c4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',4,'-')||'+'||rpad('-',c7,'-')||'+'||rpad('-',c8,'-')||'+'||rpad('-',c9,'-')||'+'
FROM    plan_width WHERE cnt>0;
