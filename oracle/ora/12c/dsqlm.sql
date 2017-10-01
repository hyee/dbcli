/*[[Get SQL Monitor report from dba_hist_reports, supports 12c only. Usage: @@NAME {[sql_id|report_id] [YYYYMMDDHH24MI] [YYYYMMDDHH24MI]} [-f"<filter>"] [-avg]
  <sql_id> : List the records related to the specific SQL_ID and export SQL Performance Hub
  -u       : Only show the SQL list within current schema
  -avg     : Show average cost instead of total cost
  --[[
    @ver   : 12.1={}
    &filt  : default={KEY1=nvl(v_sql_id,KEY1)},f={},u={username=nvl('&0',sys_context('userenv','current_schema'))}
    &grp   : default={none}, g={g}, d={d}
    &filter: default={1=1}, f={} 
    &avg   : default={sum), avg={avg}
    @check_access_hub : SYS.DBMS_PERF={1} default={0}
  --]]
]]*/

SET FEED OFF verify off


def agg = ""
col dur,avg_ela,ela,parse,queue,cpu,app,cc,cl,plsql,java,io,time format smhd2
col read,write,iosize,mem,temp,cellio,buffget,offload,offlrtn format kmg
col est_cost,est_rows,act_rows,ioreq,execs,outputs,FETCHES,dxwrite format TMB
BEGIN
     IF :V1 IS NOT NULL THEN
        :AGG := '--';
     END IF;
END;
/
ALTER SESSION SET PLSQL_CCFLAGS = 'hub:&check_access_hub';

VAR report CLOB;
var filename VARCHAR2
VAR cur REFCURSOR;
DECLARE
    v_report_id int:= regexp_substr(:V1,'^\d+$');
    v_sql_id    VARCHAR2(30):=:V1;
    v_inst      INT := :INSTANCE;
    v_report    clob;
    v_file      VARCHAR2(50);
    v_start     date:=NVL(to_date(NVL(:V2,:STARTTIME),'yymmddhh24mi'),sysdate-7);
    v_end       date:=NVL(to_date(NVL(:V3,:ENDTIME),'yymmddhh24mi'),sysdate);
BEGIN
    IF v_report_id IS NULL THEN
        OPEN :cur FOR
        &agg SELECT sql_id, 
        &agg        max(report_id) last_rpt, 
        &agg        count(1) seens,
        &agg        to_char(MIN(PERIOD_START_TIME), 'MMDD HH24:MI:SS') first_seen,
        &agg        to_char(MAX(PERIOD_END_TIME), 'MMDD HH24:MI:SS') last_seen,
        &agg        ROUND(&avg(DUR),2) DUR,
        &agg        ROUND(&avg(ELA),2) ela,
        &agg        ROUND(&avg(cpu),2) cpu,
        &agg        ROUND(&avg(io),2) io,
        &agg        ROUND(&avg(cc),2) cc,
        &agg        ROUND(&avg(cl),2) cl,
        &agg        ROUND(&avg(app),2) app,
        &agg        ROUND(&avg(plsql),2) plsql,
        &agg        ROUND(&avg(ot),2) ot,
        &agg        ROUND(&avg(ioreq),2) ioreq,
        &agg        ROUND(&avg(iosize),2) iosize,
        &agg        ROUND(&avg(buffget),2) buffget,
        &agg        ROUND(&avg(offload),2) offload,
        &agg        round(avg(ofleff),2) ofleff,
        &agg        max(SQL_TEXT) sql_text
        &agg FROM(
                SELECT *  FROM (
                    SELECT /*+no_expand*/ 
                           REPORT_ID,
                           SNAP_ID,
                           KEY1 SQL_ID,
                           KEY2 SQL_EXEC_ID,
                           PERIOD_START_TIME,
                           PERIOD_END_TIME,
                           b.*,
                           substr(TRIM(regexp_replace(REPLACE(EXTRACTVALUE(summary, '//sql_text'), chr(0)), '[' || chr(10) || chr(13) || chr(9) || ' ]+', ' ')), 1, 150) SQL_TEXT
                    FROM   (SELECT a.*, xmltype(a.report_summary) summary FROM dba_hist_reports a) a,
                           xmltable('/report_repository_summary/*' PASSING a.summary columns --
                                    plan_hash NUMBER PATH 'plan_hash',
                                    username  VARCHAR2(100) PATH 'user',
                                    dur NUMBER path 'stats/stat[@name="duration"]', 
                                    ela NUMBER path 'stats/stat[@name="elapsed_time"]*1e-6', 
                                    CPU NUMBER path 'stats/stat[@name="cpu_time"]*1e-6',
                                    io NUMBER path 'stats/stat[@name="user_io_wait_time"]*1e-6', 
                                    app NUMBER path 'stats/stat[@name="application_wait_time"]*1e-6',
                                    cl NUMBER path 'stats/stat[@name="cluster_wait_time"]*1e-6', 
                                    cc NUMBER path 'stats/stat[@name="concurrency_wait_time"]*1e-6',
                                    ot NUMBER path 'stats/stat[@name="other_wait_time"]*1e-6', 
                                    plsql NUMBER path 'stats/stat[@name="plsql_exec_time"]*1e-6',
                                    ioreq NUMBER path 'sum(stats/stat[@name=("read_reqs","write_reqs")])',
                                    iosize NUMBER path 'sum(stats/stat[@name=("read_bytes","write_bytes")])', 
                                    buffget NUMBER path 'stats/stat[@name="buffer_gets"]*8192',
                                    offload NUMBER path 'stats/stat[@name="elig_bytes"]', 
                                    --ofleff NUMBER path 'stats/stat[@name="cell_offload_efficiency"]',
                                    ofleff NUMBER path 'stats/stat[@name="cell_offload_efficiency2"]', 
                                    offlrtn NUMBER path 'stats/stat[@name="ret_bytes"]'
                                    --,service VARCHAR2(100) PATH 'service', program VARCHAR2(300) PATH 'program'
                                    --,sql_text VARCHAR2(4000) PATH 'sql_text'
                                    --unc_bytes NUMBER path 'stats/stat[@name="unc_bytes"]',
                                    --fetches NUMBER path 'stats/stat[@name="user_fetch_count"]'
                                    --
                                    ) b
                          WHERE  a.COMPONENT_NAME='sqlmonitor'
                          AND    (&filt)
                          AND    (v_sql_id IS NOT NULL OR plan_hash>0)
                          AND    PERIOD_START_TIME<=v_end
                          AND    PERIOD_END_TIME>=v_start
                ) WHERE &filter
                ORDER BY REPORT_ID DESC
            &agg ) GROUP BY SQL_ID ORDER BY ELA DESC
            FETCH FIRST 50 ROWS ONLY;
        IF v_sql_id IS NOT NULL THEN
            $IF DBMS_DB_VERSION.VERSION>11 AND $$hub =1 $THEN
                v_file   := 'sqlhub_' || v_sql_id || '.html';
                v_report := sys.dbms_perf.report_sql(sql_id => v_sql_id,
                                                     is_realtime => 0,
                                                     outer_start_time => v_start,
                                                     outer_end_time => v_end,
                                                     selected_start_time => v_start,
                                                     selected_end_time => v_end,
                                                     inst_id => v_inst,
                                                     dbid => null,
                                                     monitor_list_detail => 50);
            $END
        END IF;
    ELSE
        OPEN :cur for 
            SELECT DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL(RID => v_report_id, TYPE => 'text')
            FROM dual;
        v_report := DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL(RID => v_report_id, TYPE => 'active');
        v_file   := 'dsqlm_report_'||v_report_id||'.html';
    END IF;
    :report  := v_report;
    :filename:= v_file;
END;
/
print cur
save report filename