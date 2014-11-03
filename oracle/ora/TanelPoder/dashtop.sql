/*[[Get ASH top event. Usage: ashtop <group_columns> [sql_id] [from_time] [to_time(YYMMDDHH24MI)]
  Parameters:
      group_columns: combination of columns concated by comma. Available columns: see v$active_session_history and dba_users
  Templates:
      $1={sql_id,session_state,event} #default value
      $2={session_state,event,p1,p2,p2text,p3,p3text}
  Default Values:
      &V1: 1={$1}, 2={$2}
  Examples:
     ora ashtop = ora ashtop 1 = ora ashtop $1= ora ashtop "sql_id,session_state,event"
     ora ashtop $2=ora ashtop 2= ora ashtop "session_state,event,p1,p2,p2text,p3,p3text"
]]*/

SELECT * FROM (
    SELECT /*+ LEADING(a) USE_HASH(u) no_expand*/
        COUNT(*)                                                     Secs
      , ROUND(COUNT(*) / (1+(max(sample_time+0) - min(sample_time+0)) * 86400), 1) AAS
      , LPAD(ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100)||'%',5,' ')||' |' "%This"
      , &V1
      , SUM(CASE WHEN wait_class IS NULL           THEN 1 ELSE 0 END) "CPU"
      , SUM(CASE WHEN wait_class ='User I/O'       THEN 1 ELSE 0 END) "User I/O"
      , SUM(CASE WHEN wait_class ='Application'    THEN 1 ELSE 0 END) "Application"
      , SUM(CASE WHEN wait_class ='Concurrency'    THEN 1 ELSE 0 END) "Concurrency"
      , SUM(CASE WHEN wait_class ='Commit'         THEN 1 ELSE 0 END) "Commit"
      , SUM(CASE WHEN wait_class ='Configuration'  THEN 1 ELSE 0 END) "Configuration"
      , SUM(CASE WHEN wait_class ='Cluster'        THEN 1 ELSE 0 END) "Cluster"
      , SUM(CASE WHEN wait_class ='Idle'           THEN 1 ELSE 0 END) "Idle"
      , SUM(CASE WHEN wait_class ='Network'        THEN 1 ELSE 0 END) "Network"
      , SUM(CASE WHEN wait_class ='System I/O'     THEN 1 ELSE 0 END) "System I/O"
      , SUM(CASE WHEN wait_class ='Scheduler'      THEN 1 ELSE 0 END) "Scheduler"
      , SUM(CASE WHEN wait_class ='Administrative' THEN 1 ELSE 0 END) "Administrative"
      , SUM(CASE WHEN wait_class ='Queueing'       THEN 1 ELSE 0 END) "Queueing"
      , SUM(CASE WHEN wait_class ='Other'          THEN 1 ELSE 0 END) "Other"
      , TO_CHAR(MIN(sample_time), 'YYYY-MM-DD HH24:MI:SS') first_seen
      , TO_CHAR(MAX(sample_time), 'YYYY-MM-DD HH24:MI:SS') last_seen
    FROM
        (SELECT
             a.*
           , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p1 ELSE null END, '0XXXXXXXXXXXXXXX') p1hex
           , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p2 ELSE null END, '0XXXXXXXXXXXXXXX') p2hex
           , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p3 ELSE null END, '0XXXXXXXXXXXXXXX') p3hex
        FROM dba_hist_active_sess_history a) a
      , dba_users u
    WHERE a.user_id = u.user_id (+)
    AND sql_id=nvl(:V2,sql_id)
    and sample_time+0 between nvl(to_date(:V3,'YYMMDDHH24MISS'),sysdate-1) and nvl(to_date(:V4,'YYMMDDHH24MISS'),sysdate)
    GROUP BY &V1
    ORDER BY Secs DESC, &V1
)
WHERE ROWNUM <= 50;
