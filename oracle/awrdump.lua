local db,cfg=env.getdb(),env.set
local awr={}

function awr.get_range(starttime,endtime,instances)
    if (starttime=='.' or not starttime) then 
        if cfg.get("starttime") and  cfg.get("starttime")~='' then 
            starttime=cfg.get("starttime")
        else
            starttime=nil
        end
    else
        db:check_date(starttime)
    end

    if (endtime=='.' or not endtime) then 
        if cfg.get("endtime") and  cfg.get("endtime")~='' then 
            endtime=cfg.get("endtime")
        else
            endtime=nil
        end
    else
        db:check_date(endtime)
    end

    if (instances=='.' or not instances) then 
        if cfg.get("instance") and  tonumber(cfg.get("instance"))>0 then 
            instances=cfg.get("instance")
        else
            instances=nil
        end
    end

    env.checkerr(starttime and endtime,'Parameters: <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]')
    return starttime,endtime,instances
end

function awr.dump_report(stmt,starttime,endtime,instances)
    starttime,endtime,instances=awr.get_range(starttime,endtime,instances)
    env.checkerr(db:check_access('dbms_workload_repository.awr_report_html',1),'Sorry, you dont have the "execute" privilege on package "dbms_workload_repository"!')
    local args={starttime,endtime,instances or "",'#VARCHAR','#CLOB','#CURSOR'}
    cfg.set("feed","off")
    db:exec(stmt:replace('@get_range@',awr.extract_period()),args)
    if args[5] then
        print("Result written to file "..env.write_cache(args[4],args[5]))
        db.resultset:print(args[6],db.conn)
    else
        print('Cannot generate file: '..args[4])
    end
end

function awr.extract_period()
    return [[PROCEDURE get_range(p_start VARCHAR2,p_end VARCHAR2,p_inst VARCHAR2,dbid OUT INT, st OUT INT, ed OUT INT, stim OUT DATE, etim OUT DATE) IS
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
                    RAISE_APPLICATION_ERROR(-20001,'Not a valid date format: "'||p_start||'" or "'||p_end||'"!');
                END;
            END;
            SELECT max(dbid),
                   max(st),max(ed),
                   max((select nvl(max(end_interval_time+0),s) from Dba_Hist_Snapshot WHERE snap_id=st AND dbid=a.dbid)),
                   max((select nvl(max(end_interval_time+0),e) from Dba_Hist_Snapshot WHERE snap_id=ed AND dbid=a.dbid))
            INTO dbid,st,ed,stim,etim
            FROM   (SELECT dbid,
                           nvl(MAX(decode(sign(end_interval_time-0.004-s),1,null,snap_id)),min(snap_id)) st,
                           nvl(min(decode(sign(end_interval_time+0.004-e),-1,null,snap_id)),max(snap_id)) ed
                    FROM   Dba_Hist_Snapshot
                    WHERE  begin_interval_time-0.04 <= e and end_interval_time+0.004>=s
                    AND    (p_inst IS NULL OR instr(',' || p_inst || ',', instance_number) > 0)
                    GROUP  BY DBID
                    ORDER  BY 2 DESC) a
            WHERE  ROWNUM < 2;

            IF ed IS NULL THEN
                RAISE_APPLICATION_ERROR(-20001,'Cannot find the matched AWR snapshots between '''||s||''' and '''||e||'''!' );
            END IF;

            IF dbid IS NULL THEN
                SELECT dbid INTO dbid FROM v$database;
            END IF;
        END;]]
end

function awr.extract_awr(starttime,endtime,instances,starttime2,endtime2)
    local stmt=[[
    DECLARE
        rs       CLOB;
        filename VARCHAR2(200);
        cur      SYS_REFCURSOR;
        @get_range@
        PROCEDURE extract_awr(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2,p_start2 VARCHAR2:=NULL, p_end2 VARCHAR2:=NULL) IS
            stim  date;
            etim  date;
            dbid  INT;
            st    INT;
            ed    INT;
            dbid2 INT;
            st2   INT;
            ed2   INT;
            rc    SYS_REFCURSOR;
            txt   VARCHAR2(32000);
            inst  VARCHAR2(30) := NULLIF(upper(p_inst), 'A');
            PROCEDURE gen_ranges(p_start VARCHAR2, p_end VARCHAR2,dbid OUT INT,st OUT INT,ed OUT INT) IS
            BEGIN
                IF p_end IS NULL AND stim IS NOT NULL AND etim IS NOT NULL THEN
                    etim := to_date(p_start, 'YYMMDDHH24MI')+(etim-stim);
                ELSE
                    etim := to_date(p_end, 'YYMMDDHH24MI');
                END IF;
                stim := to_date(p_start, 'YYMMDDHH24MI');

                get_range(stim,etim,inst,dbid,st,ed,stim,etim);
            END;
        BEGIN
            IF DBMS_DB_VERSION.VERSION+DBMS_DB_VERSION.release < 13 THEN
                IF inst IS NULL THEN
                    inst := USERENV('instance');
                END IF;

                IF INSTR(inst, ',') > 0 THEN
                    RETURN;
                END IF;
            END IF;

            gen_ranges(p_start,p_end,dbid,st,ed);

            IF p_start2 IS NOT NULL THEN
                gen_ranges(p_start2,p_end2,dbid2,st2,ed2);
                filename := 'awr_diff_' || least(st,st2) || '_' || greatest(ed,ed2) || '_' || nvl(inst, 'all') || '.html';
                OPEN cur for
                select 'AWR' report_type,
                        nvl(inst,'ALL') INSTANCES,
                        st begin_snap1,
                        ed end_snap1,
                        '*' "*",
                        to_char(stim,'YYYY-MM-DD HH24:MI') begin_time2,
                        st2 begin_snap2,
                        to_char(etim,'YYYY-MM-DD HH24:MI') end_time2,
                        ed2 end_snap2
                from    dual;
            ELSE
                filename := 'awr_' || st || '_' || ed || '_' || nvl(inst, 'all') || '.html';
                OPEN cur for
                select 'AWR' report_type,
                        nvl(inst,'ALL') INSTANCES,
                        to_char(stim,'YYYY-MM-DD HH24:MI') begin_time,
                        st begin_snap,
                        to_char(etim,'YYYY-MM-DD HH24:MI') end_time,
                        ed end_snap
                from    dual;
            END IF;

            $IF DBMS_DB_VERSION.VERSION>11 OR DBMS_DB_VERSION.VERSION>10 AND DBMS_DB_VERSION.release>1 $THEN
                dbms_workload_repository.awr_set_report_thresholds(top_n_sql => 50);
            $END

            IF NOT (inst IS NULL OR INSTR(inst, ',') > 0) THEN
                IF ed2 IS NULL THEN
                    OPEN rc for SELECT * FROM TABLE(dbms_workload_repository.awr_report_html(dbid, inst, st, ed));
                ELSE
                    OPEN rc for SELECT * FROM TABLE(dbms_workload_repository.awr_diff_report_html(dbid, inst, st, ed,dbid2, inst, st2, ed2));
                END IF;
            $IF DBMS_DB_VERSION.VERSION>11 OR DBMS_DB_VERSION.VERSION>10 AND DBMS_DB_VERSION.release>1 $THEN
            ELSE
                IF ed2 IS NULL THEN
                    OPEN rc for SELECT * FROM TABLE(dbms_workload_repository.awr_global_report_html(dbid,inst,st,ed));
                ELSE
                    OPEN rc for SELECT * FROM TABLE(dbms_workload_repository.awr_global_diff_report_html(dbid,inst,st,ed,dbid2,inst,st2,ed2));
                END IF;
            $END
            END IF;
            dbms_lob.createtemporary(rs, TRUE);
            LOOP
                BEGIN
                    fetch rc into txt;
                    exit when rc%notfound;
                    IF Trim(txt) IS NOT NULL THEN
                        dbms_lob.writeappend(rs,lengthb(txt)+1,txt||chr(10));
                    END IF;
                EXCEPTION WHEN OTHERS THEN null;
                END;
            END LOOP;
            CLOSE rc;
        END;
    BEGIN
        extract_awr(:1, :2, :3,@diff);
        :4 := filename;
        :5 := rs;
        :6 := cur;
    END;]]
    if not starttime2 then
        stmt=stmt:gsub(',@diff','')
    else
        db:check_date(starttime2)
        db:check_date(endtime2 or starttime2)
        stmt=stmt:gsub('@diff',string.format("'%s','%s'",starttime2,endtime2 or ''))
    end
    awr.dump_report(stmt,starttime,endtime,instances)
end

function awr.extract_awr_diff(starttime,endtime,starttime2,endtime2,instances)
    if endtime2=='.' then endtime2=nil end
    awr.extract_awr(starttime,endtime,instances,starttime2,endtime2)
end

function awr.extract_ash(starttime,endtime,instances)
    local stmt=[[
    DECLARE
        rs       CLOB;
        filename VARCHAR2(200);
        cur      SYS_REFCURSOR;
        @get_range@
        PROCEDURE extract_ash(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2) IS
            dbid INT;
            stim date;
            etim date;
            st   INT;
            ed   INT;
            inst VARCHAR2(30) := NULLIF(upper(p_inst), 'A');
        BEGIN

            IF DBMS_DB_VERSION.VERSION+DBMS_DB_VERSION.RELEASE < 13 THEN
                IF inst IS NULL THEN
                    inst := USERENV('instance');
                END IF;

                IF INSTR(inst, ',') > 0 THEN
                    RETURN;
                END IF;
            END IF;

            get_range(p_start,p_end,inst,dbid,st,ed,stim,etim);

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
                $IF DBMS_DB_VERSION.VERSION>11 OR DBMS_DB_VERSION.VERSION>10 AND DBMS_DB_VERSION.release>1 $THEN
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
        @get_range@
        PROCEDURE extract_addm(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2,taskid OUT INT) IS
            dbid     INT;
            stim     DATE;
            etim     DATE;
            st       INT;
            ed       INT;
            taskname VARCHAR2(30) := 'ADDM_DBCLI_REPORT';
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
        extract_addm(:1, :2, :3,:4);
    END;]]
    env.checkerr(db:check_access('dbms_advisor.create_task',1),'Sorry, you dont have the "Advisor" privilege!')
    starttime,endtime,instances=awr.get_range(starttime,endtime,instances)
    local args={starttime,endtime,instances or "",'#VARCHAR'}
    cfg.set("feed","off")
    db:exec(stmt:replace('@get_range@',awr.extract_period()),args)
    if args[4] ~='#VARCHAR' then
        db.C.ora:run_script('addm',args[4])
    end
end

function awr.onload()
    env.set_command(nil,"awrdump","Extract AWR report. Usage: awrdump <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]",awr.extract_awr,false,4)
    env.set_command(nil,"awrdiff","Extract AWR Diff report. Usage: awrdiff <YYMMDDHH24MI> <YYMMDDHH24MI> <YYMMDDHH24MI> [YYMMDDHH24MI] [inst_id|a|<inst1,inst2,...>]",awr.extract_awr_diff,false,6)
    env.set_command(nil,"ashdump","Extract ASH report. Usage: ashdump <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]",awr.extract_ash,false,4)
    env.set_command(nil,"addmdump","Extract ADDM report. Usage: addmdump <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]",awr.extract_addm,false,4)
end

return awr