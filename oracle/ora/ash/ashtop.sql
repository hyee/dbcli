/*[[
  Get ASH top event, type 'help @@NAME' for more info. Usage: @@NAME [-sql|-p|-none|-pr|-o|-plan|-ash|-dash|-snap|-f"<filter>"] [-t"<ash_dump_table>"] [fields]
  
  Options:
  ========
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
        -t   : source table is <ash_dump_table>
      Filters   :
        -id  : show data for specific sql_id/sid. Usage: [-id] [sql_id|sid]  [starttime] [endtime]
        -u   : only show the data related to current schema. Usage: -u <seconds> [starttime] [endtime]
        -snap: only show the data within specific seconds. Usage: -snap <seconds> [sql_id|sid]
      Addition filter:
        -f   : additional fileter. Usage: -f"<filter>"
        
  Usage Examples:
  ===============
      1) Show top objects for the specific sql id: @@NAME -o <sql_id> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      2) Show top sqls for the specific sid      : @@NAME <sid> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      3) Show top sqls within recent 60 secs     : @@NAME -snap 60 [sql_id|sid]
      4) Show top objects from dictionary ASH    : @@NAME -dash <sql_id> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      5) Show top objects based on execution plan: @@NAME -plan <sql_id> [YYMMDDHH24MISS] [YYMMDDHH24MISS]
      6) Show top sqls with user defined filter  : @@NAME -f"inst_id=1 and username='ABCD'" 
  
  Sample Outputs:
  ===============
    SECS AAS  %This  Execs Parallel? PROGRAM#  EVENT                                              SQL_ID       SQL_OPNAME     READS    WRITES   CPU ...
    ---- --- ------- ----- --------- -------- ------------------------------------------------ ------------- -------------- --------- --------- --- ...
      35  35   29% |     1 SERIAL    SYS      [file number|first dba|block cnt]                c5rrtjvaqr9d3 SELECT          81.39 MB      0  B  35 ...
      28 363   23% |     0 SERIAL    (PSPn)   [timeout]                                                                          0  B      0  B  57 ...
      14  15   12% |     1 SERIAL    SYS      [driver id|#bytes]                               ahwx914ga4qag SELECT         113.00 KB      0  B  14 ...
      11  11    9% |     1 SERIAL    SYS      [file#|block#|blocks]                            c5rrtjvaqr9d3 SELECT          33.30 MB      0  B  11 ...
      10 153    8% |     0 SERIAL    (DIAn)   [component|where|wait time(millisec)]                                              0  B      0  B  17 ...
       8   5    6% |     1 SERIAL    SYS      [driver id|#bytes]                               fjfh2kphmfq0h SELECT         125.70 MB      0  B   8 ...
       4   3    3% |     3 SERIAL    SYS      [driver id|#bytes]                               gvph4rn0sv7kg SELECT         561.00 KB  24.00 KB   4 ...
       2   4    1% |     4 SERIAL    SYS      [file number|first dba|block cnt]                032x0n8n5g5sy SELECT          14.31 MB      0  B   2 ...
       2   1    1% |     1 SERIAL    SYS      [driver id|#bytes]                               ar59zgzwt44cb SELECT          23.40 MB      0  B   1 ...
       1   1    1% |     1 SERIAL    SYS      [file#|block#|blocks]                            032x0n8n5g5sy SELECT           2.84 MB      0  B   1 ...
       1   1    1% |     1 SERIAL    (Mnnn)   db file sequential read                          1uym1vta995yb INSERT           1.91 MB      0  B   1 ...
       1   2    1% |     2 SERIAL    (Mnnn)   db file sequential read                          3s58mgk0uy2ws INSERT           2.26 MB      0  B   1 ...

   --[[
      &fields: {
            sql={sql_id &V11,sql_opname &0},
            e={null}, 
            p={p1,p2,p3,p3text &0},
            pr={p1raw,p2raw,p3raw &0}, 
            o={obj &0},
            plan={plan_hash,obj,SQL_PLAN_LINE_ID &0} 
            none={1},
            c={},
            proc={sql_id,PLSQL_ENTRY_OBJECT_ID &0},
        }
      &ela : ash={1} dash={7}
      &View: ash={gv$active_session_history}, dash={&check_access_pdb.Active_Sess_History}
      &BASE: ash={1}, dash={10}
      &ASH : default={&view} t={&0}
      &Range: default={sample_time+0 between nvl(to_date(nvl(:V2,:starttime),'YYMMDDHH24MISS'),sysdate-&ela) and nvl(to_date(nvl(:V3,:endtime),'YYMMDDHH24MISS'),sysdate+1)}
      &filter: {
            id={(trim('&1') is null or upper(:V1)='A' or :V1 in(&top_sql sql_id,''||session_id,''||sql_plan_hash_value,nvl(event,'ON CPU'))) and &range},
            snap={sample_time+0>=sysdate-nvl(0+:V1,30)/86400 and (:V2 is null or :V2 in(&top_sql sql_id,''||session_id,'event')) &V3},
            u={user_id=(select user_id from &CHECK_ACCESS_USER where username=nvl('&0',sys_context('userenv','current_schema'))) and &range}
        }
      &more_filter: default={1=1},f={}
      @CHECK_ACCESS_USER: dba_users={dba_users} default={all_users}
      @check_access_pdb: pdb/awr_pdb_snapshot={AWR_PDB_} default={DBA_HIST_}
      @counter: 11.2={, count(distinct sql_exec_id||to_char(sql_exec_start,'yyyymmddhh24miss')) "Execs"},default={}
      @UNIT   : 11.2={least(nvl(tm_delta_db_time,delta_time),DELTA_TIME)*1e-6}, default={&BASE}
      @CPU    : 11.2={least(nvl(tm_delta_cpu_time,delta_time),DELTA_TIME)*1e-6}, default={0}
      @IOS    : 11.2={,SUM(DELTA_READ_IO_BYTES) reads,SUM(DELTA_Write_IO_BYTES) writes},default={}
      @V11    : 11.2={} default={--}
      @V12    : 12.2={} default={--}
      @top_sql: 11.1={top_level_sql_id,} default={}
    ]]--
]]*/
col reads format KMG
col writes format kMG
WITH ASH_V AS(
    SELECT a.*,
           CASE WHEN PRO_ LIKE '(%)' AND upper(substr(PRO_,2,1))=substr(PRO_,2,1) THEN
                CASE WHEN PRO_ LIKE '(%)' AND substr(PRO_,2,1) IN('P','W','J') THEN
                    '('||substr(PRO_,2,1)||'nnn)'
                ELSE regexp_replace(PRO_,'[0-9a-z]','n') END
           WHEN instr(a.program,'@')>1 THEN
                nullif(substr(program,1,instr(program,'@')-1),'oracle')
           END program#
    FROM (SELECT /*+MERGE PARALLEL(4)
                  full(a.a) leading(a.a) use_hash(a.a a.s) swap_join_inputs(a.s)
                  use_hash(a.V_$ACTIVE_SESSION_HISTORY.V$ACTIVE_SESSION_HISTORY.GV$ACTIVE_SESSION_HISTORY.A)
                  FULL(A.GV$ACTIVE_SESSION_HISTORY.A) leading(A.GV$ACTIVE_SESSION_HISTORY.A) 
                  use_hash(A.GV$ACTIVE_SESSION_HISTORY.A A.GV$ACTIVE_SESSION_HISTORY.S) 
                  swap_join_inputs(A.GV$ACTIVE_SESSION_HISTORY.S)

                  FULL(A.ASH) FULL(A.EVT) swap_join_inputs(A.EVT) PX_JOIN_FILTER(A.ASH)
                  OPT_ESTIMATE(TABLE A.ASH ROWS=30000000)
                  full(A.&check_access_pdb.ACTIVE_SESS_HISTORY.ASH)
                  full(A.&check_access_pdb.ACTIVE_SESS_HISTORY.EVT)
                  swap_join_inputs(A.&check_access_pdb.ACTIVE_SESS_HISTORY.EVT)
                  PX_JOIN_FILTER(A.&check_access_pdb.ACTIVE_SESS_HISTORY.ASH)
                  OPT_ESTIMATE(TABLE D.&check_access_pdb.ACTIVE_SESS_HISTORY.ASH ROWS=30000000)
                */ 
                a.*,
                sql_plan_hash_value plan_hash,
                nvl(trim(case 
                        when current_obj# < -1 then
                            'Temp I/O'
                        when current_obj# > 0 then 
                             ''||current_obj#
                        when p3text like '%namespace' and p3>power(16,8)*4294950912 then
                            'Undo'
                        when p3text like '%namespace' and p3>power(16,8) then 
                             ''||trunc(p3/power(16,8))
                        when p3text like '%namespace' then 
                            'X$KGLST#'||trunc(mod(p3,power(16,8))/power(16,4))
                        when p1text like 'cache id' then 
                            (select parameter from v$rowcache where cache#=p1 and rownum<2)
                        when event like 'latch%' and p2text='number' then 
                            (select name from v$latchname where latch#=p2 and rownum<2)
                        when p3text='class#' then
                            (select class from (SELECT class, ROWNUM r from v$waitstat) where r=p3 and rownum<2)
                        when p1text ='file#' and p2text='block#' then 
                            'file#'||p1||' block#'||p2
                        when p3text in('block#','block') then 
                            'file#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(p3)||' block#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_BLOCK(p3)    
                        when current_obj# = 0 then 'Undo'
                        --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                        --when c.class is not null then c.class
                    end),''||current_obj#)  obj,
                nvl2(CURRENT_FILE#,CURRENT_FILE#||','||current_block#,'') block,
                SUBSTR(a.program,-6) PRO_,&unit c,&CPU CPU
              , TO_CHAR(p1, 'fm0XXXXXXXXXXXXXXX') p1raw
              , TO_CHAR(p2, 'fm0XXXXXXXXXXXXXXX') p2raw
              , TO_CHAR(p3, 'fm0XXXXXXXXXXXXXXX') p3raw
              , nvl(event,nullif('['||p1text||nullif('|'||p2text,'|')||nullif('|'||p3text,'|')||']','[]')) event_name
        &V11  , CASE WHEN IN_CONNECTION_MGMT      = 'Y' THEN 'CONNECTION_MGMT '          END ||
        &V11    CASE WHEN IN_PARSE                = 'Y' THEN 'PARSE '                    END ||
        &V11    CASE WHEN IN_HARD_PARSE           = 'Y' THEN 'HARD_PARSE '               END ||
        &V11    CASE WHEN IN_SQL_EXECUTION        = 'Y' THEN 'SQL_EXECUTION '            END ||
        &V11    CASE WHEN IN_PLSQL_EXECUTION      = 'Y' THEN 'PLSQL_EXECUTION '          END ||
        &V11    CASE WHEN IN_PLSQL_RPC            = 'Y' THEN 'PLSQL_RPC '                END ||
        &V11    CASE WHEN IN_PLSQL_COMPILATION    = 'Y' THEN 'PLSQL_COMPILATION '        END ||
        &V11    CASE WHEN IN_JAVA_EXECUTION       = 'Y' THEN 'JAVA_EXECUTION '           END ||
        &V11    CASE WHEN IN_BIND                 = 'Y' THEN 'BIND '                     END ||
        &V11    CASE WHEN IN_CURSOR_CLOSE         = 'Y' THEN 'CURSOR_CLOSE '             END ||
        &V11    CASE WHEN IN_SEQUENCE_LOAD        = 'Y' THEN 'SEQUENCE_LOAD '            END ||
        &V12    CASE WHEN IN_INMEMORY_QUERY       = 'Y' THEN 'IN_INMEMORY_QUERY'         END ||
        &V12    CASE WHEN IN_INMEMORY_POPULATE    = 'Y' THEN 'IN_INMEMORY_POPULATE'      END ||
        &V12    CASE WHEN IN_INMEMORY_PREPOPULATE = 'Y' THEN 'IN_INMEMORY_PREPOPULATE'   END ||
        &V12    CASE WHEN IN_INMEMORY_REPOPULATE  = 'Y' THEN 'IN_INMEMORY_REPOPULATE'    END ||
        &V12    CASE WHEN IN_INMEMORY_TREPOPULATE = 'Y' THEN 'IN_INMEMORY_TREPOPULATE'   END ||
        &V12    CASE WHEN IN_TABLESPACE_ENCRYPTION= 'Y' THEN 'IN_TABLESPACE_ENCRYPTION'  END ||
        &V11   '' phase
        FROM &ash a) a
    WHERE &filter and (&more_filter))
SELECT * FROM (
    SELECT /*+LEADING(a) USE_HASH(u) swap_join_inputs(u) no_expand opt_param('_sqlexec_hash_based_distagg_enabled' true) */
        round(SUM(c))                                                   Secs
      , ROUND(sum(&base)) AAS
      , LPAD(ROUND(RATIO_TO_REPORT(sum(c)) OVER () * 100)||'%',5,' ')||' |' "%This"
      &counter
      , nvl2(qc_session_id,'PARALLEL','SERIAL') "Parallel?"
      , nvl(a.program#,(select username from &CHECK_ACCESS_USER where user_id=a.user_id)) program#, event_name event
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
    FROM ASH_V A
    GROUP BY nvl2(qc_session_id,'PARALLEL','SERIAL'),a.program#,a.user_id,event_name,&fields
    ORDER BY secs DESC nulls last,&fields
)
WHERE ROWNUM <= 50;
