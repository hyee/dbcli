/*[[Find SQL/Object of a specific idn in gv$/dba_hist views. Usage: @@NAME <idn|sql_id>
    When input value is SQL Id then convert to hash_value(idn)
    When input value is idn then query all possible views
    --[[
        @ARGS:1 
        @dbid: 12.2={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
    --]]
]]*/
set feed off verify off
var c0 refcursor
var c1 refcursor
var m0 varchar2(80);
var m1 varchar2(80);
DECLARE
    sq_id VARCHAR2(30) := lower(:v1);
    idn   INT := regexp_substr(sq_id, '^\d+$');
    c SYS_REFCURSOR;
    PROCEDURE load_idn IS
    BEGIN 
        :m1 :='Target SQL Id: '''||sq_id||'''';
        --Can also use filter:  WHERE dbms_utility.sqlid_to_sqlhash(sql_id) = idn
        OPEN c FOR
            SELECT DISTINCT DECODE(C,1,''||inst,'*') inst,NAMESPACE,OWN,TRIM(NAME) NAME
            FROM (
                SELECT /*+PQ_CONCURRENT_UNION monitor*/ A.*,COUNT(1) OVER(PARTITION BY NAMESPACE,OWN,TRIM(NAME)) C
                FROM (
                    SELECT inst_id inst,NAMESPACE, nvl(owner,'GV$DB_OBJECT_CACHE') own, substr(regexp_replace(NAME, '\s+', ' '),1,300) NAME
                    FROM   gv$db_object_cache
                    WHERE  hash_value = idn
                    UNION ALL
                    SELECT inst_id inst,'GV$SQLAREA', sql_id, regexp_replace(substr(sql_text,1,300), '\s+', ' ') NAME
                    FROM   gv$sqlarea_plan_hash
                    WHERE  hash_value = idn
                    UNION ALL
                    SELECT inst_id inst,'GV$SQL_MONITOR', sql_id, regexp_replace(substr(sql_text,1,300), '\s+', ' ') NAME
                    FROM   gv$sql_monitor
                    WHERE  sql_id like sq_id
                    AND    SQL_TEXT IS NOT NULL
                    AND    PX_SERVER# IS NULL
                    UNION ALL
                    SELECT dbid,'DBA_HIST_SQLTEXT', sql_id, regexp_replace(to_char(substr(sql_text, 1, 300)), '\s+', ' ') NAME
                    FROM   dba_hist_sqltext
                    WHERE  sql_id like sq_id
                    AND    dbid = nvl(:dbid, '&dbid')
                    UNION ALL
                    SELECT sqlset_id,'DBA_HIST_SQLTEXT', sql_id, regexp_replace(to_char(substr(sql_text, 1, 300)), '\s+', ' ') NAME
                    FROM   dba_sqlset_statements
                    WHERE  sql_id like sq_id
                    UNION ALL
                    SELECT /*+use_concat*/
                           inst_id,'GV$OBJECT_DEPENCY',
                           decode(idn,from_hash,'.FROM_HASH','.TO_HASH'),
                           rpad(trim('.' from to_owner||'.'||to_name),40,' ')||' | '
                               || decode(idn,from_hash,'TO_HASH   = '||to_hash,
                                'FROM_HASH = '||from_hash)
                    FROM   gv$object_dependency
                    WHERE  idn in(from_hash,to_hash)) A
            )
            ORDER BY 2,3,4,1;
    END;
BEGIN
    IF idn>0 THEN
        SELECT '%' || listagg(x, '') within GROUP(ORDER BY lv DESC)
        INTO   sq_id
        FROM   (SELECT rownum lv,
                       substr('0123456789abcdfghjkmnpqrstuvwxyz',
                              trunc(MOD(idn + power(2, 32), power(32, rownum)) / power(32, rownum - 1)) + 1,
                              1) x
                FROM   dual
                CONNECT BY rownum < 7);
        load_idn;
    ELSE
        --ref: https://tanelpoder.com/2009/02/22/sql_id-is-just-a-fancy-representation-of-hash-value
        idn := dbms_utility.sqlid_to_sqlhash(sq_id);
        :m0 := 'Manual idn calculation(Actual as '||idn||')';
        OPEN :c0 FOR
            SELECT A.*,
                   listagg(c2,'') within group(order by lv) over() piece
            FROM (
                SELECT A.*,
                       CASE WHEN lv>6 THEN
                           substr('0123456789abcdfghjkmnpqrstuvwxyz',
                                  mod("HV Calc from 7#"+pow,power(32, len + 1 - lv))/power(32, len - lv)+1,1) 
                       END c2
                FROM (
                    SELECT sq_id sql_id,
                           len,
                           lv,
                           SUM(p*power(32, len - lv)) OVER(ORDER BY lv) "Sum",
                           trunc(SUM(p*power(32, len - lv)) OVER(ORDER BY lv)/pow) high,
                           decode(lv,len,'* $HIY$','  ')||trunc(MOD(SUM(p * power(32, len - lv)) OVER(ORDER BY lv),pow))||decode(lv,len,'$NOR$') "HASH_VALUE(idn)",
                           trunc(MOD(SUM(case when lv>6 then p * power(32, len - lv) end) OVER(ORDER BY lv), pow)) "HV Calc from 7#",
                           pow,
                           p,
                           '|' "|",
                           substr(sq_id, lv, 1) c
                    FROM   (SELECT level lv,
                                   length(sq_id) len,
                                   instr('0123456789abcdfghjkmnpqrstuvwxyz', substr(sq_id, level, 1)) - 1 p,
                                   power(2, 32) pow
                            FROM dual 
                            connect by level<=length(sq_id))) A)A
            ORDER BY lv;
        load_idn;
    END IF;

    :c1 := c;
END;
/

print c0 "&m0"
print c1 "&m1"
      