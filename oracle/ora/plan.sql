/*[[
Show execution plan. Usage: plan [-d] <sql_id> [<plan_hash_value>]]]
--[[
    @STAT: 10.1={ALLSTATS LAST outline}
    &SRC: default={0}, d={1}
]]--
]]*/

set feed off

PRO Binding Variables:
PRO ==================

WITH b1 AS
 (SELECT *
  FROM   (SELECT child_number || ':' || INST_ID r,last_captured l
          FROM   gv$sql_bind_capture a
          WHERE  sql_id = :V1
          UNION ALL
          SELECT snap_id || ':' || instance_number r,last_captured l
          FROM   dba_hist_sqlbind a
          WHERE  sql_id = :V1
          ORDER  BY l DESC NULLS LAST)
  WHERE  ROWNUM < 2),
qry AS
 (SELECT NVL2(MAX(last_captured) OVER(),1,3) flag, position, NAME, datatype_string, value_string, inst_id, last_captured
  FROM   gv$sql_bind_capture a, b1
  WHERE  sql_id = :V1
  AND    child_number || ':' || INST_ID = r
  UNION ALL
  SELECT NVL2(MAX(last_captured) OVER(),2,4) flag, position, NAME, datatype_string, value_string, instance_number, last_captured
  FROM   dba_hist_sqlbind, b1
  WHERE  sql_id = :V1
  AND    snap_id || ':' || instance_number = r)
SELECT position,
       NAME,
       datatype_string data_type,       
       nvl2(last_captured,value_string,'<no capture>') VALUE,
       inst_id,
       last_captured
FROM   qry;

WITH sql_plan_data AS
 (SELECT /*+materialize*/*
  FROM   (SELECT a.*,
                 dense_rank() OVER(ORDER BY flag, tm DESC, child_number DESC, plan_hash_value DESC,inst_id) seq
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
                  AND    a.plan_hash_value = nvl(:V2,plan_hash_value)
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
                  AND    a.plan_hash_value = nvl(:V2,plan_hash_value) 
                  ) a
         WHERE flag>&src)
  WHERE  seq = 1),
hierarchy_data AS
 (SELECT id, parent_id, plan_hash_value
  FROM   sql_plan_data
  START  WITH id = 0
  CONNECT BY PRIOR id = parent_id
  ORDER  SIBLINGS BY id DESC),
ordered_hierarchy_data AS
 (SELECT /*+materialize*/
         id,
         parent_id AS pid,
         plan_hash_value AS phv,
         row_number() over(PARTITION BY plan_hash_value ORDER BY rownum DESC) AS OID,
         MAX(id) over(PARTITION BY plan_hash_value) AS maxid
  FROM   hierarchy_data),
qry AS
 (SELECT DISTINCT sql_id sq,
                  flag flag,
                  '&STAT ALL -PROJECTION' format,
                  NVL(child_number, plan_hash_value) plan_hash,
                  inst_id
  FROM   sql_plan_data),
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
 (SELECT /*+ordered use_nl(o) no_merge(x)*/
           rownum AS r,
           x.plan_table_output AS plan_table_output,
           o.id,
           o.pid,
           o.oid,
           o.maxid,
           p.phv,
           COUNT(*) over() AS rc
  FROM   (SELECT DISTINCT phv FROM ordered_hierarchy_data) p
  CROSS  JOIN xplan x
  LEFT   OUTER JOIN ordered_hierarchy_data o
  ON     (o.phv = p.phv AND o.id = CASE
             WHEN regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|') THEN
              to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
         END))
SELECT plan_table_output
FROM   xplan_data --
model  dimension by (phv, rownum as r)
measures (plan_table_output,
         id,
         maxid,
         pid,
         oid,
         greatest(max(length(maxid)) over () + 3, 6) as csize,
         cast(null as varchar2(128)) as inject,
         rc)
rules sequential order (
      inject[phv,r] = case
                         when id[cv(),cv()+1] = 0
                         or   id[cv(),cv()+3] = 0
                         or   id[cv(),cv()-1] = maxid[cv(),cv()-1]
                         then rpad('-', csize[cv(),cv()]*2, '-')
                         when id[cv(),cv()+2] = 0
                         then '|' || lpad('Pid |', csize[cv(),cv()]) || lpad('Ord |', csize[cv(),cv()])
                         when id[cv(),cv()] is not null
                         then '|' || lpad(pid[cv(),cv()] || ' |', csize[cv(),cv()]) || lpad(oid[cv(),cv()] || ' |', csize[cv(),cv()]) 
                      end, 
      plan_table_output[phv,r] = case
                                    when inject[cv(),cv()] like '---%'
                                    then inject[cv(),cv()] || plan_table_output[cv(),cv()]
                                    when inject[cv(),cv()] is not null
                                    then regexp_replace(plan_table_output[cv(),cv()], '\|', inject[cv(),cv()], 1, 2)
                                    else plan_table_output[cv(),cv()]
                                 END
     )
order  by r; 
