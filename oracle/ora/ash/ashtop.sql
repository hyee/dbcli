/*[[
  Get ASH top event, type 'help @@NAME' for more info. Usage: @@NAME [-sql|-p|-none|-pr|-o|-plan|-ash|-dash|-snap|-f] {[fields] [filters]}
  
   --[[
      &fields: {
            sql={sql_id},
            e={null}, 
            p={p1,p2,p3,p3text},
            pr={p1raw,p2raw,p3raw}, 
            o={obj},
            plan={plan_hash,current_obj#,SQL_PLAN_LINE_ID} 
            none={1},
            proc={sql_id,PLSQL_ENTRY_OBJECT_ID},
        }
      &View: ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
      &BASE: ash={1}, dash={10}
      &Range: default={sample_time+0 between nvl(to_date(nvl(:V2,:starttime),'YYMMDDHH24MISS'),sysdate-1) and nvl(to_date(nvl(:V3,:endtime),'YYMMDDHH24MISS'),sysdate)}
      &filter: {
            id={(trim(:V1) is null or upper(:V1)='A' or :V1 in(sql_id,''||session_id)) and &range
                    &V4},
            snap={sample_time+0>=sysdate-nvl(0+:V1,30)/86400 and (:V2 is null or :V2 in(sql_id,''||session_id)) &V3},
            u={username=nvl('&0',sys_context('userenv','current_schema')) and &range}
        }
      &more_filter: default={1=1},f={}
      @counter: 11.2={, count(distinct sql_exec_id||to_char(sql_exec_start,'yyyymmddhh24miss')) "Execs"},default={}
      @UNIT   : 11.2={delta_time*1e-6}, default={&BASE}
      @IOS    : 11.2={,SUM(DELTA_READ_IO_BYTES) reads,SUM(DELTA_Write_IO_BYTES) writes},default={}
    ]]--
  Options:
      Groupings : The grouping option can be followed by other custimized field, i.e.: '@@NAME -p,p1raw ...'
        -e   : group by event
        -sql : group by event+sql_id (default)
        -p   : group by event+p1,p2,p3
        -pr  : group by event+p1raw,p2raw,p3raw
        -o   : group by event+object_id
        -plan: group by sql plan line(for 11g)
        -proc: group by procedure name
      DataSource:
        -ash : source table is gv$active_session_history(default)
        -dash: source table is dba_hist_active_sess_history
      Filters   :
        -id  : show data for specific sql_id/sid. Usage: [-id] [sql_i|sid]  [starttime] [endtime]
        -u   : only show the data related to current schema. Usage: -u <seconds> [starttime] [endtime]
        -snap: only show the data within specific seconds. Usage: -snap <seconds> [sql_id|sid]
      Addition filter:
        -f   : additional fileter. Usage: -f"<filter>"
        
  Usage examples:  
      1) Show top objects for the specific sql id: @@NAME -o <sql_id> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      2) Show top sqls for the specific sid      : @@NAME <sid> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      3) Show top sqls within recent 60 secs     : @@NAME -snap 60 [sql_id|sid]
      4) Show top objects from dictionary ASH    : @@NAME -dash <sql_id> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      5) Show top objects based on execution plan: @@NAME -plan <sql_id> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      6) Show top sqls with user defined filter  : @@NAME -f"inst_id=1 and username='ABCD'" 
  
  This script references Tanel Poder's script
]]*/
col reads format KMG
col writes format kMG
SELECT * FROM (
    SELECT /*+ LEADING(a) USE_HASH(u) no_expand*/
        round(SUM(c))                                                   Secs
      , ROUND(SUM(c) / (1+(max(sample_time+0) - min(sample_time+0)) * 86400), 1) AAS
      , LPAD(ROUND(RATIO_TO_REPORT(sum(c)) OVER () * 100)||'%',5,' ')||' |' "%This"
      &counter
      , nvl2(qc_session_id,'PARALLEL','SERIAL') "Parallel?"
      , nvl(a.program#,u.username) program#, event_name event
      , &fields &IOS
      , round(SUM(CASE WHEN wait_class IS NULL           THEN c ELSE 0 END)) "CPU"
      , round(SUM(CASE WHEN wait_class ='User I/O'       THEN c ELSE 0 END)) "User I/O"
      , round(SUM(CASE WHEN wait_class ='Application'    THEN c ELSE 0 END)) "Application"
      , round(SUM(CASE WHEN wait_class ='Concurrency'    THEN c ELSE 0 END)) "Concurrency"
      , round(SUM(CASE WHEN wait_class ='Commit'         THEN c ELSE 0 END)) "Commit"
      , round(SUM(CASE WHEN wait_class ='Configuration'  THEN c ELSE 0 END)) "Configuration"
      , round(SUM(CASE WHEN wait_class ='Cluster'        THEN c ELSE 0 END)) "Cluster"
      , round(SUM(CASE WHEN wait_class ='Idle'           THEN c ELSE 0 END)) "Idle"
      , round(SUM(CASE WHEN wait_class ='Network'        THEN c ELSE 0 END)) "Network"
      , round(SUM(CASE WHEN wait_class ='System I/O'     THEN c ELSE 0 END)) "System I/O"
      , round(SUM(CASE WHEN wait_class ='Scheduler'      THEN c ELSE 0 END)) "Scheduler"
      , round(SUM(CASE WHEN wait_class ='Administrative' THEN c ELSE 0 END)) "Administrative"
      , round(SUM(CASE WHEN wait_class ='Queueing'       THEN c ELSE 0 END)) "Queueing"
      , round(SUM(CASE WHEN wait_class ='Other'          THEN c ELSE 0 END)) "Other"
      , TO_CHAR(MIN(sample_time), 'YYYY-MM-DD HH24:MI:SS') first_seen
      , TO_CHAR(MAX(sample_time), 'YYYY-MM-DD HH24:MI:SS') last_seen
    FROM
        (SELECT a.*,sql_plan_hash_value plan_hash,current_obj# obj,nvl2(CURRENT_FILE#,CURRENT_FILE#||','||current_block#,'') block,
            CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
              REGEXP_REPLACE(SUBSTR(a.program,INSTR(a.program,'(')), '\d', 'n')
            END program#,&unit c
           , TO_CHAR(p1, '0XXXXXXXXXXXXXXX') p1raw
           , TO_CHAR(p2, '0XXXXXXXXXXXXXXX') p2raw
           , TO_CHAR(p3, '0XXXXXXXXXXXXXXX') p3raw
           , nvl(event,'['||p1text||nullif('|'||p2text,'|')||nullif('|'||p3text,'|')||']') event_name
        FROM &View a) a
      , all_users u
    WHERE a.user_id = u.user_id (+)
    AND   &filter and (&more_filter)
    GROUP BY nvl2(qc_session_id,'PARALLEL','SERIAL'),nvl(a.program#,u.username),event_name,&fields
    ORDER BY Secs DESC nulls last,&fields
)
WHERE ROWNUM <= 50;
