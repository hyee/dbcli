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
SELECT a.sid||','||a.serial#||',@'||a.inst_id session#,
       (select spid from gv$process d where d.inst_id=a.inst_id and d.addr=a.paddr)||regexp_substr(program,'\(.*\)') spid,       
       a.sql_id,
       b.plan_hash_value plan_hash,
       a.event,&V9,
       ROUND(&COST,1) waits,
       substr(regexp_replace(to_char(SUBSTR(b.sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,120) sql_text
FROM   gv$session a, gv$sqlarea b, dba_objects c
WHERE  a.sql_id = b.sql_id(+)
AND    a.inst_id = b.inst_id(+)
AND    a.sid!=USERENV('SID')
and    a.audsid!=userenv('sessionid')
AND    b.PROGRAM_ID = c.object_id(+)
AND    a.status = 'ACTIVE'
--and    event not like '%idle%'
AND    (NVL(a.wait_class,'x')!='Idle' or a.sql_id is not null)
order by &V1