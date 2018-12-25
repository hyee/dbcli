--Geneate/Show ADDM report in better format.  Usage: @addm [<p1>] [<p2>] [<inst_id>|a] [<dbid>]
--Parameters:
--      p1: Optional, when not specified then list the recent 50 advisor tasks. Can be:
--          1). task_id in DBA_ADVISOR_TASKS, 
--          2). begin snap_id in dba_hist_snapshot
--          3). begin time in YYMMDDHH24MISS format
--      p2: Optional, when not specified then directly print the existing ADDM report whose task_id=<p1>, Can be
--          1). end snap_id in dba_hist_snapshot
--          2). end time in YYMMDDHH24MISS format
--      inst: Optional, when not specified then generate the report across all instances, Can be:
--          1). a or A: generate the report across all instances
--          2). list of instances separated by comma, e.g.: 1,2,3,4
--      dbid: Optional, you'd better specify it in case of target dbid is not the current db's dbid
--            When multiple DBIDs have the snapshots that match <p1> and <p2>
--  
--  If there is an existing ADDM report that matches the input predicates, then will not generate
--  the new report, instead print it directly.
-- 
--  Examples:
--  1) Print existing reports in DBA_ADVISOR_TASKS: @addm 308878
--  2) Generate and print report by time range:     @addm 181010 18101123
--  3) Generate and print report by snap_id:        @addm 123 129
--  4) Generate and print report by snap_id+inst:   @addm 123 129 1,2
--  5) Generate and print report by snap_id+dbid:   @addm 123 129 a 462426730

set serveroutput on lines 2000 arraysize 100 verify off pages 999 feed off recsep off 
set trim on trims on colsep | LONG 80000000 longchunksize 30000
COLUMN 1 NEW_VALUE 1
COLUMN 2 NEW_VALUE 2
COLUMN 3 NEW_VALUE 3
COLUMN 4 NEW_VALUE 4
set termout off
SELECT  '' "1",'' "2",'' "3",'' "4" FROM dual WHERE ROWNUM = 0;
set termout on

col Impact  for a10;
col Target# for a13;
col message for a300;

col task_id for 999999999
col owner   for a10
col TASK_NAME for a30
col AWR_START for a30
col AWR_END   for a30
col dbid      for a10
col INST      for a10
col AWR_MODE  for a15
col FINDINGS  for 99,999,999
col STATUS    for A10
col EXECUTION_START for a19
col EXECUTION_END   for a19
var cur     REFCURSOR;
var res     CLOB;
var dest    VARCHAR2(100);

DECLARE
    st       VARCHAR2(30):='&&1'; --start time or begin_snap
    et       VARCHAR2(30):='&&2'; --end time or end_snap
    inst     VARCHAR2(30):='&&3'; --inst_id or a
    dbid     INT         :='&&4';--dbid
    bid      INT;
    eid      INT;
    btime    DATE;
    etime    DATE;
    taskid   PLS_INTEGER;
    c        PLS_INTEGER;
    taskname varchar2(50);
    advtype  varchar2(100);
    rs       CLOB;
    sq       VARCHAR2(2000);
    PROCEDURE get_range(p_start VARCHAR2,
                        p_end   VARCHAR2,
                        p_inst  VARCHAR2,
                        p_dbid  IN OUT INT, 
                        st OUT INT, 
                        ed OUT INT, 
                        stim OUT DATE, 
                        etim OUT DATE) IS
        s DATE;
        e DATE;
    BEGIN
        BEGIN
            s := to_date(p_start,'YYMMDDHH24MISS');
            e := to_date(p_end,'YYMMDDHH24MISS');
        EXCEPTION WHEN OTHERS THEN
            BEGIN
                s := to_date(p_start);
                e := to_date(p_end);
            EXCEPTION WHEN OTHERS THEN
                BEGIN
                    select dbid,
                           min(end_interval_time),
                           max(end_interval_time)
                    into   p_dbid,s,e
                    from   dba_hist_snapshot
                    where  snap_id in(p_start+0,p_end+0)
                    and    dbid=nvl(p_dbid,dbid)
                    group by dbid
                    having count(distinct snap_id)>1;
                EXCEPTION WHEN OTHERS THEN
                    RAISE_APPLICATION_ERROR(-20001,'Invalid date format or snap_id: "'||p_start||'" or "'||p_end||'"');
                END;
            END;
        END;

        SELECT dbid,least(st,ed) st,greatest(st,ed),least(stim,etim),greatest(stim,etim)
        INTO p_dbid,st,ed,stim,etim
        FROM (
            SELECT max(dbid) dbid,
                   max(st) st,max(ed) ed,
                   max((select nvl(max(end_interval_time+0),s) from Dba_Hist_Snapshot WHERE snap_id=st AND dbid=a.dbid)) stim,
                   max((select nvl(max(end_interval_time+0),e) from Dba_Hist_Snapshot WHERE snap_id=ed AND dbid=a.dbid)) etim
            FROM   (SELECT dbid,
                           nvl(MAX(decode(sign(end_interval_time-3e-4-s),1,null,snap_id)),min(snap_id)) st,
                           nvl(min(decode(sign(end_interval_time+3e-4-e),-1,null,snap_id)),max(snap_id)) ed
                    FROM   Dba_Hist_Snapshot
                    WHERE  begin_interval_time-3e-4 <= e and end_interval_time+3e-4>=s
                    AND    (p_inst IS NULL OR instr(',' || p_inst || ',', instance_number) > 0)
                    AND    dbid=nvl(p_dbid,dbid)
                    GROUP  BY DBID
                    ORDER  BY 2 DESC) a
            WHERE  ROWNUM < 2);

        IF ed IS NULL THEN
            RAISE_APPLICATION_ERROR(-20001,'Cannot find the matched AWR snapshots between '''||s||''' and '''||e||''' for instance#'||p_inst||' !' );
        END IF;
    END;
    
    PROCEDURE extract_addm(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2,taskid OUT INT) IS
        stim     DATE;
        etim     DATE;
        st       INT;
        ed       INT;
        taskname VARCHAR2(30);
        inst     VARCHAR2(30) := NULLIF(p_inst, 'A');
    BEGIN
        IF DBMS_DB_VERSION.VERSION+DBMS_DB_VERSION.release < 13 THEN
            IF inst IS NULL THEN
                inst := USERENV('instance');
            END IF;

            IF INSTR(inst, ',') > 0 THEN
                RETURN;
            END IF;
        END IF;

        get_range(p_start,p_end,inst,dbid,st,ed,stim,etim);
        taskname := 'ADDM_'||dbid||'_'||st||'_'||ed||'_'||nvl(upper(inst),'A');
        
        BEGIN
            dbms_advisor.delete_task(taskname);
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
        dbms_output.put_line('Extracting addm report from ' || st || ' to ' || ed || ' with instance ' || nvl(inst, 'a') || '...');
        $IF DBMS_DB_VERSION.VERSION>11 OR DBMS_DB_VERSION.VERSION>10 AND DBMS_DB_VERSION.release>1 $THEN
            IF inst IS NULL THEN
                DBMS_ADDM.ANALYZE_DB(taskname, st, ed, dbid);
            ELSE
                DBMS_ADDM.ANALYZE_PARTIAL(taskname, inst, st, ed, dbid);
            END IF;
            select max(task_id) into taskid from dba_advisor_tasks where task_name=taskname;
        $ELSE
            dbms_advisor.create_task('ADDM', taskid, taskname, 'ADDM Extraction', NULL);
            dbms_advisor.set_task_parameter(taskname, 'START_SNAPSHOT', st);
            dbms_advisor.set_task_parameter(taskname, 'END_SNAPSHOT', ed);
            dbms_advisor.set_task_parameter(taskname, 'INSTANCE', inst);
            dbms_advisor.set_task_parameter(taskname, 'DB_ID', dbid);
            dbms_advisor.execute_task(taskname);
        $END
    END;
BEGIN
    
    
    IF st IS NULL THEN
        OPEN :cur FOR
            WITH r AS(
                SELECT /*+materialize*/ 
                       task_id,owner, task_name, execution_start,execution_end,status,
                       (SELECT COUNT(1) FROM dba_advisor_findings WHERE task_id = a.task_id) findings
                FROM   dba_advisor_tasks a),
            r1 as(
                SELECT task_id,
                       nvl(MAX(DECODE(parameter_name, 'START_TIME', parameter_value)) ||MAX(DECODE(parameter_name, 'START_SNAPSHOT', '(' || parameter_value || ')')),'UNKNOWN') awr_start,
                       nvl(MAX(DECODE(parameter_name, 'END_TIME', parameter_value)) ||MAX(DECODE(parameter_name, 'END_SNAPSHOT', '(' || parameter_value || ')')),'UNKNOWN') awr_end,
                       nvl(MAX(DECODE(parameter_name, 'DB_ID', parameter_value)),'N/A') DBID,
                       nvl(MAX(DECODE(parameter_name, 'INSTANCE', parameter_value)),'N/A') INST,
                       nvl(MAX(DECODE(parameter_name, 'MODE', parameter_value)),'N/A') AWR_MODE
                FROM   R join DBA_ADVISOR_PARAMETERS using(task_id)
                GROUP  BY task_id)
            SELECT * FROM (
                SELECT TASK_ID,substr(R.OWNER,1,10) owner,
                       R.TASK_NAME,R1.AWR_START,R1.AWR_END,r1.dbid,R1.INST,
                       R1.AWR_MODE,r.findings,r.status,
                       to_char(r.execution_start,'yyyy-mm-dd hh24:mi:ss') execution_start,
                       to_char(r.execution_end,'yyyy-mm-dd hh24:mi:ss') execution_end
                FROM   R LEFT JOIN R1 USING(TASK_ID)
                ORDER  BY execution_start DESC NULLS LAST)
            WHERE rownum<=50;
    ELSE
        --Run ADDM if specified the begin_time/begin_snap_id and end_time/end_snap_id  
        IF st IS NOT NULL AND et IS NOT NULL THEN
            get_range(st,et,inst,dbid,bid,eid,btime,etime);
            --Check if the matched ADDM report has been generated
            SELECT max(task_id)
            INTO   bid 
            FROM (
                select TASK_ID,count(1) cnt
                from   Dba_Advisor_Parameters
                WHERE (parameter_name='DB_ID' AND parameter_value=''||dbid
                OR     parameter_name='INSTANCES' AND parameter_value=decode(upper(inst),'A','UNUSED','','UNUSED', inst)
                OR     parameter_name='START_SNAPSHOT' AND parameter_value=''||bid
                OR     parameter_name='END_SNAPSHOT' AND parameter_value=''||eid)
                AND    TASK_NAME LIKE 'ADDM%'
                GROUP  by task_id
                HAVING count(1)>3
                ORDER BY cnt desc
            ) WHERE rownum<2;
            
            IF bid IS NULL THEN
                extract_addm(btime, etime, inst,st);
            ELSE
                st := bid;
            END IF;
        END IF;
        
        select max(ADVISOR_NAME),max(task_name),max(owner) 
        into advtype,taskname,sq 
        FROM DBA_ADVISOR_TASKS 
        where task_id=regexp_substr(st,'\d+');
        
        IF taskname IS NULL THEN
            OPEN :cur for select 'No such task' message from dual;
        ELSIF advtype LIKE 'Segment%' THEN
            OPEN :cur for 'select * from table(SYS.DBMS_SPACE.ASA_RECOMMENDATIONS) where task_id=:task_id' using st;
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
            SELECT COUNT(1) INTO c 
            FROM ALL_OBJECTS 
            WHERE OBJECT_NAME IN('DBMS_ADDM','DBMS_ADVISOR') AND OWNER='SYS';
            OPEN :cur for
                WITH act AS(SELECT /*+materialize*/ action_id,task_id,command,command_id,message,rec_id,object_id,
                                    nvl2(attr1,trim(attr1||nvl2(attr2,'.'||attr2,'')||nvl2(attr3,'.'||attr3,'')),'') obj,
                                    to_char(nullif(NUM_ATTR1,0)) obj_id
                            FROM DBA_ADVISOR_ACTIONS WHERE task_id = st),
                A AS
                 (SELECT --+materialize ordered use_nl(a b c d) no_merge(b) no_merge(c) no_merge(d) push_pred(b) push_pred(c) push_pred(d
                       dense_rank() OVER(ORDER BY impact DESC, a.message || a.more_info ASC) r, 
                       row_number() OVER(partition by impact , a.message || a.more_info order by b.rank desc) r2,
                       row_number() OVER(PARTITION BY impact , a.message || a.more_info,b.rank ORDER BY c.action_id ) r1, 
                       a.finding_id, b.rec_id,
                       a.task_id, c.action_id, SUM(DISTINCT a.impact) OVER(PARTITION BY a.finding_id) impact,
                       REPLACE(trim(chr(10) from a.message || chr(10)||a.more_info), chr(10), chr(10) || lpad(' ', 13)) findmsg,
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
                                       regexp_replace(listagg(replace(e.message,chr(0)),chr(10)) within group(order by e.message),CHR(10)||',*',chr(10) || LPAD(' ', 15)),
                                       chr(10))
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
                  AND    A.task_id = st),
                B AS
                 (SELECT --+materialize no_merge(a) no_merge(b) ordered use_nl(b)
                  DISTINCT a.r r1, DECODE(SIGN(b.r - 1), 1, rec_id, -9) R2,
                           DECODE(SIGN(b.r - 2), 1, NVL2(rationale_msg, -1, action_cmdid), -9) r3,
                           DECODE(SIGN(b.r - 3), 1, action_cmdid, -9) r4,
                           trim(trailing chr(10) from rpad(' ', LEAST(b.r - 1, 2) * 2) ||DECODE(b.r,
                                   1,case when a.r2=1 then 'Finding #' || lpad(a.r,2,'0') || ': ' || FINDMSG end,
                                   2,case when a.r1=1 then remgroup end,
                                   3,nvl(case when a.r1=1 then rationale_msg else ' ' end, action_msg),
                                   4,action_msg)) "Message",
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
                    select r1,r2,r3,r4,is_top,
                           "Impact",
                           "Target#",
                           "Message"
                    FROM   b
                    where  trim("Message") is not null 
                    union all
                    select distinct r1,99,99,99,null,RPAD('_',8,'_'),RPAD('_',max(length("Target#")) over(),'_'),RPAD('_',300,'_') from b
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
    
    IF :dest IS NOT NULL THEN
        dbms_output.put_line('Result is saving to '||sqlerrm);
    END IF;
END;
/

undef 1
undef 2
undef 3
undef 4
print cur;
set colsep " "
set termout off pages 0
col fname new_value fname
select :dest fname from dual;
spool &fname.
SELECT :res addm_report from dual;
spool off
set termout on pages 999