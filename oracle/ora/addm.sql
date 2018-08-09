/*[[Show existing ADDM report. Usage: @@NAME [task_id] [-f"<filter>"]
    --[[
        @ALIAS : adv
        &filter: default={1=1}, f={}
        @VER   : 11.2={listagg(e.message,chr(10)) within group(order by e.message)} default={to_char(wmsys.wm_concat(e.message || CHR(10)))}
    --]]
]]*/
SET FEED OFF VERIFY off COLSEP |
col ALLOCATED_SPACE FORMAT kmg
col USED_SPACE FORMAT kmg
col RECLAIMABLE_SPACE FORMAT kmg
var cur refcursor;
var res CLOB;
VAR DEST VARCHAR2;
DECLARE
    c PLS_INTEGER;
    taskname varchar2(50);
    advtype  varchar2(100);
    rs CLOB;
    sq VARCHAR2(2000);
BEGIN
    IF :V1 IS NULL THEN
        OPEN :cur FOR
            WITH r AS(
                SELECT /*+materialize*/ 
                       task_id,owner, task_name, execution_start,execution_end,status,
                       (SELECT COUNT(1) FROM dba_advisor_findings WHERE task_id = a.task_id) findings
                FROM   dba_advisor_tasks a),
            r1 as(
                SELECT task_id,
                       MAX(DECODE(parameter_name, 'START_TIME', parameter_value)) ||MAX(DECODE(parameter_name, 'START_SNAPSHOT', '(' || parameter_value || ')')) awr_start,
                       MAX(DECODE(parameter_name, 'END_TIME', parameter_value)) ||MAX(DECODE(parameter_name, 'END_SNAPSHOT', '(' || parameter_value || ')')) awr_end,
                       MAX(DECODE(parameter_name, 'INSTANCE', parameter_value)) INST,
                       MAX(DECODE(parameter_name, 'MODE', parameter_value)) AWR_MODE
                FROM   DBA_ADVISOR_PARAMETERS
                WHERE  task_id IN (SELECT TASK_ID FROM R)
                GROUP  BY task_id)
            SELECT TASK_ID,R.OWNER,R.TASK_NAME,R1.AWR_START,R1.AWR_END,R1.INST,R1.AWR_MODE,r.findings,r.status,r.execution_start,r.execution_end
            FROM   R LEFT JOIN R1 USING(TASK_ID)
            WHERE  &FILTER
            ORDER  BY execution_start DESC NULLS LAST;
    ELSE
        select max(ADVISOR_NAME),max(task_name),max(owner) into advtype,taskname,sq FROM DBA_ADVISOR_TASKS where task_id=regexp_substr(:V1,'\d+');
        IF taskname IS NULL THEN
            OPEN :cur for select 'No such task' message from dual;
        ELSIF advtype LIKE 'Segment%' THEN
            OPEN :cur for 'select * from table(SYS.DBMS_SPACE.ASA_RECOMMENDATIONS) where task_id=:task_id' using :V1;
        ELSIF advtype LIKE 'Statistics%' THEN
            EXECUTE IMMEDIATE 'BEGIN :rs :=dbms_stats.report_advisor_task(:1);END;' using out rs,taskname;
            OPEN :cur for select rs result from dual;
            :res  := rs;
            :dest := replace(taskname,':','_')||'.txt';
        ELSIF advtype like 'SQL%' THEN
            EXECUTE IMMEDIATE 'BEGIN :rs :=sys.DBMS_SQLTUNE.REPORT_TUNING_TASK(task_name=>:1,owner_name=>:2);END;' using out rs,taskname,sq;
            OPEN :cur for select rs result from dual;
            :res  := rs;
            :dest := replace(taskname,':','_')||'.txt';
        ELSE
            SELECT COUNT(1) INTO c FROM ALL_OBJECTS WHERE OBJECT_NAME IN('DBMS_ADDM','DBMS_ADVISOR') AND OWNER='SYS';
            OPEN :cur for
                WITH act AS(SELECT /*+materialize*/ action_id,task_id,command,command_id,message,rec_id,object_id,
                                    nvl2(attr1,trim(attr1||nvl2(attr2,'.'||attr2,'')||nvl2(attr3,'.'||attr3,'')),'') obj,
                                    to_char(nullif(NUM_ATTR1,0)) obj_id
                            FROM DBA_ADVISOR_ACTIONS WHERE task_id = :V1),
                A AS
                 (SELECT --+materialize ordered use_nl(a b c d) no_merge(b) no_merge(c) no_merge(d) push_pred(b) push_pred(c) push_pred(d
                       dense_rank() OVER(ORDER BY impact DESC, a.message || a.more_info ASC) r, 
                       row_number() OVER(partition by impact , a.message || a.more_info order by b.rank desc) r2,
                       row_number() OVER(PARTITION BY impact , a.message || a.more_info,b.rank ORDER BY c.action_id ) r1, 
                       a.finding_id, b.rec_id,
                       a.task_id, c.action_id, SUM(DISTINCT a.impact) OVER(PARTITION BY a.finding_id) impact,
                       REPLACE(a.message || chr(10)||a.more_info, chr(10), chr(10) || lpad(' ', 13)) findmsg,
                       nvl2(b.rank,'Advise #' || b.rank || ': ' || b.type,'') remgroup, b.benefit,
                       (SELECT nullif(0+parameter_value,0)
                        FROM   Dba_Advisor_Parameters f
                        WHERE  parameter_name = 'DB_ELAPSED_TIME'
                        AND    f.task_id = a.task_id) elapsed,
                       (SELECT nullif(sum(impact),0)
                        FROM   DBA_ADVISOR_RATIONALE e
                        WHERE  B.task_id = E.task_id
                        AND    B.rec_id  = E.rec_id) rationale_impact,
                       (SELECT RTRIM(NVL2(MAX(E.task_id), 'Rationale: ', '') ||
                                       regexp_replace(&VER,CHR(10)||',*',chr(10) || LPAD(' ', 15)),
                                       chr(0) || chr(10))
                         FROM   DBA_ADVISOR_RATIONALE e
                         WHERE  B.task_id   = E.task_id
                         AND    B.rec_id    = E.rec_id
                         ) rationale_msg, c.command action_cmd, c.command_id action_cmdid,
                         nvl2(c.message, 'Action: ', '') || c.message action_msg, d.object_id, d.type target,
                         nvl(d.attr1,nvl2(c.obj,c.obj_id,'')) target_id, d.attr2 sql_plan_id, 
                         nvl(trim(to_char(substr(d.attr4,1,3000))),c.obj) sql_text
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
                           DECODE(SIGN(b.r - 2), 1, NVL2(rationale_msg, -1, action_cmdid), -9) r3,
                           DECODE(SIGN(b.r - 3), 1, action_cmdid, -9) r4,
                           rpad(' ', LEAST(b.r - 1, 2) * 2) ||DECODE(b.r,
                                   1,case when a.r2=1 then 'Finding #' || lpad(a.r,2,'0') || ': ' || FINDMSG end,
                                   2,case when a.r1=1 then remgroup end,
                                   3,nvl(case when a.r1=1 then rationale_msg else ' ' end, action_msg),
                                   4,action_msg) "Message",
                           round(DECODE(b.r, 1, IMPACT, 2, benefit, 3, rationale_impact) * 1e-6 / 60, 2) "Minutes",
                           rpad(' ', LEAST(b.r - 1, 2)) ||nullif(to_char(DECODE(b.r, 1, IMPACT, 2, benefit, 3, nvl(rationale_impact,benefit)) * 100 /a.elapsed,'fm990.00')||'%','%') "Impact", 
                           CASE WHEN b.r>=3 THEN  target end "Target Obj",
                           CASE WHEN b.r>=3 THEN  target_id end "Target#", DECODE(b.r, 4, sql_plan_id) "Plan Hash",
                           decode(b.r,1,a.r) is_top,
                           a.target,a.target_id,a.sql_text,max(nvl(rationale_impact,benefit)*100/elapsed) over(partition by target_id) item_impact
                  FROM   a, (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM <= 4) b
                  WHERE  b.r - 2 <= NVL2(a.rationale_msg, 1, 0) + NVL2(a.action_msg, 1, 0) - NVL2(a.rec_id, 0, 1)
                  ORDER  BY 1, 2, 3, 4)
                SELECT "Impact", "Target#", "Message"
                from (
                    select r1,r2,r3,r4,is_top,"Impact", "Target#", "Message"
                    FROM   b
                    where  trim("Message") is not null
                    UNION ALL
                    select distinct r1,99,99,99,null,RPAD('_',8,'_'),RPAD('_',max(lengthb("Target#")) over(),'_'),RPAD('_',300,'_') from b
                    order by 1,2,3,4)
                UNION ALL
                select RPAD('*',8,'*'),RPAD('*',max(lengthb("Target#")),'*'),RPAD('*',300,'*') from b
                UNION ALL
                select to_char(impact,'fm900.00')||'%',target_id,
                        nvl(sql_text,(select max(owner||'.'||object_name||nullif('.'||subobject_name,'.')) from dba_objects where object_id=regexp_substr(target_id,'^\d+$')))
                from (
                    SELECT max(item_impact) impact, target_id,
                           trim(to_char(substr(regexp_replace(REPLACE(max(sql_text), chr(0)),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,300))) sql_text
                    FROM   b
                    WHERE  target_id is not null
                    group by target_id
                    order by 1 desc);
            IF c > 0 THEN
                BEGIN
                $IF DBMS_DB_VERSION.VERSION > 10 $THEN
                    sq := 'BEGIN :rs := DBMS_ADDM.GET_REPORT(:rtask);END;';
                $ELSE
                    sq := q'[BEGIN :rs := dbms_advisor.get_task_report(:rtask, 'TEXT', 'ALL');END;]';
                $END
                    EXECUTE IMMEDIATE sq using out rs, taskname;
                    :dest := replace(taskname,':','_')||'.txt';
                    :res  := rs;
                EXCEPTION WHEN OTHERS THEN
                    dbms_output.put_line('Cannot extract ADDM report into file because of '||sqlerrm);
                END;
            END IF;
        END IF;
    END IF;
END;
/
print cur
PRO
save res dest