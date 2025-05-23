/*[[
  Get ASH top event, type 'help @@NAME' for more info. Usage: @@NAME [{<sql_id|sid|event|phv> {[YYMMDDHH24MI] [YYMMDDHH24MI] | -snap <secs>}} | -u] [<other options>]
  
  Options:
  ========
        -wall : show & order by wall clock
      Groupings : The grouping option can be followed by other custimized field, i.e.: '@@NAME -p,p1raw ...'
        -e    : group by event
        -sql  : group by event+sql_id (default)
        -p    : group by event+p1,p2,p3
        -pr   : group by event+p1raw,p2raw,p3raw
        -o    : group by event+object_id
        -plan : group by sql plan line(for 11g)
        -proc : group by procedure name
        -phase: group by phase(parsing/executing/etc)
        -op   : group by plan operation + obj
      DataSource:
        -ash : source table is gv$active_session_history(default)
        -dash: source table is dba_hist_active_sess_history
        -t   : source table is <ash_dump_table>
      Filters   :
        -id  : show data for specific sql_id/sid. Usage: @@NAME [-id] [sql_id|sid] [starttime] [endtime]
        -u   : only show the data related to current schema. Usage: @@NAME -u <seconds> [starttime] [endtime]
        -snap: only show the data within specific seconds. Usage: @@NAME -snap <seconds> [sql_id|sid]
      Addition filter:
        -f   : additional fileter. Usage: @@NAME -f"<filter>"
        
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
            default={"SQL Id" &V11,sql_opname &0},
            sql={"SQL Id" &V11,sql_opname &0},
            m={force_matching_signature &V11, sql_opname &0}
            e={wait_class &0}, 
            p={p1,p2,p3,p3text &0},
            pr={p1raw,p2raw,p3raw &0}, 
            o={obj &0},
            plan={plan_hash,obj,SQL_PLAN_LINE_ID &0} 
            none={1},
            op={operation,obj &0}
            proc={"SQL Id",PLSQL_ENTRY_OBJECT_ID &0}
            phase={phase &0}
        }
      &ev  : default={event_name}  noevent={1}
      &wait: default={,median(nullif(wait,0)) wait} noevent={}
      &ela : ash={1} dash={7}
      &View: ash={gv$active_session_history}, dash={(select * from &check_access_pdb.Active_Sess_History where dbid=&dbid)}
      &BASE: ash={1}, dash={10}
      &ASH : default={&view} t={&0}
      &Range: default={sample_time+0 between nvl(to_date(nvl('&V2','&STARTTIME'),'YYMMDDHH24MISS'),sysdate-&ela) and nvl(to_date(nvl('&V3','&ENDTIME'),'YYMMDDHH24MISS'),sysdate+1)}
      &filter: {
            id={(trim('&V1') is null or upper('&V1')='A' or '&V1' in(&top_sql sql_id,''||session_id,''||sql_plan_hash_value,nvl(event,'ON CPU'))) and &range},
            snap={sample_time+0>=sysdate-NUMTODSINTERVAL(0+coalesce('&V2','&V1','30'),'second') and (trim('&V2') is null or trim('&V2') is not null and (upper('&V1')='A' or '&V1' in(&top_sql sql_id,''||session_id,''||sql_plan_hash_value,nvl(event,'ON CPU')))) &V3},
            u={user_id=(select user_id from &CHECK_ACCESS_USER where username=nvl('&0',sys_context('userenv','current_schema'))) and &range}
        }
      &more_filter: default={1=1},f={}
      @CHECK_ACCESS_USER: dba_users={dba_users} default={all_users}
      @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_}
      @counter: 11.2={, count(distinct sql_id||sql_exec_id||to_char(sql_exec_start,'yyyymmddhh24miss')) "Execs"},default={}
      @UNIT   : 11.2={least(nvl(tm_delta_db_time,delta_time),DELTA_TIME)*1e-6}, default={&BASE}
      @CPU    : 11.2={least(nvl(tm_delta_cpu_time,delta_time),DELTA_TIME)*1e-6}, default={0}
      @IOS    : 11.2={,SUM(DELTA_READ_IO_BYTES) reads,SUM(DELTA_Write_IO_BYTES) writes,SUM(nvl(DELTA_READ_IO_BYTES,0)+nvl(DELTA_Write_IO_BYTES,0))/nullif(SUM(nvl(DELTA_READ_IO_REQUESTS,0)+nvl(DELTA_WRITE_IO_REQUESTS,0)),0) AVG_IO},default={}
      @V11    : 11.2={} default={--}
      @V12    : 12.2={} default={--}
      @top_sql: 11.1={top_level_sql_id,} default={}
      &wall   : default={} wall={count(distinct bucket#)*&base wall,}
      &wall1  : default={} wall={--}
    ]]--
]]*/
col reads,writes,AVG_IO format KMG
COL WALL,SECS,AAS FOR smhd2
COL wait for usmhd2
WITH ASH_V AS(
    SELECT /*+outline*/
           a.*,
           decode(:fields,'wait_class',' ',
           CASE WHEN PRO_ LIKE '(%)' AND upper(substr(PRO_,2,1))=substr(PRO_,2,1) THEN
                CASE WHEN PRO_ LIKE '(%)' AND substr(PRO_,2,1) IN('P','W','J') THEN
                    '('||substr(PRO_,2,1)||'nnn)'
                ELSE regexp_replace(PRO_,'[0-9a-z]','n') END
           WHEN instr(a.program,'@')>1 THEN
                nullif(substr(program,1,instr(program,'@')-1),'oracle')
           END) program#,
           decode(:fields,'wait_class',to_number(null),user_id) u_id
    FROM (SELECT /*+full(a.a) leading(a.a) use_hash(a.a a.s) swap_join_inputs(a.s)
                    full(A.GV$ACTIVE_SESSION_HISTORY.A)
                    leading(A.GV$ACTIVE_SESSION_HISTORY.A)
                    use_hash(A.GV$ACTIVE_SESSION_HISTORY.A A.GV$ACTIVE_SESSION_HISTORY.S)
                    swap_join_inputs(A.GV$ACTIVE_SESSION_HISTORY.S)
                    use_hash(@GV_ASHV A@GV_ASHV) 
                */
                a.*,
                coalesce(sql_id, &top_sql null) "SQL Id",
                sql_plan_hash_value plan_hash,
                nvl(trim(case 
                        when current_obj# < -1 then
                            'Temp I/O'
                        when current_obj# > 0 then 
                             ''||current_obj#
                        when p2text='id1' then
                             ''||p2
                        when p3text in('(identifier<<32)+(namespace<<16)+mode','100*mode+namespace') then 
                            ''||trunc(p3/power(16,8))
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
              , floor((sample_time+0-date'1970-1-1')*86400/&base) bucket#
              , lpad(sys_op_numtoraw(p1),16,'0') p1raw
              , lpad(sys_op_numtoraw(p2),16,'0') p2raw
              , lpad(sys_op_numtoraw(p3),16,'0') p3raw
              , greatest(time_waited,wait_time) wait
              , nvl(event,nullif('['||p1text||nullif('|'||p2text,'|')||nullif('|'||p3text,'|')||']','[]')) event_name
        &v11  , SQL_PLAN_OPERATION||' '||SQL_PLAN_OPTIONS OPERATION
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
    SELECT /*+LEADING(a) USE_HASH(u) swap_join_inputs(u) no_expand 
           */
        &wall round(SUM(c)) Secs
      , ROUND(sum(&base)) AAS
      , LPAD(ROUND(RATIO_TO_REPORT(sum(c)) OVER () * 100)||'%',5,' ')||' |' "%This"
      &counter
      &wall1 , nvl2(qc_session_id,'PARALLEL','SERIAL') "Parallel?"
      &wall1 , nvl(a.program#,(select username from &CHECK_ACCESS_USER where user_id=a.u_id)) program#
      &wall1 , &ev &wait
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
    GROUP BY &wall1 nvl2(qc_session_id,'PARALLEL','SERIAL'),a.program#,&ev,
             a.u_id,&fields
    ORDER BY 1 desc nulls last,secs DESC nulls last,&fields
)
WHERE ROWNUM <= 50;
