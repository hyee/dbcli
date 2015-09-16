/*[[
Show ash wait chains. Usage: ashchain [<sql_id>] [YYMMDDHH24MI [YYMMDDHH24MI]]
--[[
Templates:
      &V8: ash={gv$active_session_history},dash={Dba_Hist_Active_Sess_History}
--]]

]]*/

WITH
bclass AS (SELECT class, ROWNUM r from v$waitstat),
ash AS (SELECT /*+ QB_NAME(ash) LEADING(a) USE_HASH(u) SWAP_JOIN_INPUTS(u) */
            coalesce(sql_id,p3text,p2text,p1text) sql_id,current_obj#,sample_id,
            SESSION_ID||','||SESSION_serial# SID,
            nullif(blocking_session||','||BLOCKING_SESSION_SERIAL#,',') b_sid
          , u.username
          , CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
              REGEXP_REPLACE(SUBSTR(a.program,INSTR(a.program,'(')), '\d', 'n')
            ELSE
                '('||REGEXP_REPLACE(REGEXP_REPLACE(a.program, '(.*)@(.*)(\(.*\))', '\1'), '\d', 'n')||')'
            END || ' ' program2
          , NVL(a.event||CASE WHEN p3text='class#'
                              THEN ' ['||(SELECT class FROM bclass WHERE r = a.p3)||']' ELSE null END,'ON CPU')
                       || ' ' event2
          , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p1 ELSE null END, '0XXXXXXXXXXXXXXX') p1hex
          , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p2 ELSE null END, '0XXXXXXXXXXXXXXX') p2hex
          , TO_CHAR(CASE WHEN session_state = 'WAITING' THEN p3 ELSE null END, '0XXXXXXXXXXXXXXX') p3hex
        FROM
            &V8 a
          , dba_users u
        WHERE
            a.user_id = u.user_id (+)
        AND sample_time+0 BETWEEN NVL(TO_DATE(:V2,'YYMMDDHH24MI'),SYSDATE-1) AND NVL(TO_DATE(:V3,'YYMMDDHH24MI'),SYSDATE)
    ),
ash_samples AS (SELECT DISTINCT sample_id FROM ash),
ash_data AS (SELECT /*+ MATERIALIZE */ * FROM ash),
chains AS (
    SELECT /*+NO_EXPAND*/
        level lvl
      --, sql_id
      , sid
      , REPLACE(SYS_CONNECT_BY_PATH(sql_id, '->'), '->', ' -> ') sql_ids
      , REPLACE(SYS_CONNECT_BY_PATH(program2||event2, '->'), '->', ' -> ') path -- there's a reason why I'm doing this (ORA-30004 :)
     -- , CASE WHEN CONNECT_BY_ISLEAF = 1 THEN d.session_id ELSE NULL END sids
      , CONNECT_BY_ISLEAF isleaf
      , CONNECT_BY_ISCYCLE iscycle
      , d.*
    FROM
        ash_samples s
      , ash_data d
    WHERE
        s.sample_id = d.sample_id
    CONNECT BY NOCYCLE
        (    PRIOR d.b_sid = d.sid
        -- AND PRIOR d.blocking_inst_id = d.inst_id
         AND PRIOR s.sample_id = d.sample_id
        )
     START WITH (:V1 is null and b_sid is not null or sql_id=:V1)
)
SELECT * FROM (
    SELECT
        LPAD(ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100)||'%',5,' ') "%This"
      , COUNT(*) seconds
      --, COUNT(DISTINCT sql_exec_id) execs
      , (SELECT nvl(max(object_name),''||current_obj#) FROM all_objects WHERE object_id=current_obj#) obj#
    --  , ROUND(COUNT(*) / ((MAX(sample_time+0)-MIN(sample_time+0)) * 86400), 1) AAS
      , sql_ids
      , path wait_chain
    FROM
        chains
    WHERE
        isleaf = 1
    GROUP BY
        current_obj#
      , path,sql_ids
    ORDER BY
        COUNT(*) DESC
    )
WHERE
    ROWNUM <= 50