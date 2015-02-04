local db,cfg=env.oracle,env.set
local awr={}

function awr.dump_report(stmt,starttime,endtime,instances)
    if not endtime then 
        return print('Parameters: <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]')
    end

    db:check_date(starttime)
    db:check_date(endtime)

    env.checkerr(db:check_obj('dbms_workload_repository.awr_report_html'),'Sorry, you dont have the "execute" privilege on package "dbms_workload_repository"!')    
    
    local args={starttime,endtime,instances or "",'#VARCHAR','#CLOB','#CURSOR'}
    db:internal_call(stmt,args)
    if args[5] and args[5]~="#CLOB" then
        print("Result written to file "..env.write_cache(args[4],args[5]))
        db.resultset:print(args[6],db.conn)
    else
        print(args[4])
    end
end

function awr.extract_awr(starttime,endtime,instances)
    local stmt=[[
    DECLARE
        rs       CLOB;
        filename VARCHAR2(200);
        cur      SYS_REFCURSOR;
        PROCEDURE extract_awr(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2) IS
            dbid INT;
            stim date;
            etim date;
            st   INT;
            ed   INT;
            inst VARCHAR2(30) := NULLIF(upper(p_inst), 'A');
        BEGIN
        
            IF DBMS_DB_VERSION.VERSION < 11 THEN
                IF inst IS NULL THEN
                    inst := USERENV('instance');
                END IF;
            
                IF INSTR(inst, ',') > 0 THEN
                    RETURN;
                END IF;
            END IF;

            stim := to_date(p_start, 'YYMMDDHH24MI');
            etim := to_date(p_end, 'YYMMDDHH24MI');
        
            SELECT max(dbid),max(st),max(ed),
                   max((select nvl(max(end_interval_time+0),stim) from Dba_Hist_Snapshot WHERE snap_id=st AND dbid=a.dbid)),
                   max((select nvl(max(end_interval_time+0),etim) from Dba_Hist_Snapshot WHERE snap_id=ed AND dbid=a.dbid))
            INTO   dbid, st, ed,stim,etim
            FROM   (SELECT dbid, 
                           nvl(MAX(decode(sign(end_interval_time+0-stim),1,null,snap_id)),min(snap_id)) st, 
                           nvl(min(decode(sign(end_interval_time+0-etim),-1,null,snap_id)),max(snap_id)) ed
                    FROM   Dba_Hist_Snapshot
                    WHERE  begin_interval_time+0 <= etim+0.5 and end_interval_time>=stim-0.5
                    AND    (inst IS NULL OR instr(',' || inst || ',', instance_number) > 0)
                    GROUP  BY DBID
                    ORDER  BY 2 DESC) a
            WHERE  ROWNUM < 2;

            IF ed IS NULL THEN
                filename := 'Cannot find the matched AWR snapshots between '''||stim||''' and '''||etim||''' !' ;            
                RETURN;
            END IF; 
            
            $IF DBMS_DB_VERSION.VERSION>10 $THEN
                 dbms_workload_repository.awr_set_report_thresholds(top_n_sql => 30);
            $END


            filename := 'awr_' || st || '_' || ed || '_' || nvl(inst, 'all') || '.html';
            OPEN cur for 
                select 'AWR' report_type,
                        nvl(inst,'ALL') INSTANCES,
                        to_char(stim,'YYYY-MM-DD HH24:MI') start_time,
                        st begin_snap,
                        to_char(etim,'YYYY-MM-DD HH24:MI') end_time,
                        ed end_snap
                from    dual;
            dbms_lob.createtemporary(rs, TRUE);
            IF NOT (inst IS NULL OR INSTR(inst, ',') > 0) THEN
                FOR r IN (SELECT *
                          FROM   TABLE(dbms_workload_repository.awr_report_html(dbid, inst, st, ed))) LOOP
                    IF r.output IS NOT NULL THEN
                        dbms_lob.writeappend(rs, LENGTHB(r.output), r.output);
                    END IF;
                END LOOP;
                $IF DBMS_DB_VERSION.VERSION>10 $THEN
            ELSE
                FOR r IN (SELECT *
                          FROM   TABLE(dbms_workload_repository.awr_global_report_html(dbid,inst,st,ed))) LOOP
                    IF r.output IS NOT NULL THEN
                        dbms_lob.writeappend(rs, LENGTHB(r.output), r.output);
                    END IF;
                END LOOP;
                $END
            END IF;
        END;
    BEGIN
        extract_awr(:1, :2, :3);
        :4 := filename;
        :5 := rs;
        :6 := cur;
    END;]]
    awr.dump_report(stmt,starttime,endtime,instances)
end

function awr.extract_ash(starttime,endtime,instances)
    local stmt=[[
    DECLARE
        rs       CLOB;
        filename VARCHAR2(200);
        cur      SYS_REFCURSOR;
        PROCEDURE extract_ash(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2) IS
            dbid INT;
            stim date;
            etim date;        
            inst VARCHAR2(30) := NULLIF(upper(p_inst), 'A');
        BEGIN
        
            IF DBMS_DB_VERSION.VERSION < 11 THEN
                IF inst IS NULL THEN
                    inst := USERENV('instance');
                END IF;
            
                IF INSTR(inst, ',') > 0 THEN
                    RETURN;
                END IF;
            END IF;
        
            stim := to_date(p_start, 'YYMMDDHH24MI');
            etim := to_date(p_end, 'YYMMDDHH24MI');
            SELECT MAX(dbid) KEEP(dense_rank LAST ORDER BY begin_interval_time)
            INTO   dbid
            FROM   Dba_Hist_Snapshot
            WHERE  begin_interval_time+0 <= etim+0.5 and end_interval_time>=stim-0.5
            AND    (inst IS NULL OR instr(',' || inst || ',', instance_number) > 0)
            GROUP  BY DBID;
        
            IF dbid IS NULL THEN
                SELECT dbid INTO dbid FROM v$database;
            END IF;    
        
            filename := 'ash_' || p_start || '_' || p_end || '_' || nvl(inst, 'a') || '.html';
            OPEN cur for 
                select 'ASH' report_type,
                        nvl(inst,'ALL') INSTANCES,
                        to_char(stim,'YYYY-MM-DD HH24:MI') start_time,
                        to_char(etim,'YYYY-MM-DD HH24:MI') end_time
                from    dual;
            dbms_lob.createtemporary(rs, TRUE);
            IF NOT (inst IS NULL OR INSTR(inst, ',') > 0) THEN
                FOR r IN (SELECT *
                          FROM   TABLE(dbms_workload_repository.ash_report_html(dbid,
                                                                                inst,
                                                                                stim ,
                                                                                etim ,0,600))) LOOP
                    IF r.output IS NOT NULL THEN
                        dbms_lob.writeappend(rs, LENGTHB(r.output), r.output);
                    END IF;
                END LOOP;
                $IF DBMS_DB_VERSION.VERSION>10 $THEN
            ELSE
                FOR r IN (SELECT *
                          FROM   TABLE(dbms_workload_repository.ash_global_report_html(dbid,
                                                                                       inst,
                                                                                       stim ,
                                                                                       etim ,0,600))) LOOP
                    IF r.output IS NOT NULL THEN
                        dbms_lob.writeappend(rs, LENGTHB(r.output), r.output);
                    END IF;
                END LOOP;
                $END
            END IF;
        END;
    BEGIN
        extract_ash(:1, :2, :3);
        :4 := filename;
        :5 := rs;
        :6 := cur;
    END;]]

    awr.dump_report(stmt,starttime,endtime,instances)
end

function awr.extract_addm(starttime,endtime,instances)
    local stmt=[[
    DECLARE
        rs       CLOB;
        cur      SYS_REFCURSOR;
        filename VARCHAR2(200);
        PROCEDURE extract_addm(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2) IS
            dbid     INT;
            taskid   INT;
            stim     DATE;
            etim     DATE;
            st       INT;
            ed       INT;
            taskname VARCHAR2(30) := 'ADDM_DBCLI_REPORT';
            inst     VARCHAR2(30) := NULLIF(p_inst, 'A');
        BEGIN
        
            IF DBMS_DB_VERSION.VERSION < 11 THEN
                IF inst IS NULL THEN
                    inst := USERENV('instance');
                END IF;
            
                IF INSTR(inst, ',') > 0 THEN
                    RETURN;
                END IF;
            END IF;
        
            stim := to_date(p_start, 'YYMMDDHH24MI');
            etim := to_date(p_end, 'YYMMDDHH24MI');
        
            SELECT max(dbid),max(st),max(ed),
                   max((select nvl(max(end_interval_time+0),stim) from Dba_Hist_Snapshot WHERE snap_id=st AND dbid=a.dbid)),
                   max((select nvl(max(end_interval_time+0),etim) from Dba_Hist_Snapshot WHERE snap_id=ed AND dbid=a.dbid))
            INTO   dbid, st, ed,stim,etim
            FROM   (SELECT dbid, 
                           nvl(MAX(decode(sign(end_interval_time+0-stim),1,null,snap_id)),min(snap_id)) st, 
                           nvl(min(decode(sign(end_interval_time+0-etim),-1,null,snap_id)),max(snap_id)) ed
                    FROM   Dba_Hist_Snapshot
                    WHERE  begin_interval_time+0 BETWEEN stim-0.5 AND etim+0.5
                    AND    (inst IS NULL OR instr(',' || inst || ',', instance_number) > 0)
                    GROUP  BY DBID
                    ORDER  BY 2 DESC) a
            WHERE  ROWNUM < 2;

            IF ed IS NULL THEN
                filename := 'Cannot find the matched AWR snapshots between '''||stim||''' and '''||etim||''' !' ; 
                RETURN;
            END IF;

            BEGIN
                dbms_advisor.delete_task(taskname);
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
            filename := 'addm_' || st || '_' || ed || '_' || nvl(inst, 'a') || '.txt';
            dbms_output.put_line('Extracting addm report from ' || st || ' to ' || ed ||
                                 ' with instance ' || nvl(inst, 'a') || '...');
            dbms_lob.createtemporary(rs, TRUE);
            $IF DBMS_DB_VERSION.VERSION>10 $THEN
                IF inst IS NULL THEN
                    DBMS_ADDM.ANALYZE_DB(taskname, st, ed, dbid);
                ELSE
                    DBMS_ADDM.ANALYZE_PARTIAL(taskname, inst, st, ed, dbid);
                END IF;
                rs := DBMS_ADDM.GET_REPORT(taskname);
            $ELSE
                dbms_advisor.create_task('ADDM', taskid, taskname, 'ADDM Extraction', NULL);
                dbms_advisor.set_task_parameter(taskname, 'START_SNAPSHOT', st);
                dbms_advisor.set_task_parameter(taskname, 'END_SNAPSHOT', ed);
                dbms_advisor.set_task_parameter(taskname, 'INSTANCE', inst);
                dbms_advisor.set_task_parameter(taskname, 'DB_ID', dbid);
                dbms_advisor.execute_task(taskname);
                rs := dbms_advisor.get_task_report(taskname, 'TEXT', 'ALL');
            $END
            OPEN cur FOR
                SELECT r1 "#", "Impact(%)","Target ID","Message"
                FROM   (With A as(SELECT /*+materialize*/
                                   dense_rank() OVER(ORDER BY impact DESC, a.message || a.more_info ASC) r,
                                   a.finding_id,
                                   b.rec_id,
                                   a.task_id,
                                   c.action_id,
                                   SUM(DISTINCT a.impact) OVER(PARTITION BY a.finding_id) impact,
                                   REPLACE(a.message || a.more_info, chr(10), chr(10) || lpad(' ', 12)) findmsg,
                                   'Advise #' || b.rank || ': ' || b.type remgroup,
                                   b.benefit rembenefit,
                                   (SELECT MAX(decode(f.message#, 388, f.p2 * f.p3 * 1e6))
                                    FROM   sys.wri$_adv_rationale e, sys.wri$_adv_message_groups f
                                    WHERE  f.task_id = E.task_id
                                    AND    e.task_id = b.task_id
                                    AND    e.rec_id = b.rec_id
                                    AND    f.id = e.msg_id) remimpact,
                                   (SELECT RTRIM(NVL2(MAX(E.task_id), 'Rationale: ', '') ||
                                                 to_char(REPLACE(wmsys.wm_concat(e.message || CHR(10)),
                                                                 CHR(10) || ',',
                                                                 chr(10) || LPAD(' ', 19))),
                                                 chr(0) || chr(10))
                                    FROM   DBA_ADVISOR_RATIONALE e
                                    WHERE  B.task_id = E.task_id
                                    AND    B.rec_id = E.rec_id) remreason,
                                   c.command remcommand,
                                   c.command_id remcommandid,
                                   nvl2(c.message, 'Action: ', '') || c.message remmessage,
                                   d.object_id,
                                   d.type target,
                                   d.attr1 target_id,
                                   d.attr2 sql_plan_id,
                                   d.attr4 sql_text
                            FROM   DBA_ADVISOR_FINDINGS        a,
                                   DBA_ADVISOR_RECOMMENDATIONS b,
                                   DBA_ADVISOR_ACTIONS         C,
                                   DBA_ADVISOR_OBJECTS         D
                            WHERE  A.task_id = B.task_id(+)
                            AND    A.finding_id = B.finding_id(+)
                            AND    B.task_id = C.task_id(+)
                            AND    B.rec_id = C.rec_id(+)
                            AND    C.task_id = D.task_id(+)
                            AND    C.object_id = D.object_id(+)
                            AND    A.task_name = taskname)
                        SELECT DISTINCT a.r r1,
                                        DECODE(SIGN(b.r - 1), 1, rec_id, -9) R2,
                                        DECODE(SIGN(b.r - 2), 1, NVL2(remreason, -1, remcommandid), -9) r3,
                                        DECODE(SIGN(b.r - 3), 1, remcommandid, -9) r4,
                                        rpad(' ', LEAST(b.r - 1, 2) * 4) ||
                                        DECODE(b.r,
                                               1,
                                               'Finding #'||a.r||': '||FINDMSG,
                                               2,
                                               remgroup,
                                               3,
                                               nvl(remreason, remmessage),
                                               4,
                                               remmessage) "Message",
                                        round(DECODE(b.r, 1, IMPACT, 2, rembenefit, 3, remimpact) * 1e-6/60,
                                              2) "Minutes",
                                        round(DECODE(b.r, 1, IMPACT, 2, rembenefit, 3, remimpact) * 100 /
                                              (SELECT parameter_value
                                               FROM   Dba_Advisor_Parameters f
                                               WHERE  parameter_name = 'DB_ELAPSED_TIME'
                                               AND    f.task_id = a.task_id),
                                              2) "Impact(%)",
                                        DECODE(b.r, 4, target) "Target Obj",
                                        DECODE(b.r, 4, target_id) "Target ID",
                                        DECODE(b.r, 4, sql_plan_id) "Plan Hash"
                        FROM    a,
                               (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM <= 4) b
                        WHERE  b.r - 2 <=
                               NVL2(a.remreason, 1, 0) + NVL2(a.remmessage, 1, 0) - NVL2(a.rec_id, 0, 1)
                        ORDER  BY 1, 2, 3, 4);
        
        END;
    BEGIN
        extract_addm(:1, :2, :3);
        :4 := filename;
        :5 := rs;
        :6 := cur;
    END;]]
    env.checkerr(db:check_obj('dbms_advisor.create_task'),'Sorry, you dont have the "Advisor" privilege!')
    awr.dump_report(stmt,starttime,endtime,instances)
end

function awr.onload()
    env.set_command(nil,"awrdump","Extract AWR report. Usage: awrdump <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]",awr.extract_awr,false,4)
    env.set_command(nil,"ashdump","Extract ASH report. Usage: ashdump <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]",awr.extract_ash,false,4)
    env.set_command(nil,"addmdump","Extract ADDM report. Usage: addmdump <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]",awr.extract_addm,false,4)
end

return awr