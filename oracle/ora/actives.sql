/*[[
Show active sessions. Usage: ora actives [-s|-p|-b] [waits|sid|sql|pkg|other field]
--[[
Templates:
    &V9 : {s={coalesce(NULLIF(c.owner  ||'.' || c.object_name,'.'),
                  nullif(''||PROGRAM_ID,'0'),'['||nvl(a.module,a.program)||'('||osuser||')]') pkg_name,
              PROGRAM_LINE# pkg_line},
           p={p1,p2,p2text,p3},
           b={NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCKING_SID,
             NVL((SELECT OBJECT_NAME FROM ALL_OBJECTS WHERE OBJECT_ID=ROW_WAIT_OBJ# AND ROWNUM<2),''||ROW_WAIT_OBJ#) WAIT_OBJ,
             ROW_WAIT_BLOCK# WAIT_BLOCK#}
          }
    &V1 : sid={''||sid},wt={waits desc},ev={event},sql={sql_text}   
Executable:
    @COST : 11.0={nvl(1440*(sysdate-SQL_EXEC_START),wait_secs/60)},10.0={wait_secs/60},9.0={null}
]]--      
]]*/

set feed off

VAR OBJECTS CURSOR

DECLARE
    sqls sys.dbms_debug_vc2coll := sys.dbms_debug_vc2coll();
    cur  SYS_REFCURSOR;
BEGIN
    --use loop instead of join to avoid full scan on gv$sqlarea
    FOR r IN (SELECT DISTINCT inst_id,sql_id FROM gv$session WHERE sql_id IS NOT NULL) LOOP
        IF sqls.count = 0 OR sqls(sqls.count) IS NOT NULL THEN
            sqls.extend;
        END IF;
        SELECT MAX(inst_id||'-'||sql_id || ':' || nvl(plan_hash_value,0) || ':' || nvl(program_id,0) || ':' || nvl(PROGRAM_LINE#,0) || ':' ||
                   substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200))
        INTO   sqls(sqls.count)
        FROM   gv$sqlarea
        WHERE  sql_id = r.sql_id AND inst_id=r.inst_id
        AND    ROWNUM < 2;
    END LOOP;

    OPEN cur FOR
        WITH s1 AS
         (SELECT /*+no_merge*/*
          FROM   gv$session
          WHERE  sid != USERENV('SID')
          AND    audsid != userenv('sessionid')
          AND    status = 'ACTIVE'
          AND    (NVL(wait_class, 'x') != 'Idle' OR sql_id IS NOT NULL)),
        s2 AS
         (SELECT /*+no_merge*/
           *
          FROM   gv$px_session
          WHERE  NOT (SID = qcsid AND inst_id = qcinst_id)),
        s3 AS
         (SELECT /*+no_merge*/ * FROM s1 LEFT JOIN s2 USING (inst_id, SID, serial#)),
        s4 AS
         (SELECT /*+materialize*/
           DECODE(LEVEL, 1, '', '  ') || SID NEW_SID,
           decode(LEVEL, 1, sql_id) new_sql_id,
           rownum r,
           s3.*
          FROM   (SELECT s3.*,CASE WHEN seconds_in_wait > 1300000000 THEN 0 ELSE seconds_in_wait END wait_secs,
                         regexp_substr(sq.object_value, '[^:]+', 1, 2) plan_hash_value,          
                         regexp_substr(sq.object_value, '[^:]+', 1, 3) program_id,
                         regexp_substr(sq.object_value, '[^:]+', 1, 4) program_line#,
                         regexp_replace(sq.object_value,'^([^:]+:){2,4}') sql_text
                  FROM   s3, TABLE(sqls) sq
                  WHERE  regexp_like(sq.object_value(+), '^' ||  s3.inst_id||'-'||s3.sql_id || ':')) s3
          START  WITH qcsid IS NULL
          CONNECT BY qcsid = PRIOR SID
              AND    qcinst_id = PRIOR inst_id
              AND    LEVEL < 3
          order SIBLINGS BY &V1)
        SELECT r "#",
               a.NEW_SID || ',' || a.serial# || ',@' || a.inst_id session#,
               (SELECT spid
                FROM   gv$process d
                WHERE  d.inst_id = a.inst_id
                AND    d.addr = a.paddr) || regexp_substr(program, '\(.*\)') spid,
               a.sql_id,
               plan_hash_value plan_hash,
               a.event,&V9,
               ROUND(&COST,1) waits,
               sql_text
        FROM   s4 a, dba_objects c
        WHERE  a.PROGRAM_ID = c.object_id(+)
        ORDER  BY r;
     :OBJECTS := cur;
END;
/