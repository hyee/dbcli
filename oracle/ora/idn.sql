/*[[Find SQL/Object of a specific idn in gv$/dba_hist views. Usage: @@NAME <idn|sql_id>
    When input value is SQL Id then convert to hash_value(idn)
    When input value is idn then query all possible views
    --[[
        @ARGS:1 
        @dbid: 12.2={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
    --]]
]]*/
set feed off
var c refcursor
DECLARE
    sq_id VARCHAR2(30) := lower(:v1);
    idn   INT := regexp_substr(sq_id, '^\d+$');
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

        dbms_output.put_line('Target SQL Id: '''||sq_id||'''');
        dbms_output.put_line('========================');
        --Can also use filter:  WHERE dbms_utility.sqlid_to_sqlhash(sql_id) = idn
        OPEN :c FOR
            SELECT /*+PQ_CONCURRENT_UNION(@SET$1)*/
                   NAMESPACE, nvl(owner,'GV$DB_OBJECT_CACHE') own, regexp_replace(NAME, '\s+', ' ') NAME
            FROM   gv$db_object_cache
            WHERE  hash_value = idn
            UNION ALL
            SELECT 'GV$SQLAREA', sql_id, regexp_replace(substr(sql_text,1,1500), '\s+', ' ') NAME
            FROM   gv$sqlarea_plan_hash
            WHERE  hash_value = idn
            UNION ALL
            SELECT 'DBA_HIST_SQLTEXT', sql_id, regexp_replace(to_char(substr(sql_text, 1, 1500)), '\s+', ' ') NAME
            FROM   dba_hist_sqltext
            WHERE  sql_id like sq_id
            AND    dbid = nvl(:dbid, '&dbid')
            UNION ALL
            SELECT 'DBA_HIST_SQLTEXT', sql_id, regexp_replace(to_char(substr(sql_text, 1, 1500)), '\s+', ' ') NAME
            FROM   dba_sqlset_statements
            WHERE  sql_id like sq_id;
    ELSE
        --ref: https://tanelpoder.com/2009/02/22/sql_id-is-just-a-fancy-representation-of-hash-value
        dbms_output.put_line('Manually idn calculation(Actual is '||dbms_utility.sqlid_to_sqlhash(sq_id)||')');
        dbms_output.put_line('================================================');
        OPEN :c FOR
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
    END IF;
END;
/

      