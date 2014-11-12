/*[[Get ASH top event. Usage: ashtop [-sql|-p|-ash|-dash|-snap] [group_columns] [sql_id] [from_time] [to_time(YYMMDDHH24MI)]
  Parameters:
      group_columns: combination of columns concated by comma. Available columns: see v$active_session_history and dba_users
      --[[
  Templates:
      &V7: sql={sql_id,event}, p={event,current_obj#,p3text}, plan={plan_hash,event,current_obj#,SQL_PLAN_LINE_ID}
	  &V9: ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
	  &V8: {
            sql_id={(trim(:V1) is null or upper(:V1)='A' or :V1 in(sql_id,''||session_id)) and 
                     sample_time+0 between nvl(to_date(:V2,'YYMMDDHH24MISS'),sysdate-1) and nvl(to_date(:V3,'YYMMDDHH24MISS'),sysdate)},
            snap={sample_time+0>=sysdate-nvl(0+:V1,30)/86400 and (:V2 is null or :V2 in(sql_id,''||session_id))},
            f={},
        }
      @counter: 11.2={1},10.1={1}
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
        round(SUM(c))                                                     Secs
      , ROUND(SUM(c) / (1+(max(sample_time+0) - min(sample_time+0)) * 86400), 1) AAS
      , LPAD(ROUND(RATIO_TO_REPORT(sum(c)) OVER () * 100)||'%',5,' ')||' |' "%This"
      , nvl2(qc_session_id,'PARALLEL','SERIAL') "Parallel?"
      , nvl(a.program#,u.username) program#
      , &V7
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
        (SELECT a.*,sql_plan_hash_value plan_hash,
            CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
              REGEXP_REPLACE(SUBSTR(a.program,INSTR(a.program,'(')), '\d', 'n')
            END program#,&counter c
           , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p1 ELSE null END, '0XXXXXXXXXXXXXXX') p1hex
           , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p2 ELSE null END, '0XXXXXXXXXXXXXXX') p2hex
           , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p3 ELSE null END, '0XXXXXXXXXXXXXXX') p3hex
        FROM &V9 a) a
      , all_users u
    WHERE a.user_id = u.user_id (+)
	AND   &V8
    GROUP BY nvl2(qc_session_id,'PARALLEL','SERIAL'),nvl(a.program#,u.username),&V7
    ORDER BY Secs DESC nulls last, &V7
)
WHERE ROWNUM <= 50;
