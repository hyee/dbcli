/*[[Show sql wait stats in AWR ASH. Usage: ora dsqlm <sql_id> <plan_hash_value>]]*/
WITH qry AS
 (SELECT :V1 sq, :V2 has, nvl(lower(:V3),'total') flag,
         to_timestamp(nvl(:V4, to_char(SYSDATE - 7, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') st,
         to_timestamp(coalesce(:V5, '' || (:V4 + 1), to_char(SYSDATE, 'YYMMDDHH24MI')),'YYMMDDHH24MI') ed
  FROM dual where :V1 is not null and :V2 is not null),
ash AS
 (SELECT /*+materialize index(hs ix_wrh$_active_sess_his_sqlid) ordered use_nl(qry hs b)*/ sql_plan_line_id line#,
         ROUND(count(distinct decode(session_state,'ON CPU',TRUNC(SAMPLE_TIME,'MI')))/ nullif(COUNT(DISTINCT sql_exec_id),0),1) "CPU",
         ROUND(count(distinct decode(session_state,'ON CPU',null,TRUNC(SAMPLE_TIME,'MI')))/ nullif(COUNT(DISTINCT sql_exec_id),0),1) "NON-CPU",
         ROUND(COUNT(distinct TRUNC(SAMPLE_TIME,'MI')) / nullif(COUNT(DISTINCT sql_exec_id),0), 1) total,
         decode(qry.flag,'dump',current_obj#) obj,
         to_char(wmsys.wm_concat(DISTINCT b.wait_class)) wait_class
  FROM   qry, (SELECT * FROM dba_hist_active_sess_history WHERE sql_id=:V1 AND sql_plan_hash_value=:V2) hs,v$event_name b
  WHERE  hs.event_id=b.event_id(+)
  AND    hs.sample_time BETWEEN qry.st AND qry.ed
  GROUP  BY sql_plan_line_id,decode(qry.flag,'dump',current_obj#))
SELECT /*+ordered use_nl(sql_pl ash)*/ distinct ID,LPAD('|', DEPTH,'|')||  operation||' '||options operation, object_name,CPU,"NON-CPU",total,
       (select object_name from dba_objects where object_id=ash.obj) wait_obj,wait_class
FROM   dba_hist_sql_plan sql_pl, ash
WHERE  sql_pl.SQL_ID = :V1
AND    sql_pl.plan_hash_value = :V2
AND    sql_pl.id = ash.line#(+)
ORDER  BY ID
