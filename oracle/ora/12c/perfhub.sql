/*[[ Oracle Performance Hub. Usage: @@NAME [{[1|YYMMDDHH24MI] [YYMMDDHH24MI] [<sql_id>|<component>]} | {[sid] [inst_id] [serial#]}] [-snap"<minutes>"]
  -snap"<minutes>"        : Used only on realtime(gv$*) mode, specifying the start time as sysdate-<minutes>  
  <start> [<end>]         : Generate non-realtime(dba_hist*) Performance hub report
  1 [<end>]               : Generate realtime(gv$*) Performance hub report, start time defaults to 3 hours ago if "-snap" is not specified
  <sid> [<inst>]          : Generate realtime(gv$*) report on sepcific session, start time defaults to 3 hours ago if "-snap" is not specified
  <sid> [<inst>] <serial#>: Generate non-realtime(dba_hist*) report on sepcific session
  <component>             : can be combination with timepicker/summary/rac/ash/workload/monitor/addm/exa/cell concated by '+'. e.g: +exa+addm
  --[[
    @check_access_1: sys.dbms_perf={1}
    &snap          : default={to_number(null)} snap={&0/1440}
    &V1            : default={&starttime}
    &V2            : default={&endtime}
  --]]
]]*/   
set feed off VERIFY off
VAR report CLOB;
var filename VARCHAR2
DECLARE
    v_start    DATE;
    v_end      DATE;
    v_realtime INT := CASE WHEN nvl(:V1,'1') = '1' THEN 1 ELSE 0 END;
    v_report   CLOB;
    v_file     VARCHAR2(50);
    v_inst     INT := :instance;
    v_serial#  INT ;
    v_param    VARCHAR2(500);
    v_level    VARCHAR2(1000);
    dyn_lvl    PLS_INTEGER;
    PROCEDURE report_start IS
    BEGIN
        IF dyn_lvl IS NULL THEN
            SELECT value into dyn_lvl from v$parameter where name='optimizer_dynamic_sampling';
        END IF;
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling=5';
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PROCEDURE report_end IS
    BEGIN
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling='||dyn_lvl;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
BEGIN
    BEGIN
        v_start  := coalesce(to_date(nullif(:V1,'1'), 'YYMMDDHH24MI'),SYSDATE - CASE WHEN :V1 = '1' THEN nvl(&snap,3/24) ELSE 7 END);
        v_end    := coalesce(to_date(:V2, 'YYMMDDHH24MI'), SYSDATE);
        v_file   := 'perfhub_' ||CASE WHEN :v3 IS NOT NULL THEN trim('_' from REGEXP_REPLACE(:v3,'[\+-]+','_'))||'_' END|| to_char(v_start, 'YYMMDDHH24MI') || '_' || to_char(v_end, 'YYMMDDHH24MI') || '.html';
        BEGIN
        execute immediate 'alter session set events ''emx_control compress_xml=none''';
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        report_start;
        IF trim('+' from lower(:V3)) IN ('cell') THEN
            --SELECT COMPONENT_ID,COMPONENT_NAME,SYS.ANYDATA.CONVERTOBJECT(COMPONENT_OBJECT).GETTYPENAME() TYPE_NAME FROM SYS."_REPORT_COMPONENT_OBJECTS";
            v_param:=utl_lms.format_message('/orarep/cell/main?report_level=all&top=30&start_time=%s&end_time=%s&is_realtime=%s',
                                                                     to_char(v_start,'MM/DD/YYYY HH24:mm:ss'),
                                                                     to_char(v_end,'MM/DD/YYYY HH24:mm:ss'),
                                                                     ''||v_realtime);
            IF :dbid IS NOT NULL THEN
                v_param:=replace(v_param||'@dbid='||:dbid,'@','&');
            END IF;
            v_report := dbms_report.get_report(report_reference => v_param,compress_xml=>0);
        ELSIF :V3 IS NULL OR instr(:V3,'+')>0 OR instr(:V3,'-')>0 OR 
              lower(:V3) in('timepicker','summary','rac','ash','workload','monitor','addm','exa') THEN
            IF :V3 IS NOT NULL THEN
                v_level :='-timepicker-summary-rac-ash-workload-monitor-addm-exa+'||trim('+' from lower(:V3));
            END IF;
            v_report := dbms_perf.report_perfhub(is_realtime => v_realtime,
                                                 outer_start_time => v_start,
                                                 outer_end_time => v_end,
                                                 selected_start_time => v_start,
                                                 selected_end_time => v_end,
                                                 dbid=>:dbid,
                                                 inst_id => v_inst,
                                                 monitor_list_detail => 50,
                                                 workload_sql_detail => 50,
                                                 addm_task_detail => 20,
                                                 report_level=>v_level);
        ELSE
            v_report := dbms_perf.report_sql(sql_id => :V3,
                                             is_realtime => v_realtime,
                                             outer_start_time => v_start,
                                             outer_end_time => v_end,
                                             selected_start_time => v_start,
                                             selected_end_time => v_end,
                                             dbid=>:dbid,
                                             inst_id => v_inst,
                                             monitor_list_detail => 50);
        END IF;
        report_end;
    EXCEPTION
        WHEN OTHERS THEN
            IF v_file IS NOT NULL THEN
                report_end;
                raise;
            END IF;
            v_inst := nvl(:V2, v_inst);
            SELECT nvl(MAX(serial#), 0 + :V3), COUNT(1), coalesce(sysdate-&snap,MAX(logon_time),v_start,sysdate-7)
            INTO   v_serial#, v_realtime, v_start
            FROM   (SELECT *
                    FROM   gv$session
                    WHERE  sid = :V1
                    AND    inst_id = nvl(v_inst, inst_id))
            WHERE  rownum < 2;
            
            IF v_realtime=0 AND v_serial# IS NULL THEN
                raise_application_error(-20001,'Cannot find active session &V1@&V2, please specify the serial# in case of searching historical session!');
            END IF;
            v_end    := coalesce(to_date(:endtime, 'YYMMDDHH24MI'), SYSDATE); 
            
            v_file   := 'sidhub_' ||:V1 || '_' || v_serial# || '_' || v_inst ||'.html';
            v_report := dbms_perf.report_session(inst_id => v_inst,
                                                 SID => :V1,
                                                 serial => v_serial#,
                                                 is_realtime => v_realtime,
                                                 outer_start_time => v_start,
                                                 outer_end_time => v_end,
                                                 selected_start_time => v_start,
                                                 selected_end_time => v_end,
                                                 monitor_list_detail => 100);
            report_end;
    END;
    :filename := v_file;
    :report   := v_report;
END;
/
save report filename