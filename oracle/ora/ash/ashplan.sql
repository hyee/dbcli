/*[[Show ash cost for a specific SQL. usage: @@NAME {<sql_id> [plan_hash_value|sid|a] [YYMMDDHH24MI] [YYMMDDHH24MI]} [-dash] [-o]
-o    : Show top object#, otherwise show top event
-dash : Based on dba_hist_active_sess_history, otherwise based on gv$active_session_history
--[[
    @adaptive : 12.1={adaptive} 11.1={}
    &V9 : ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
    &OBJ: default={nvl(event,'ON CPU')}, O={CURRENT_OBJ#}
    &Title: default={Event}, O={Obj#}
--]]
]]*/
set feed off printsize 3000 pipequery off

WITH sql_plan_data AS
 (SELECT *
  FROM   (SELECT a.*,
                 dense_rank() OVER(ORDER BY flag, tm DESC, child_number DESC, plan_hash_value DESC,inst_id desc) seq
          FROM   (SELECT id,
                         parent_id,
                         child_number    ha,
                         1               flag,
                         TIMESTAMP       tm,
                         child_number,
                         sql_id,
                         plan_hash_value,
                         inst_id
                  FROM   gv$sql_plan_statistics_all a
                  WHERE  a.sql_id = :V1
                  AND    a.plan_hash_value = case when nvl(lengthb(:V2),0) >6 then :V2+0 else plan_hash_value end
                  UNION ALL
                  SELECT id,
                         parent_id,
                         plan_hash_value,
                         2,
                         TIMESTAMP,
                         NULL child_number,
                         sql_id,
                         plan_hash_value,
                         dbid
                  FROM   dba_hist_sql_plan a
                  WHERE  a.sql_id = :V1
                  AND    a.plan_hash_value = case when nvl(lengthb(:V2),0) >6 then :V2+0 else (select max(plan_hash_value) keep(dense_rank last order by snap_id) from dba_hist_sqlstat where sql_id=:V1)  end
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
         plan_hash_value AS phv,
         row_number() over(PARTITION BY plan_hash_value ORDER BY rownum DESC) AS OID,
         MAX(id) over(PARTITION BY plan_hash_value) AS maxid
  FROM   hierarchy_data),
qry AS
 (SELECT /*+materialize*/
         DISTINCT sql_id sq,
         flag flag,
         'BASIC ROWS PARTITION PARALLEL PREDICATE NOTE &adaptive' format,
         plan_hash_value phv,
         NVL(child_number, plan_hash_value) plan_hash,
         inst_id
  FROM   sql_plan_data),
ash as(SELECT /*+no_expand materialize ordered use_nl(b)*/ 
              b.*,CEIL(SUM(delta_time*1e-6) OVER(PARTITION BY SQL_PLAN_LINE_ID,&OBJ)) tenv
       FROM   qry a
       JOIN   &V9 b
       ON     ( b.sql_id=:V1 AND a.phv = b.sql_plan_hash_value AND sample_time BETWEEN NVL(to_date(nvl(:V3,:STARTTIME),'YYMMDDHH24MISS'),SYSDATE-7) AND NVL(to_date(nvl(:V4,:STARTTIME),'YYMMDDHH24MISS'),SYSDATE))
       AND    (:V2 is null or nvl(lengthb(:V2),0) >6 or not regexp_like(:V2,'^\d+$') or :V2+0 in(QC_SESSION_ID,SESSION_ID))
       ),
ash_base AS(
   SELECT /*+materialize no_expand*/ nvl(SQL_PLAN_LINE_ID,0) ID,
           COUNT(1) px_hits,
           CEIL(SUM(nvl2(qc_session_id,0,Delta_time))*1e-6) hits,
           COUNT(DISTINCT sql_exec_id) exes,
           CEIL(SUM(nvl2(qc_session_id,0,Delta_time))*1e-7/6) mins,
           ROUND(COUNT(DECODE(wait_class, NULL, 1)) * NVL2(max(sample_id),100,0) / COUNT(1), 1) "CPU",
           ROUND(COUNT(CASE WHEN wait_class IN ('User I/O','System I/O') THEN 1 END) * 100 / COUNT(1), 1) "IO",
           ROUND(COUNT(DECODE(wait_class, 'Cluster', 1)) * 100 / COUNT(1), 1) "CL",
           ROUND(COUNT(DECODE(wait_class, 'Concurrency', 1)) * 100 / COUNT(1), 1) "CC",
           ROUND(COUNT(DECODE(wait_class, 'Application', 1)) * 100 / COUNT(1), 1) "APP",
           ROUND(COUNT(CASE WHEN NVL(wait_class,'1') NOT IN ('1','User I/O','System I/O','Cluster','Concurrency','Application') THEN 1 END) * 100 / COUNT(1), 1) oth,
           MAX(&OBJ||'('||tenv||')') KEEP(dense_rank LAST ORDER BY tenv) top_event
    FROM   ash
    GROUP  BY nvl(SQL_PLAN_LINE_ID,0)
),
ash_data AS(
    SELECT /*+materialize no_expand no_merge(a) no_merge(b)*/*
    FROM   ordered_hierarchy_data a
    LEFT   JOIN ash_base b
    USING     (ID)
) ,
xplan AS
 (SELECT a.*
  FROM   qry, TABLE(dbms_xplan.display_awr(sq, plan_hash, NULL, format)) a
  WHERE  flag = 2
  UNION ALL
  SELECT a.*
  FROM   qry,
         TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',NULL,format,'child_number=' || plan_hash || ' and sql_id=''' || sq ||''' and inst_id=' || inst_id)) a
  WHERE  flag = 1),
xplan_data AS
 (SELECT /*+ ordered use_nl(o) */
       rownum AS r,
       x.plan_table_output AS plan_table_output,
       o.id,
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
       decode(nvl(hits,0),0,' ',hits||'('||round(100*ratio_to_report(hits) over())||'%)') hits,
       regexp_replace(nvl(exes,0),'^0$',' ') exes,
       regexp_replace(nvl(mins,0),'^0$',' ') mins,
       nvl(top_event,' ') top_event,
       p.phv,
      COUNT(*) over() AS rc
  FROM   (SELECT DISTINCT phv FROM ordered_hierarchy_data) p
  CROSS  JOIN xplan x
  LEFT JOIN ash_data o
  ON     (o.phv = p.phv AND o.id = CASE WHEN regexp_like(x.plan_table_output, '^\|[-\* ]*[0-9]+ \|') THEN to_number(regexp_substr(x.plan_table_output, '[0-9]+')) END))
SELECT plan_table_output
FROM   xplan_data --
model  dimension by (rownum as r)
measures (plan_table_output,
         id,
         maxid,
         pid,
         oid,
         greatest(max(LENGTHB(maxid)) over () + 3, 6) as csize,
         greatest(max(LENGTHB(hits)) over () + 1, 5) as shit,
         greatest(max(LENGTHB(px_hits)) over () + 1, 7) as spx_hit,
         greatest(max(LENGTHB(exes)) over () + 1, 5) as sexe,
         greatest(max(LENGTHB(mins)) over () + 1, 6) as smin,
         greatest(max(LENGTHB(top_event)) over () + 2, 11) as sevent,
         cast(null as varchar2(150)) as inject,
         cpu,io,cc,cl,app,oth,exes,hits,mins,px_hits,top_event,
         rc)
rules sequential order (
    inject[r] = case
         when plan_table_output[cv()] like '------%'
         then rpad('-', sevent[cv()]+csize[cv()]+spx_hit[cv()]++shit[cv()]+sexe[cv()]+smin[cv()]+31, '-')
         when id[cv()+2] = 0
         then '|'  || lpad('Ord |', csize[cv()])--
             ||LPAD('Calls',sexe[cv()])
             ||LPAD('Count',spx_hit[cv()])
             ||LPAD('Secs',shit[cv()])
             ||LPAD('Mins|',smin[cv()])
             ||' CPU%  IO%  CL%  CC% APP% OTH%|'
            -- ||LPAD('Top_Obj',sobj[cv()])
             ||RPAD(' Top &title',sevent[cv()]-1)||'|'
         when id[cv()] is not null
         then '|' || lpad(oid[cv()] || ' |', csize[cv()])
             ||LPAD(exes[cv()], sexe[cv()])
             ||LPAD(px_hits[cv()],spx_hit[cv()])
             ||LPAD(hits[cv()], shit[cv()])
             ||LPAD(mins[cv()]||'|', smin[cv()])
             ||LPAD(CPU[cv()],5)||LPAD(IO[cv()],5)||LPAD(CL[cv()],5)||LPAD(cc[cv()],5)||LPAD(app[cv()],5)||LPAD(oth[cv()],5)||'|'
            ||RPAD(' '||top_event[cv()],sevent[cv()]-1)||'|'
        end,
    plan_table_output[r] = case
            when inject[cv()] like '---%'
            then inject[cv()] || plan_table_output[cv()]
            when plan_table_output[cv()] like 'Plan hash value%'
            then plan_table_output[cv()]||'   Source: &V9 from '||COALESCE(:V3,:STARTTIME,to_char(sysdate-90,'YYMMDDHH24MI'))||' to '||COALESCE(:V4,:ENDTIME,to_char(sysdate,'YYMMDDHH24MI'))
            when inject[cv()] is not null
            then regexp_replace(plan_table_output[cv()], '\|', inject[cv()], 1, 2)
            else plan_table_output[cv()]
         END
     )
order  by r; 