/*[[
Show execution plan. Usage: plan <sql_id> [<plan_hash_value>]]]
--[[
    @STAT: 10.1={ALLSTATS LAST outline}
--]]
]]*/
WITH qry AS
 (SELECT MAX(sql_id) sq,
         max(flag) flag,
         'ALL -PROJECTION &STAT' format,
         max(inst_id) keep(dense_rank LAST ORDER BY flag,TIMESTAMP,hash) inst_id,
         MAX(hash) KEEP(dense_rank LAST ORDER BY flag,TIMESTAMP) plan_hash
  FROM   (select 2 flag,sql_id,child_number hash,inst_id,TIMESTAMP from gv$sql_plan_statistics_all
          WHERE sql_id=trim(:V1) and plan_hash_value=nvl(:V2,plan_hash_value)
          union all
          select distinct 1 flag,sql_id,plan_hash_value,null,TIMESTAMP from Dba_Hist_Sql_Plan
          WHERE  sql_id = trim(:V1)
          AND    plan_hash_value=nvl(:V2,plan_hash_value)
         )
  )
SELECT a.*
FROM   qry, TABLE(dbms_xplan.display_awr(sq, plan_hash,null,format))  a
where  mod(flag,2)=1
union all
SELECT a.*
FROM   qry, TABLE(dbms_xplan.display('gv$sql_plan_statistics_all',
                                      null,
                                     format,
                                     'child_number='||plan_hash||' and sql_id='''||sq||''' and inst_id='||inst_id
                                     )) a
where  mod(flag,2)=0
