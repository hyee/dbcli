/*[[ Oracle Performance Hub. Usage: @@NAME [{[1|YYMMDDHH24MI] [YYMMDDHH24MI]} | {[sid] [inst_id]}] [-snap"<minutes>"]
  -snap"<minutes>"        : Used only on realtime(gv$*) mode, specifying the start time as sysdate-<minutes>  
  <start> [<end>]         : Generate non-realtime(dba_hist*) Performance hub report
  1 [<end>]               : Generate realtime(gv$*) Performance hub report, start time defaults to 3 hours ago if "-snap" is not specified
  <sid> [<inst>]          : Generate realtime(gv$*) report on sepcific session, start time defaults to 3 hours ago if "-snap" is not specified
  <sid> [<inst>] <serial#>: Generate non-realtime(dba_hist*) report on sepcific session
  
  --[[
    @check_access_1: sys.dbms_perf={1}
    &snap          : default={to_number(null)} snap={&0/1440}
  --]]
]]*/   
set feed off VERIFY off
VAR report CLOB;
var filename VARCHAR2
DECLARE
    v_start    DATE :=to_date(:starttime, 'YYMMDDHH24MI');
    v_end      DATE :=to_date(:endtime, 'YYMMDDHH24MI');
    v_realtime INT := CASE WHEN nvl(:V1,'1') = '1' THEN 1 ELSE 0 END;
    v_report   CLOB;
    v_file     VARCHAR2(50);
    v_inst     INT := :instance;
    v_serial#  INT;
BEGIN
    BEGIN
        v_start  := coalesce(to_date(nullif(:V1,'1'), 'YYMMDDHH24MI'),v_start,SYSDATE - CASE WHEN :V1 = '1' THEN nvl(&snap,3/24) ELSE 7 END);
        v_end    := coalesce(to_date(nvl(:V2, :endtime), 'YYMMDDHH24MI'), SYSDATE);
        v_file   := 'perfhub_' || to_char(v_start, 'YYMMDDHH24MI') || '_' || to_char(v_end, 'YYMMDDHH24MI') || '.html';
        
        v_report := dbms_perf.report_perfhub(is_realtime => v_realtime,
                                             outer_start_time => v_start,
                                             outer_end_time => v_end,
                                             selected_start_time => v_start,
                                             selected_end_time => v_end,
                                             inst_id => v_inst,
                                             monitor_list_detail => 50,
                                             workload_sql_detail => 50,
                                             addm_task_detail => 20);
    EXCEPTION
        WHEN OTHERS THEN
            IF v_file IS NOT NULL THEN
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
    END;
    :filename := v_file;
    :report   := v_report;
END;
/
save report filename