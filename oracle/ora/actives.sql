/*[[
Show active sessions. Usage: ora actives [-s|-p|-b] [waits|sid|sql|pkg]
Templates:
    &V9 : {s={coalesce(NULLIF(c.owner  ||'.' || c.object_name,'.'),
                  nullif(''||PROGRAM_ID,'0'),'['||nvl(a.module,a.program)||'('||osuser||')]') pkg_name,
              b.PROGRAM_LINE# pkg_line},
           p={p1,p2,p2text,p3},
           b={NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCKING_SID,
             NVL((SELECT OBJECT_NAME FROM ALL_OBJECTS WHERE OBJECT_ID=ROW_WAIT_OBJ# AND ROWNUM<2),''||ROW_WAIT_OBJ#) WAIT_OBJ,
             ROW_WAIT_BLOCK# WAIT_BLOCK#}
          }
    &V1 : sid={''||sid},wt={waits desc},ev={event},sql={sql_text} 
    
Cross-versions:
    @COST : 11.0={nvl(1440*(sysdate-SQL_EXEC_START),seconds_in_wait/60)},10.0={seconds_in_wait/60},9.0={null}
]]*/
WITH s1 AS(SELECT /*+materialize*/ * FROM gv$session where sid!=USERENV('SID')
           and    audsid!=userenv('sessionid')
           AND    status = 'ACTIVE'
           AND    (NVL(wait_class,'x')!='Idle' or sql_id is not null)),
s2 AS(SELECT /*+materialize*/ * FROM gv$px_session WHERE NOT (SID=qcsid and inst_id=qcinst_id)),
s3 as(SELECT  * FROM s1 LEFT JOIN s2 USING(inst_id,SID,serial#)),
s4 AS (select /*+materialize*/ DECODE(LEVEL,1,'','  ')||SID NEW_SID,decode(level,1,sql_id) new_sql_id,rownum r,s3.* 
      from s3 START WITH qcsid IS NULL 
      CONNECT BY qcsid = PRIOR SID AND qcinst_id=PRIOR inst_id AND LEVEL<3)

SELECT a.NEW_SID||','||a.serial#||',@'||a.inst_id session#,logon_time,
       (select spid from gv$process d where d.inst_id=a.inst_id and d.addr=a.paddr)||regexp_substr(program,'\(.*\)') spid,       
       a.sql_id,
       b.plan_hash_value plan_hash,
       a.event,&V9,
       ROUND(&COST,1) waits,
       substr(regexp_replace(to_char(SUBSTR(b.sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,120) sql_text
FROM   s4 a, gv$sqlarea b, dba_objects c
WHERE  a.new_sql_id = b.sql_id(+)
AND    a.inst_id = b.inst_id(+)
AND    b.PROGRAM_ID = c.object_id(+)
order by r