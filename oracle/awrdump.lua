local db,cfg=env.getdb(),env.set
local awr={}

function awr.get_snap_time(time)
    local t=db:get_value("select max(to_char(end_interval_time+0,'yymmddhh24miss')) from dba_hist_snapshot where snap_id=regexp_substr(:1,'\\d+')",{time})
    return t~="" and t or db:check_date(time)
end

function awr.get_range(starttime,endtime,instances,container)
    if (starttime=='.' or not starttime) then 
        if cfg.get("starttime") and  cfg.get("starttime")~='' then 
            starttime=cfg.get("starttime")
        else
            starttime=nil
        end
    else
        starttime=awr.get_snap_time(starttime)
    end

    if (endtime=='.' or not endtime) then 
        if cfg.get("endtime") and  cfg.get("endtime")~='' then 
            endtime=cfg.get("endtime")
        else
            endtime=nil
        end
    else
        endtime=awr.get_snap_time(endtime)
    end

    if (instances=='.' or not instances) then 
        if cfg.get("instance") then 
            if  tonumber(cfg.get("instance"))>0 then
                instances=cfg.get("instance")
            else
                instances=db.props.instance
            end
        else
            instances=nil
        end
    end

    if (container=='.' or not container) then 
        if cfg.get("container") then 
            if  tonumber(cfg.get("container"))>0 then
                container=cfg.get("container")
            else
                container=db.props.container_id
            end
        else
            container=nil
        end
    end

    env.checkerr(starttime and endtime,'Parameters: <YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|a|<inst1,inst2,...>]')
    return starttime,endtime,instances,container
end

function awr.dump_report(stmt,starttime,endtime,instances,container)
    starttime,endtime,instances,container=awr.get_range(starttime,endtime,instances,container)
    env.checkerr(db:check_access('dbms_workload_repository.awr_report_html',1),'Sorry, you dont have the "execute" privilege on package "dbms_workload_repository"!')
    local args={starttime,endtime,instances or "",'#VARCHAR','#CLOB','#CURSOR'}
    cfg.set("feed","off")
    stmt=stmt:replace("@lz_compress@",env.oracle.lz_compress)
    db:exec(stmt:replace('@get_range@',awr.extract_period()),args)
    if args[5] and args[5]~='' then
        if not args[5]:find(' ') then
            local pieces=args[5]:split('\n')
            args[5]=loader:Base64ZlibToText(pieces);
        end
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
                           nvl(MAX(decode(sign(end_interval_time-3e-4-s),1,null,snap_id)),min(snap_id)) st,
                           nvl(min(decode(sign(end_interval_time+3e-4-e),-1,null,snap_id)),max(snap_id)) ed
                    FROM   Dba_Hist_Snapshot
                    WHERE  begin_interval_time-3e-4 <= e and end_interval_time+3e-4>=s
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

function awr.extract_awr(starttime,endtime,instances,starttime2,endtime2,container,typ)
    local stmt=[[
    DECLARE
        rs       CLOB;
        filename VARCHAR2(200);
        cur      SYS_REFCURSOR;
        typ      VARCHAR2(30):='AWR';
        @get_range@
        @lz_compress@
        PROCEDURE extract_awr(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2,p_start2 VARCHAR2:=NULL, p_end2 VARCHAR2:=NULL) IS
            stim1         date;
            etim1         date;
            stim          date;
            etim          date;
            dbid          INT;
            st            INT;
            ed            INT;
            dbid2         INT;
            st2           INT;
            ed2           INT;
            rc            SYS_REFCURSOR;
            txt           VARCHAR2(32000);
            inst          VARCHAR2(30) := NULLIF(upper(p_inst), 'A');
            inst1         INT;
            inst2         INT;
            PROCEDURE gen_ranges(p_start VARCHAR2, p_end VARCHAR2,dbid OUT INT,st OUT INT,ed OUT INT) IS
            BEGIN
                IF p_end IS NULL AND stim IS NOT NULL AND etim IS NOT NULL THEN
                    etim := to_date(p_start, 'YYMMDDHH24MISS')+(etim-stim);
                ELSE
                    etim := to_date(p_end, 'YYMMDDHH24MISS');
                END IF;
                stim := to_date(p_start, 'YYMMDDHH24MISS');

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
                stim1 := stim;
                etim1 := etim;
                gen_ranges(p_start2,p_end2,dbid2,st2,ed2);
                filename := lower(typ)||'_diff_' || least(st,st2) || '_' || greatest(ed,ed2) || '_' || nvl(inst, 'all') || '.html';
                OPEN cur for
                select  typ report_type,
                        nvl(inst,'ALL') INSTANCES,
                        to_char(stim1,'YYYY-MM-DD HH24:MI') begin_time1,
                        to_char(etim1,'YYYY-MM-DD HH24:MI') end_time1,
                        st begin_snap1,
                        ed end_snap1,
                        '|' "|",
                        to_char(stim,'YYYY-MM-DD HH24:MI') begin_time2,
                        to_char(etim,'YYYY-MM-DD HH24:MI') end_time2,
                        st2 begin_snap2,
                        ed2 end_snap2
                from    dual;
            ELSE
                filename := lower(typ)||'_' || st || '_' || ed || '_' || nvl(inst, 'all') || '.html';
                OPEN cur for
                select  typ report_type,
                        nvl(inst,'ALL') INSTANCES,
                        to_char(stim,'YYYY-MM-DD HH24:MI') begin_time,
                        st begin_snap,
                        to_char(etim,'YYYY-MM-DD HH24:MI') end_time,
                        ed end_snap
                from    dual;
            END IF;

            IF typ='ADDM' THEN
                $IF DBMS_DB_VERSION.VERSION>11 $THEN
                    IF regexp_like(inst,'\d+') THEN
                        inst1 := regexp_substr(inst,'\d+',1,1);
                        inst2 := nvl(regexp_substr(inst,'\d+',1,2)+0,inst1);
                        rs:=sys.dbms_addm.compare_instances(dbid, inst1,st, ed,dbid2,inst2,st2, ed2);
                    ELSE
                        rs:=sys.dbms_addm.compare_databases(dbid, st, ed,dbid2, st2, ed2);
                    END IF;
                $ELSE
                    raise_application_error(-20001,'Unsupported database version!');
                $END
            ELSE
                $IF DBMS_DB_VERSION.VERSION>11 OR DBMS_DB_VERSION.VERSION>10 AND DBMS_DB_VERSION.release>1 $THEN
                    dbms_workload_repository.awr_set_report_thresholds(top_n_sql => 50);
                $END

                IF NOT (inst IS NULL OR INSTR(inst, ',') > 0) THEN
                    IF ed2 IS NULL THEN
                        OPEN rc for SELECT * FROM TABLE(dbms_workload_repository.awr_report_html(dbid, inst, st, ed));
                    ELSE
                        OPEN rc for SELECT * FROM TABLE(dbms_workload_repository.awr_diff_report_html(dbid, inst, st, ed,dbid2, inst, st2, ed2));
                    END IF;
                ELSIF INSTR(inst, ',') > 0 AND st=st2 THEN
                    inst1 := regexp_substr(inst,'\d+',1,1);
                    inst2 := nvl(regexp_substr(inst,'\d+',1,2)+0,inst1);
                    OPEN rc for SELECT * FROM TABLE(dbms_workload_repository.awr_diff_report_html(dbid, inst1, st, ed,dbid2, inst2, st2, ed2));
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
                            dbms_lob.writeappend(rs,length(txt)+1,txt||chr(10));
                        END IF;
                    EXCEPTION WHEN OTHERS THEN null;
                    END;
                END LOOP;
                CLOSE rc;
            END IF;
        END;
    BEGIN
        extract_awr(:1, :2, :3,@diff);
        base64encode(rs);
        :4 := filename;
        :5 := rs;
        :6 := cur;
    END;]]
    env.checkhelp(endtime)
    if typ=='ADDM' then stmt=stmt:gsub('AWR','ADDM') end
    if not starttime2 then
        stmt=stmt:gsub(',@diff','')
    else
        starttime2,endtime2=awr.get_range(starttime2,endtime2 or starttime2,instances,container)
        stmt=stmt:gsub('@diff',string.format("'%s','%s'",starttime2,endtime2==starttime2 and '' or endtime2))
    end
    awr.dump_report(stmt,starttime,endtime,instances,container)
end

function awr.extract_awr_diff(starttime,endtime,starttime2,endtime2,instances,container)
    if endtime2=='.' then endtime2=nil end
    if starttime2=='.' then starttime2=nil end
    env.checkhelp(starttime2 or (instances and instances:find(',')))
    if not starttime2 then starttime2=starttime end
    awr.extract_awr(starttime,endtime,instances,starttime2,endtime2,container)
end

function awr.extract_addm_diff(starttime,endtime,starttime2,endtime2,instances,container)
    if endtime2=='.' then endtime2=nil end
    if starttime2=='.' then starttime2=nil end
    env.checkhelp(starttime2 or (instances and instances:find(',')))
    if not starttime2 then starttime2=starttime end
    awr.extract_awr(starttime,endtime,instances,starttime2,endtime2,container,'ADDM')
end

function awr.extract_ash(starttime,endtime,instances,container)
    local stmt=[[
    DECLARE
        rs       CLOB;
        filename VARCHAR2(200);
        cur      SYS_REFCURSOR;
        wait_class    VARCHAR2(100);
        service_name  VARCHAR2(30);
        module        VARCHAR2(300);
        action        VARCHAR2(300);
        client_id     VARCHAR2(300);
        @get_range@
        @lz_compress@
        PROCEDURE extract_ash(p_start VARCHAR2, p_end VARCHAR2, p_inst VARCHAR2) IS
            dbid INT;
            stim date;
            etim date;
            st   INT;
            ed   INT;
            inst VARCHAR2(30) := NULLIF(upper(p_inst), 'A');
        BEGIN
            IF not regexp_like(replace(inst,','),'^\d+$') AND inst!='A' THEN
                SELECT MAX(DECODE(typ, 'service_name', nam)), MAX(DECODE(typ, 'wait_class', nam)), 
                       MAX(DECODE(typ, 'module', nam)), MAX(DECODE(typ, 'action', nam)),
                       MAX(DECODE(typ, 'client_id', nam))
                INTO   service_name, wait_class, module, action, client_id
                FROM   (SELECT 'service_name' typ, to_char(NAME_hash) nam
                         FROM   GV$ACTIVE_SERVICES
                         WHERE  upper(NAME) LIKE inst
                         AND    ROWNUM < 2
                         UNION ALL
                         SELECT 'wait_class', NAME
                         FROM   v$event_name
                         WHERE  upper(NAME) LIKE inst
                         AND    ROWNUM < 2
                         UNION ALL
                         SELECT /*+no_expand*/
                          DECODE(upper(inst), upper(MODULE), 'module', upper(action), 'action', upper(client_identifier), 'client_id'),
                          DECODE(upper(inst), upper(MODULE), MODULE, upper(action), action, upper(client_identifier), client_identifier)
                         FROM   gv$session
                         WHERE  (upper(MODULE) = inst OR UPPER(action) = inst OR upper(client_identifier) = inst)
                         AND    ROWNUM < 2)
                WHERE  ROWNUM < 2;
                inst := NULL;
            END IF;

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
                                                                                etim ,
                                                                                0,
                                                                                600,null,null,
                                                                                wait_class,
                                                                                service_name,
                                                                                module,
                                                                                action,
                                                                                client_id))) LOOP
                    IF r.output IS NOT NULL THEN
                        dbms_lob.writeappend(rs, LENGTH(r.output), r.output);
                    END IF;
                END LOOP;
            $IF DBMS_DB_VERSION.VERSION>11 OR DBMS_DB_VERSION.VERSION>10 AND DBMS_DB_VERSION.release>1 $THEN
            ELSE
                FOR r IN (SELECT *
                          FROM   TABLE(dbms_workload_repository.ash_global_report_html(dbid,
                                                                                       inst,
                                                                                       stim ,
                                                                                       etim ,0,
                                                                                       l_slot_width=>600,
                                                                                       l_wait_class=>wait_class,
                                                                                       l_service_hash=>service_name,
                                                                                       l_module=>module,
                                                                                       l_action=>action,
                                                                                       l_client_id=>client_id))) LOOP
                    IF r.output IS NOT NULL THEN
                        dbms_lob.writeappend(rs, LENGTH(r.output), r.output);

                    END IF;
                END LOOP;
            $END
            END IF;
        END;
    BEGIN
        extract_ash(:1, :2, :3);
        base64encode(rs);
        :4 := filename;
        :5 := rs;
        :6 := cur;
    END;]]
    env.checkhelp(endtime)
    awr.dump_report(stmt,starttime,endtime,instances,container)
end

function awr.extract_addm(starttime,endtime,instances,container)
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
    env.checkhelp(endtime)
    env.checkerr(db:check_access('dbms_advisor.create_task',1),'Sorry, you dont have the "Advisor" privilege!')
    starttime,endtime,instances,instances=awr.get_range(starttime,endtime,instances,container)
    local args={starttime,endtime,instances or "",'#VARCHAR'}
    cfg.set("feed","off")
    stmt=stmt:replace("@lz_compress@",env.oracle.lz_compress)
    db:exec(stmt:replace('@get_range@',awr.extract_period()),args)
    if args[4] ~='#VARCHAR' then
        db.C.ora:run_script('addm',args[4])
    end
end

function awr.onload()
    env.set_command(nil,"awrdump","Extract AWR report. Usage: @@NAME {<YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|<inst1,inst2,...>] }",awr.extract_awr,false,5)
    env.set_command(nil,"awrdiff","Extract AWR Diff report. Usage: @@NAME {<YYMMDDHH24MI> <YYMMDDHH24MI> <YYMMDDHH24MI> [YYMMDDHH24MI] [inst_id|<inst1,inst2,...>] }",awr.extract_awr_diff,false,7)
    env.set_command(nil,"addmdiff","Extract AWR Diff report. Usage: @@NAME {<YYMMDDHH24MI> <YYMMDDHH24MI> <YYMMDDHH24MI> [YYMMDDHH24MI] [inst_id|<inst1,inst2,...>] }",awr.extract_addm_diff,false,7)
    env.set_command(nil,"ashdump","Extract ASH report. Usage: @@NAME {<YYMMDDHH24MI> <YYMMDDHH24MI> [<inst1[,inst2...>]|<client_id>|<wait_class>|<service_name>|<module>|<action>] [container]}",awr.extract_ash,false,5)
    env.set_command(nil,"addmdump","Extract ADDM report. Usage: @@NAME {<YYMMDDHH24MI> <YYMMDDHH24MI> [inst_id|<inst1,inst2,...>] }",awr.extract_addm,false,5)
end

return awr