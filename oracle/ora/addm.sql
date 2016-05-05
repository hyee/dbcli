/*[[Show existing ADDM report. Usage: @@NAME [task_id] [-f"<filter>"]
    --[[
        &filter: default={1=1}, f={}
        @VER   : 11.2={listagg(e.message,chr(10)) within group(order by e.message)} default={to_char(wmsys.wm_concat(e.message || CHR(10)))}
    --]]
]]*/
SET FEED OFF printvar off
var cur refcursor;
var res CLOB;
VAR DEST VARCHAR2;
DECLARE
    c PLS_INTEGER;
    taskname varchar2(50);
    rs CLOB;
    sq VARCHAR2(2000);
BEGIN
    IF :V1 IS NULL THEN
        OPEN :cur FOR
            WITH r AS(
                SELECT /*+materialize*/ task_id,owner, task_name, execution_start,execution_end,status,(SELECT COUNT(1) FROM dba_advisor_findings WHERE task_id = a.task_id) findings
                FROM   dba_advisor_tasks a
                WHERE  advisor_name = 'ADDM'),
            r1 as(
                SELECT task_id,
                       MAX(DECODE(parameter_name, 'START_TIME', parameter_value)) ||MAX(DECODE(parameter_name, 'START_SNAPSHOT', '(' || parameter_value || ')')) awr_start,
                       MAX(DECODE(parameter_name, 'END_TIME', parameter_value)) ||MAX(DECODE(parameter_name, 'END_SNAPSHOT', '(' || parameter_value || ')')) awr_end,
                       MAX(DECODE(parameter_name, 'INSTANCE', parameter_value)) INST,
                       MAX(DECODE(parameter_name, 'MODE', parameter_value)) AWR_MODE
                FROM   DBA_ADVISOR_PARAMETERS
                WHERE  task_id IN (SELECT TASK_ID FROM R)
                GROUP  BY task_id)
            SELECT R.TASK_ID,R.OWNER,R.TASK_NAME,R1.AWR_START,R1.AWR_END,R1.INST,R1.AWR_MODE,r.findings,r.status,r.execution_start,r.execution_end
            FROM   R,R1 WHERE R.TASK_ID=R1.TASK_ID AND &FILTER
            ORDER  BY execution_start DESC NULLS LAST;
    ELSE
        SELECT COUNT(1) INTO c FROM ALL_OBJECTS WHERE OBJECT_NAME IN('DBMS_ADDM','DBMS_ADVISOR') AND OWNER='SYS';
        OPEN :cur for
            WITH act AS(SELECT /*+materialize*/ action_id,task_id,command,command_id,message,rec_id,object_id FROM DBA_ADVISOR_ACTIONS WHERE task_id = :V1),
            A AS
             (SELECT --+materialize ordered use_nl(a b c d) no_merge(b) no_merge(c) no_merge(d) push_pred(b) push_pred(c) push_pred(d
                   dense_rank() OVER(ORDER BY impact DESC, a.message || a.more_info ASC) r, 
                   row_number() OVER(partition by impact , a.message || a.more_info order by b.rank desc) r2,
                   row_number() OVER(PARTITION BY impact , a.message || a.more_info,b.rank ORDER BY c.action_id ) r1, 
                   a.finding_id, b.rec_id,
                   a.task_id, c.action_id, SUM(DISTINCT a.impact) OVER(PARTITION BY a.finding_id) impact,
                   REPLACE(a.message || chr(10)||a.more_info, chr(10), chr(10) || lpad(' ', 13)) findmsg,
                   nvl2(b.rank,'Advise #' || b.rank || ': ' || b.type,'') remgroup, b.benefit rembenefit,
                   (SELECT parameter_value
                    FROM   Dba_Advisor_Parameters f
                    WHERE  parameter_name = 'DB_ELAPSED_TIME'
                    AND    f.task_id = a.task_id) elapsed,
                   (SELECT MAX(decode(f.message#, 388, f.p2 * f.p3 * 1e6))
                     FROM   sys.wri$_adv_rationale e, sys.wri$_adv_message_groups f
                     WHERE  f.task_id = E.task_id
                     AND    e.task_id = b.task_id
                     AND    e.rec_id = b.rec_id
                     AND    f.id = e.msg_id) remimpact,
                   (SELECT RTRIM(NVL2(MAX(E.task_id), 'Rationale: ', '') ||
                                   REPLACE(&VER,CHR(10),chr(10) || LPAD(' ', 15)),
                                   chr(0) || chr(10))
                     FROM   DBA_ADVISOR_RATIONALE e
                     WHERE  B.task_id = E.task_id
                     AND    B.rec_id = E.rec_id) remreason, c.command remcommand, c.command_id remcommandid,
                     nvl2(c.message, 'Action: ', '') || c.message remmessage, d.object_id, d.type target,
                     d.attr1 target_id, d.attr2 sql_plan_id, to_char(substr(d.attr4,1,3000)) sql_text
              FROM   DBA_ADVISOR_FINDINGS a, DBA_ADVISOR_RECOMMENDATIONS b, ACT C,
                     DBA_ADVISOR_OBJECTS D
              WHERE  A.task_id = B.task_id(+)
              AND    A.finding_id = B.finding_id(+)
              AND    B.task_id = C.task_id(+)
              AND    B.rec_id = C.rec_id(+)
              AND    C.task_id = D.task_id(+)
              AND    C.object_id = D.object_id(+)
              AND    A.task_id = :V1),
            B AS
             (SELECT --+materialize no_merge(a) no_merge(b) ordered use_nl(b)
              DISTINCT a.r r1, DECODE(SIGN(b.r - 1), 1, rec_id, -9) R2,
                       DECODE(SIGN(b.r - 2), 1, NVL2(remreason, -1, remcommandid), -9) r3,
                       DECODE(SIGN(b.r - 3), 1, remcommandid, -9) r4,
                       rpad(' ', LEAST(b.r - 1, 2) * 2) ||DECODE(b.r,
                               1,case when a.r2=1 then 'Finding #' || lpad(a.r,2,'0') || ': ' || FINDMSG end,
                               2,case when a.r1=1 then remgroup end,
                               3,nvl(remreason, remmessage),
                               4,remmessage,
                               5,RPAD('--SQL-TEXT--',200,'-') ) "Message",
                       round(DECODE(b.r, 1, IMPACT, 2, rembenefit, 3, remimpact) * 1e-6 / 60, 2) "Minutes",
                       rpad(' ', LEAST(b.r - 1, 2)) ||nullif(to_char(DECODE(b.r, 1, IMPACT, 2, rembenefit, 3, nvl(remimpact,rembenefit)) * 100 /a.elapsed,'fm990.00')||'%','%') "Impact", 
                       DECODE(b.r, 4, target) "Target Obj",
                       DECODE(b.r, 4, target_id) "Target ID", DECODE(b.r, 4, sql_plan_id) "Plan Hash",
                       decode(b.r,1,a.r) is_top,
                       a.target,a.target_id,a.sql_text,max(nvl(remimpact,rembenefit)*100/elapsed) over(partition by target_id) item_impact
              FROM   a, (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM <= 4) b
              WHERE  b.r - 2 <= NVL2(a.remreason, 1, 0) + NVL2(a.remmessage, 1, 0) - NVL2(a.rec_id, 0, 1)
              ORDER  BY 1, 2, 3, 4)
            SELECT "Impact", "Target ID", "Message"
            from (
                select r1,r2,r3,r4,is_top,"Impact", "Target ID", "Message"
                FROM   b
                where  trim("Message") is not null
                UNION ALL
                select distinct r1,99,99,99,null,RPAD('-',7,'-'),RPAD('-',14,'-'),RPAD('-',300,'-') from b
                order by 1,2,3,4)
            UNION ALL
            select to_char(impact,'fm990.00')||'%',target_id,sql_text from (
                SELECT distinct 
                       item_impact impact, target_id,
                       trim(to_char(substr(regexp_replace(REPLACE(sql_text, chr(0)),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,300))) sql_text
                FROM   b
                WHERE  target='SQL'
                order by impact desc);
        IF c > 0 THEN
            SELECT MAX(TASK_NAME) INTO taskname from DBA_ADVISOR_TASKS where task_id=:V1;
        $IF DBMS_DB_VERSION.VERSION > 10 $THEN
            sq := 'BEGIN :rs := DBMS_ADDM.GET_REPORT(:rtask);END;';
        $ELSE
            sq := q'[BEGIN :rs := dbms_advisor.get_task_report(:rtask, 'TEXT', 'ALL');END;]';
        $END
        BEGIN
            EXECUTE IMMEDIATE sq using out rs, taskname;
            :dest := replace(taskname,':','_')||'.txt';
            :res  := rs;
        EXCEPTION WHEN OTHERS THEN
            dbms_output.put_line('Cannot extract ADDM report into file because of '||sqlerrm);
        END;
        END IF;
    END IF;
END;
/
print cur
PRO
save res dest