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
        -u   : only show the data related to current schema. Usage: @@NAME -u <sql_id|sid|event|phv> [starttime] [endtime]
        -snap: only show the data within specific seconds. Usage: @@NAME -snap <seconds> [sql_id|sid]
      Addition filter:
        -noevent: don't show the 'Event' column
        -f      : additional fileter. Usage: @@NAME -f"<filter>"
        
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
      &View: ash={gv$active_session_history}, dash={(select /*+full(a.AWR_CDB_ACTIVE_SESS_HISTORY.ash) full(a.AWR_PDB_ACTIVE_SESS_HISTORY.ash)*/ * FROM &check_access_pdb.active_sess_history a WHERE dbid='&dbid')}
      &BASE: ash={1}, dash={10}
      &ASH : DEFAULT={&view} t={&0}
      &key : DEFAULT={(nvl(upper('&V1'),'A')='A' OR '&V1' IN(&top_sql sql_id,''||session_id,''||sql_plan_hash_value,nvl(event,'ON CPU')))}
      &Range: DEFAULT={sample_time+0 BETWEEN nvl(to_date(nvl('&V2','&STARTTIME'),'YYMMDDHH24MISS'),sysdate-&ela) AND nvl(to_date(nvl('&V3','&ENDTIME'),'YYMMDDHH24MISS'),sysdate+1)}
      &filter: {
            id={&key AND &range},
            snap={sample_time+0>=sysdate-numtodsinterval(0+coalesce('&V2','&V1','30'),'second') AND (trim('&V2') IS NULL OR trim('&V2') IS NOT NULL AND &key)},
            u={user_id=(SELECT user_id FROM &CHECK_ACCESS_USER WHERE username=nvl('&0',sys_context('userenv','current_schema'))) AND &key AND &range}
        }
      &more_filter: DEFAULT={1=1},f={}
      @CHECK_ACCESS_USER: dba_users={dba_users} DEFAULT={all_users}
      @check_access_pdb: awrpdb={awr_pdb_} DEFAULT={dba_hist_}
      @counter: 11.2={, count(DISTINCT sql_id||sql_exec_id||to_char(sql_exec_start,'yyyymmddhh24miss')) "Execs"},DEFAULT={}
      @UNIT   : 11.2={least(nvl(tm_delta_db_time,delta_time),delta_time)*1e-6}, DEFAULT={&BASE}
      @CPU    : 11.2={least(nvl(tm_delta_cpu_time,delta_time),delta_time)*1e-6}, DEFAULT={0}
      @IOS    : 11.2={,sum(delta_read_io_bytes) reads,sum(delta_write_io_bytes) writes,sum(nvl(delta_read_io_bytes,0)+nvl(delta_write_io_bytes,0))/nullif(sum(nvl(delta_read_io_requests,0)+nvl(delta_write_io_requests,0)),0) avg_io},DEFAULT={}
      @V11    : 11.2={} DEFAULT={--}
      @V12    : 12.2={} DEFAULT={--}
      @top_sql: 11.1={top_level_sql_id,} DEFAULT={}
      &wall   : DEFAULT={} wall={count(DISTINCT bucket#)*&base wall,}
      &wall1  : DEFAULT={} wall={--}
    ]]--
]]*/
col reads,writes,AVG_IO format KMG
COL WALL,SECS,AAS FOR smhd2
COL wait for usmhd2
WITH ash_v AS(
    SELECT /*+outline*/
           a.*,
           CASE WHEN :fields LIKE 'wait_class%' THEN ' ' ELSE
               CASE WHEN pro_ LIKE '(%)' AND upper(substr(pro_,2,1))=substr(pro_,2,1) THEN
                    CASE WHEN pro_ LIKE '(%)' AND substr(pro_,2,1) IN('P','W','J') THEN
                        '('||substr(pro_,2,1)||'nnn)'
                    ELSE regexp_replace(pro_,'[0-9a-z]','n') END
               WHEN instr(a.program,'@')>1 THEN
                    nullif(substr(program,1,instr(program,'@')-1),'oracle')
               END
           END program#,
           CASE WHEN :fields LIKE 'wait_class%' THEN to_number(NULL) ELSE user_id END u_id
    FROM (SELECT /*+full(a.a) leading(a.a) use_hash(a.a a.s) swap_join_inputs(a.s)
                    full(A.GV$ACTIVE_SESSION_HISTORY.A)
                    leading(A.GV$ACTIVE_SESSION_HISTORY.A)
                    use_hash(A.GV$ACTIVE_SESSION_HISTORY.A A.GV$ACTIVE_SESSION_HISTORY.S)
                    swap_join_inputs(A.GV$ACTIVE_SESSION_HISTORY.S)
                    use_hash(@GV_ASHV A@GV_ASHV)
                    opt_param('optimizer_index_cost_adj',10000)
                    opt_param('optimizer_index_caching',0)
                */
                a.*,
                coalesce(sql_id, &top_sql NULL) "SQL Id",
                sql_plan_hash_value plan_hash,
                nvl(trim(CASE 
                        WHEN current_obj# < -1 THEN
                            'Temp I/O'
                        WHEN current_obj# > 0 THEN 
                             ''||current_obj#
                        WHEN p2text='id1' THEN
                             ''||p2
                        WHEN p3text IN('(identifier<<32)+(namespace<<16)+mode','100*mode+namespace') THEN 
                            ''||trunc(p3/power(16,8))
                        WHEN p3text LIKE '%namespace' AND p3>power(16,8)*4294950912 THEN
                            'Undo'
                        WHEN p3text LIKE '%namespace' AND p3>power(16,8) THEN 
                             ''||trunc(p3/power(16,8))
                        WHEN p3text LIKE '%namespace' THEN 
                            'X$KGLST#'||trunc(mod(p3,power(16,8))/power(16,4))
                        WHEN p1text LIKE 'cache id' THEN 
                            (SELECT parameter FROM v$rowcache WHERE cache#=p1 AND ROWNUM<2)
                        WHEN event LIKE 'latch%' AND p2text='number' THEN 
                            (SELECT name FROM v$latchname WHERE latch#=p2 AND ROWNUM<2)
                        WHEN p3text='class#' THEN
                            (SELECT class FROM (SELECT class, ROWNUM r FROM v$waitstat) WHERE r=p3 AND ROWNUM<2)
                        WHEN p1text ='file#' AND p2text='block#' THEN 
                            'file#'||p1||' block#'||p2
                        WHEN p3text IN('block#','block') THEN 
                            'file#'||dbms_utility.data_block_address_file(p3)||' block#'||dbms_utility.data_block_address_block(p3)    
                        WHEN current_obj# = 0 THEN 'Undo'
                        --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                        --when c.class is not null then c.class
                    END),''||current_obj#)  obj
              , nvl2(current_file#,current_file#||','||current_block#,'') block
              , substr(a.program,-6) pro_,&unit c,&CPU cpu
              , floor((sample_time+0-DATE'1970-1-1')*86400/&base) bucket#
              , lpad(sys_op_numtoraw(p1),16,'0') p1raw
              , lpad(sys_op_numtoraw(p2),16,'0') p2raw
              , lpad(sys_op_numtoraw(p3),16,'0') p3raw
              , greatest(time_waited,wait_time) wait
              , nvl(event,nullif('['||p1text||nullif('|'||p2text,'|')||nullif('|'||p3text,'|')||']','[]')) event_name
        &v11  , sql_plan_operation||' '||sql_plan_options operation
        &V11  , CASE WHEN in_connection_mgmt      = 'Y' THEN 'CONNECTION_MGMT '          END ||
        &V11    CASE WHEN in_parse                = 'Y' THEN 'PARSE '                    END ||
        &V11    CASE WHEN in_hard_parse           = 'Y' THEN 'HARD_PARSE '               END ||
        &V11    CASE WHEN in_sql_execution        = 'Y' THEN 'SQL_EXECUTION '            END ||
        &V11    CASE WHEN in_plsql_execution      = 'Y' THEN 'PLSQL_EXECUTION '          END ||
        &V11    CASE WHEN in_plsql_rpc            = 'Y' THEN 'PLSQL_RPC '                END ||
        &V11    CASE WHEN in_plsql_compilation    = 'Y' THEN 'PLSQL_COMPILATION '        END ||
        &V11    CASE WHEN in_java_execution       = 'Y' THEN 'JAVA_EXECUTION '           END ||
        &V11    CASE WHEN in_bind                 = 'Y' THEN 'BIND '                     END ||
        &V11    CASE WHEN in_cursor_close         = 'Y' THEN 'CURSOR_CLOSE '             END ||
        &V11    CASE WHEN in_sequence_load        = 'Y' THEN 'SEQUENCE_LOAD '            END ||
        &V12    CASE WHEN in_inmemory_query       = 'Y' THEN 'IN_INMEMORY_QUERY'         END ||
        &V12    CASE WHEN in_inmemory_populate    = 'Y' THEN 'IN_INMEMORY_POPULATE'      END ||
        &V12    CASE WHEN in_inmemory_prepopulate = 'Y' THEN 'IN_INMEMORY_PREPOPULATE'   END ||
        &V12    CASE WHEN in_inmemory_repopulate  = 'Y' THEN 'IN_INMEMORY_REPOPULATE'    END ||
        &V12    CASE WHEN in_inmemory_trepopulate = 'Y' THEN 'IN_INMEMORY_TREPOPULATE'   END ||
        &V12    CASE WHEN in_tablespace_encryption= 'Y' THEN 'IN_TABLESPACE_ENCRYPTION'  END ||
        &V11   '' phase
        FROM &ash a) a
    WHERE &filter AND (&more_filter))
SELECT * FROM (
    SELECT /*+LEADING(a) USE_HASH(u) swap_join_inputs(u) no_expand */
          &wall round(sum(c)) secs
          , round(sum(&base)) aas
          , lpad(round(ratio_to_report(sum(c)) OVER () * 100)||'%',5,' ')||' |' "%This"
          &counter
          &wall1 , nvl2(qc_session_id,'PARALLEL','SERIAL') "Parallel?"
          &wall1 , nvl(a.program#,(SELECT username FROM &CHECK_ACCESS_USER WHERE user_id=a.u_id)) program#
          &wall1 , &ev &wait
          , &fields &IOS
          , round(sum(CASE WHEN wait_class IS NULL AND cpu=0 THEN c ELSE 0 END+cpu)) "CPU"
          , round(sum(CASE WHEN wait_class ='User I/O'       THEN c ELSE 0 END)) "User I/O"
          , round(sum(CASE WHEN wait_class ='Application'    THEN c ELSE 0 END)) "Application"
          , round(sum(CASE WHEN wait_class ='Concurrency'    THEN c ELSE 0 END)) "Concurrency"
          , round(sum(CASE WHEN wait_class ='Commit'         THEN c ELSE 0 END)) "Commit"
          , round(sum(CASE WHEN wait_class ='Configuration'  THEN c ELSE 0 END)) "Configuration"
          , round(sum(CASE WHEN wait_class ='Cluster'        THEN c ELSE 0 END)) "Cluster"
          , round(sum(CASE WHEN wait_class ='Idle'           THEN c ELSE 0 END)) "Idle"
          , round(sum(CASE WHEN wait_class ='Network'        THEN c ELSE 0 END)) "Network"
          , round(sum(CASE WHEN wait_class ='System I/O'     THEN c ELSE 0 END)) "System I/O"
          , round(sum(CASE WHEN wait_class ='Scheduler'      THEN c ELSE 0 END)) "Scheduler"
          , round(sum(CASE WHEN wait_class ='Administrative' THEN c ELSE 0 END)) "Administrative"
          , round(sum(CASE WHEN wait_class ='Queueing'       THEN c ELSE 0 END)) "Queueing"
          , round(sum(CASE WHEN wait_class ='Other'          THEN c ELSE 0 END)) "Other"
          , to_char(min(sample_time), 'YYYY-MM-DD HH24:MI:SS') first_seen
          , to_char(max(sample_time), 'YYYY-MM-DD HH24:MI:SS') last_seen
    FROM  ash_v a
    GROUP BY &wall1 nvl2(qc_session_id,'PARALLEL','SERIAL'),a.program#,&ev,
             a.u_id,&fields
    ORDER BY 1 DESC NULLS LAST,secs DESC NULLS LAST,aas DESC,&fields
)
WHERE ROWNUM <= 50;
