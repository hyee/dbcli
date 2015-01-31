/*[[
Show active sessions. Usage: ora actives [-s|-p|-b] [waits|sid|sql|pkg|other field]
    --[[
        &fields : {
               s={coalesce(nullif(program_name,'0'),'['||regexp_replace(nvl(a.module,a.program),' *\(.*\)$')||'('||osuser||')]') PROGRAM,PROGRAM_LINE# line#},
               p={p1,p2,p2text,p3},
               b={NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCK_BY,
                 (SELECT OBJECT_NAME FROM ALL_OBJECTS WHERE OBJECT_ID=ROW_WAIT_OBJ# AND ROWNUM<2) WAITING_OBJ,
                 ROW_WAIT_BLOCK# WAIT_BLOCK#}
              }
        &V1 : sid={''||sid},wt={waits desc},ev={event},sql={sql_text}   
        @COST : 11.0={nvl(1440*(sysdate-SQL_EXEC_START),wait_secs/60)},10.0={LAST_CALL_ET/60},9.0={null}
    ]]--      
]]*/

set feed off

VAR OBJECTS CURSOR

WITH s1 AS
 (SELECT /*+no_merge*/*
  FROM   gv$session
  WHERE  sid != USERENV('SID')
  AND    audsid != userenv('sessionid')
  --And    (event not like 'Streams%' and event not in('rdbms ipc message'))
  AND    (NVL(wait_class, 'x') != 'Idle' OR sql_id IS NOT NULL)),
s2 AS
 (SELECT /*+no_merge*/* FROM gv$px_session WHERE  NOT (SID = qcsid AND inst_id = qcinst_id)),
s3 AS
 (SELECT /*+no_merge*/ * FROM s1 LEFT JOIN s2 USING (inst_id, SID, serial#)),
sq1 as(
 SELECT /*+materialize ordered use_nl(a b)*/ a.*,
       extractvalue(b.column_value,'/ROW/A1')     program_name,
       extractvalue(b.column_value,'/ROW/A2')     PROGRAM_LINE#,
       extractvalue(b.column_value,'/ROW/A3')     sql_text,
       extractvalue(b.column_value,'/ROW/A4')     plan_hash_value
 FROM (select distinct inst_id,sql_id,nvl(sql_child_number,0) child from s1 where sql_id is not null) A,
       TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'[
           SELECT (select c.owner  ||'.' || c.object_name from all_objects c where c.object_id=PROGRAM_ID and rownum<2) A1,
                  PROGRAM_LINE# A2,
                  substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) A3,
                  plan_hash_value A4
           FROM  gv$sql
           WHERE ROWNUM<2 AND sql_id=']'||a.sql_id||''' AND inst_id='||a.inst_id||' and child_number='||a.child)
       ,'/ROWSET/ROW'))) B
),         
s4 AS
 (SELECT /*+materialize no_merge(s3)*/
       DECODE(LEVEL, 1, '', '  ') || SID NEW_SID,
       decode(LEVEL, 1, sql_id) new_sql_id,
       rownum r,
       s3.*
  FROM   (SELECT s3.*,
                 CASE WHEN seconds_in_wait > 1300000000 THEN 0 ELSE seconds_in_wait END wait_secs,
                 plan_hash_value,          
                 program_name,
                 program_line#,
                 sql_text
          FROM   s3, sq1
          WHERE  s3.inst_id=sq1.inst_id(+) and s3.sql_id=sq1.sql_id(+) and nvl(s3.sql_child_number,0)=sq1.child(+)) s3
  START  WITH qcsid IS NULL
  CONNECT BY qcsid = PRIOR SID
      AND    qcinst_id = PRIOR inst_id
      AND    LEVEL < 3
  ORDER SIBLINGS BY &V1)
SELECT /*+cardinality(a 1)*/ 
       r "#",
       a.NEW_SID || ',' || a.serial# || ',@' || a.inst_id session#,
       (SELECT spid
        FROM   gv$process d
        WHERE  d.inst_id = a.inst_id
        AND    d.addr = a.paddr) || regexp_substr(program, '\(.*\)') spid,
       a.sql_id,
       plan_hash_value plan_hash,
       sql_child_number child,
       a.event,&fields,
       ROUND(&COST,1) waits,
       sql_text
FROM   s4 a
WHERE  wait_class!='Idle' or sql_text is not null
ORDER  BY r;
