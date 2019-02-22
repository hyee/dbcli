/*[[
  Get ASH top event, type 'help @@NAME' for more info. Usage: @@NAME [-sql|-p|-none|-pr|-o|-plan|-ash|-dash|-snap|-f] {[fields] [filters]}
  
   --[[
      &fields: {
            sql={sql_id},
            e={null}, 
            p={p1,p2,p3,p3text &0},
            pr={p1raw,p2raw,p3raw &0}, 
            o={obj &0},
            plan={plan_hash,current_obj#,SQL_PLAN_LINE_ID &0} 
            none={1},
            c={},
            proc={sql_id,PLSQL_ENTRY_OBJECT_ID &0},
        }
      &View: ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
      &BASE: ash={1}, dash={10}
      &Range: default={sample_time+0 between nvl(to_date(nvl(:V2,:starttime),'YYMMDDHH24MISS'),sysdate-1) and nvl(to_date(nvl(:V3,:endtime),'YYMMDDHH24MISS'),sysdate)}
      &filter: {
            id={(trim('&1') is null or upper(:V1)='A' or :V1 in(sql_id,''||session_id,event)) and &range
                    &V4},
            snap={sample_time+0>=sysdate-nvl(0+:V1,30)/86400 and (:V2 is null or :V2 in(sql_id,''||session_id,'event')) &V3},
            u={username=nvl('&0',sys_context('userenv','current_schema')) and &range}
        }
      &more_filter: default={1=1},f={}
      @counter: 11.2={, count(distinct sql_exec_id||to_char(sql_exec_start,'yyyymmddhh24miss')) "Execs"},default={}
      @UNIT   : 11.2={least(nvl(tm_delta_db_time,delta_time),DELTA_TIME)*1e-6}, default={&BASE}
      @CPU    : 11.2={least(nvl(tm_delta_cpu_time,delta_time),DELTA_TIME)*1e-6}, default={0}
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
        -id  : show data for specific sql_id/sid. Usage: [-id] [sql_id|sid]  [starttime] [endtime]
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
    SELECT /*+ LEADING(a) USE_HASH(u) swap_join_inputs(u) no_expand opt_param('_sqlexec_hash_based_distagg_enabled' true)*/
        round(SUM(c))                                                   Secs
      , ROUND(sum(&base)) AAS
      , LPAD(ROUND(RATIO_TO_REPORT(sum(c)) OVER () * 100)||'%',5,' ')||' |' "%This"
      &counter
      , nvl2(qc_session_id,'PARALLEL','SERIAL') "Parallel?"
      , nvl(a.program#,u.username) program#, event_name event
      , &fields &IOS
      , round(SUM(CASE WHEN wait_class IS NULL AND CPU=0 THEN c ELSE 0 END+CPU)) "CPU"
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
            END program#,&unit c,&CPU CPU
           , TO_CHAR(p1, '0XXXXXXXXXXXXXXX') p1raw
           , TO_CHAR(p2, '0XXXXXXXXXXXXXXX') p2raw
           , TO_CHAR(p3, '0XXXXXXXXXXXXXXX') p3raw
           , nvl(event,'['||p1text||nullif('|'||p2text,'|')||nullif('|'||p3text,'|')||']') event_name
           , CASE WHEN IN_CONNECTION_MGMT      = 'Y' THEN 'CONNECTION_MGMT '          END ||
            CASE WHEN IN_PARSE                = 'Y' THEN 'PARSE '                    END ||
            CASE WHEN IN_HARD_PARSE           = 'Y' THEN 'HARD_PARSE '               END ||
            CASE WHEN IN_SQL_EXECUTION        = 'Y' THEN 'SQL_EXECUTION '            END ||
            CASE WHEN IN_PLSQL_EXECUTION      = 'Y' THEN 'PLSQL_EXECUTION '          END ||
            CASE WHEN IN_PLSQL_RPC            = 'Y' THEN 'PLSQL_RPC '                END ||
            CASE WHEN IN_PLSQL_COMPILATION    = 'Y' THEN 'PLSQL_COMPILATION '        END ||
            CASE WHEN IN_JAVA_EXECUTION       = 'Y' THEN 'JAVA_EXECUTION '           END ||
            CASE WHEN IN_BIND                 = 'Y' THEN 'BIND '                     END ||
            CASE WHEN IN_CURSOR_CLOSE         = 'Y' THEN 'CURSOR_CLOSE '             END ||
            CASE WHEN IN_SEQUENCE_LOAD        = 'Y' THEN 'SEQUENCE_LOAD '            END ||
    --        CASE WHEN IN_INMEMORY_QUERY       = 'Y' THEN 'IN_INMEMORY_QUERY'         END ||
    --        CASE WHEN IN_INMEMORY_POPULATE    = 'Y' THEN 'IN_INMEMORY_POPULATE'      END ||
    --        CASE WHEN IN_INMEMORY_PREPOPULATE = 'Y' THEN 'IN_INMEMORY_PREPOPULATE'   END ||
    --        CASE WHEN IN_INMEMORY_REPOPULATE  = 'Y' THEN 'IN_INMEMORY_REPOPULATE'    END ||
    --        CASE WHEN IN_INMEMORY_TREPOPULATE = 'Y' THEN 'IN_INMEMORY_TREPOPULATE'   END ||
    --        CASE WHEN IN_TABLESPACE_ENCRYPTION= 'Y' THEN 'IN_TABLESPACE_ENCRYPTION'  END ||
            '' phase
        FROM &View a) a
      , all_users u
    WHERE a.user_id = u.user_id (+)
    AND   &filter and (&more_filter)
    GROUP BY nvl2(qc_session_id,'PARALLEL','SERIAL'),nvl(a.program#,u.username),event_name,&fields
    ORDER BY secs DESC nulls last,&fields
)
WHERE ROWNUM <= 50;
