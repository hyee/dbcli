/*[[
  Get ASH top event. Usage: ashtop [-sql|-p|-none|-pr|-o|-plan|-ash|-dash|-snap|-f] [fields] [filters]
  Parameters:
      fields : combination of columns concated by comma. Available columns: see v$active_session_history and dba_users
               available options: -sql,-p,-pr,-o,-plan,-none
      filters: available options: -id, -snap, -f
      Source : -ash: gv$active_Session_history    -dash: Dba_Hist_Active_Sess_History 
    --[[
      &fields: sql={sql_id}, p={p1,p2,p3,p3text},pr={p1raw,p2raw,p3raw}, o={obj},plan={plan_hash,current_obj#,SQL_PLAN_LINE_ID} none={1}
      &View: ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
      &BASE: ash={1}, dash={10}
      &filter: {
            id={(trim(:V1) is null or upper(:V1)='A' or :V1 in(sql_id,''||session_id)) and 
                     sample_time+0 between nvl(to_date(nullif(:V2,'a'),'YYMMDDHH24MISS'),sysdate-1) and nvl(to_date(nullif(:V3,'a'),'YYMMDDHH24MISS'),sysdate)
                    &V4},
            snap={sample_time+0>=sysdate-nvl(0+:V1,30)/86400 and (:V2 is null or :V2 in(sql_id,''||session_id)) &V3}
        }
      &more_filter: default={1=1},f={}
      @counter: 11.2={, count(distinct sql_exec_id) "Execs"},10.1={}
    ]]--
  Examples:
      ora ashtop -sql               =  ora ashtop "sql_id,session_state,event"
      ora ashtop -p,qc_session_id   =  ora ashtop "session_state,event,current_obj#,p3text,qc_session_id"
      ora ashtop -dash              =  Query dictionary ash view instead of dynamic ash view     
      ora ashtop -plan              =  ora ashtop "plan_hash,event,current_obj#,SQL_PLAN_LINE_ID"
      ora ashtop -p", qc_session_id, qc_session_serial#"  = ora ashtop "-p, qc_session_id, qc_session_serial#"
]]*/

SELECT * FROM (
    SELECT /*+ LEADING(a) USE_HASH(u) no_expand*/
        round(SUM(c))                                                   Secs
      , ROUND(SUM(c) / (1+(max(sample_time+0) - min(sample_time+0)) * 86400), 1) AAS
      , LPAD(ROUND(RATIO_TO_REPORT(sum(c)) OVER () * 100)||'%',5,' ')||' |' "%This"
      &counter
      , nvl2(qc_session_id,'PARALLEL','SERIAL') "Parallel?"
      , nvl(a.program#,u.username) program#, event_name event
      , &fields
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
            END program#,&BASE c
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
